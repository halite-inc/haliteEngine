import Foundation

struct DiagnosticEvent: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let category: String
    let message: String
    let threadID: UUID?

    nonisolated init(category: String, message: String, threadID: UUID? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.category = category
        self.message = message
        self.threadID = threadID
    }
}

/// Bounded, privacy-safe operational history. It records lifecycle metadata,
/// never prompts, message bodies, API keys, tool payloads, or file contents.
actor DiagnosticsStore {
    private var events: [DiagnosticEvent] = []
    private let limit = 300

    func record(category: String, message: String, threadID: UUID? = nil) {
        events.append(DiagnosticEvent(category: category, message: message, threadID: threadID))
        if events.count > limit { events.removeFirst(events.count - limit) }
    }

    func exportJSON() throws -> Data {
        try JSONEncoder().encode(events)
    }
}
