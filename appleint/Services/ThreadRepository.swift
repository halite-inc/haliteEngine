import Foundation

protocol ThreadPersisting: AnyObject {
    func load(from source: URL) throws -> [ChatThread]
    func scheduleSave(_ threads: [ChatThread], to destination: URL)
    func flush()
    func lastErrorDescription() -> String?
}

/// Serial, debounced persistence for chat snapshots. Only the most recent
/// snapshot is written during a burst of streaming/UI updates.
final class ThreadRepository: ThreadPersisting {
    private let queue = DispatchQueue(label: "com.halite.appleint.thread-repository", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private var pendingWrite: DispatchWorkItem?
    private var latestSnapshot: [ChatThread] = []
    private var latestDestination: URL?
    private var persistenceError: String?

    init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    func load(from source: URL) throws -> [ChatThread] {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        return try JSONDecoder().decode([ChatThread].self, from: data)
    }

    func scheduleSave(_ threads: [ChatThread], to destination: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.latestSnapshot = threads
            self.latestDestination = destination
            self.pendingWrite?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.writeLatestSnapshot() }
            self.pendingWrite = work
            self.queue.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    func flush() {
        // App deactivation/termination needs a real durability boundary.
        let operation = { [weak self] in
            guard let self else { return }
            self.pendingWrite?.cancel()
            self.pendingWrite = nil
            self.writeLatestSnapshot()
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            operation()
        } else {
            queue.sync(execute: operation)
        }
    }

    func lastErrorDescription() -> String? {
        let operation = { [weak self] in self?.persistenceError }
        if DispatchQueue.getSpecific(key: queueKey) != nil { return operation() }
        return queue.sync(execute: operation)
    }

    private func writeLatestSnapshot() {
        guard let destination = latestDestination else { return }
        do {
            let data = try JSONEncoder().encode(latestSnapshot)
            try data.write(to: destination, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            print("Failed to save threads: \(error)")
        }
    }
}
