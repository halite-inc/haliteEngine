import Foundation

/// Privacy-safe, bounded feedback loop. It learns operational patterns from
/// outcomes and exposes recommendations for the user/developer to approve;
/// it never changes prompts, files, credentials, or permissions by itself.
actor AgentLearningStore {
    struct Outcome: Codable, Sendable {
        let toolName: String
        let succeeded: Bool
        let duration: TimeInterval
    }

    private var outcomes: [Outcome] = []
    private let limit = 500

    func record(toolName: String, succeeded: Bool, duration: TimeInterval) {
        outcomes.append(.init(toolName: toolName, succeeded: succeeded, duration: duration))
        if outcomes.count > limit { outcomes.removeFirst(outcomes.count - limit) }
    }

    func recommendations() -> [String] {
        let grouped = Dictionary(grouping: outcomes, by: \.toolName)
        return grouped.compactMap { name, values in
            let failures = values.filter { !$0.succeeded }.count
            guard values.count >= 3, Double(failures) / Double(values.count) >= 0.4 else { return nil }
            return "Review \(name): \(failures) of \(values.count) recent runs failed. Consider improving validation or adding a confirmation step."
        }.sorted()
    }
}
