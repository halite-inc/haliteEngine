import Foundation

/// All durable locations owned by the application. Keeping paths here avoids
/// features inventing their own storage roots and makes previews/tests fully
/// isolated by supplying a temporary root directory.
struct AppPaths: Sendable {
    let rootDirectory: URL

    var threads: URL { rootDirectory.appendingPathComponent("threads.json", isDirectory: false) }
    var globalMemory: URL { rootDirectory.appendingPathComponent("global_memory_graph.json", isDirectory: false) }
    var attachments: URL { rootDirectory.appendingPathComponent("attachments", isDirectory: true) }
    var terminalAudit: URL { rootDirectory.appendingPathComponent("terminal-audit.jsonl", isDirectory: false) }

    static func live(fileManager: FileManager = .default) -> AppPaths {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return AppPaths(rootDirectory: base.appendingPathComponent("AppleIntChat", isDirectory: true))
    }

    func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.createDirectory(
            at: attachments,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}

/// The application composition root. Features receive capabilities from this
/// value rather than reaching for global singletons, which keeps ownership and
/// lifecycle visible and makes deterministic tests possible.
struct AppDependencies {
    let preferences: UserDefaults
    let networkSession: URLSession
    let fileManager: FileManager
    let paths: AppPaths
    let credentials: any CredentialStoring
    let threadRepository: any ThreadPersisting
    let diagnostics: DiagnosticsStore
    let learningStore: AgentLearningStore
    let modelDiscovery: ModelDiscoveryService
    let providerHealth: ProviderHealthService
    let attachmentStore: any AttachmentStoring
    let toolRequestManager: ToolRequestManager

    @MainActor
    static func live(
        preferences: UserDefaults = .standard,
        networkSession: URLSession = .shared,
        fileManager: FileManager = .default
    ) -> AppDependencies {
        let paths = AppPaths.live(fileManager: fileManager)
        do {
            try paths.prepare(fileManager: fileManager)
        } catch {
            assertionFailure("Unable to prepare application storage: \(error.localizedDescription)")
        }

        return AppDependencies(
            preferences: preferences,
            networkSession: networkSession,
            fileManager: fileManager,
            paths: paths,
            credentials: LiveCredentialStore(),
            threadRepository: ThreadRepository(),
            diagnostics: DiagnosticsStore(),
            learningStore: AgentLearningStore(),
            modelDiscovery: ModelDiscoveryService(networkSession: networkSession),
            providerHealth: ProviderHealthService(networkSession: networkSession),
            attachmentStore: AttachmentStore(directory: paths.attachments, fileManager: fileManager),
            toolRequestManager: ToolRequestManager()
        )
    }
}

/// Performs ordered startup work before constructing stateful features.
@MainActor
enum AppBootstrapper {
    static func makeChatManager() -> ChatManager {
        AppMigration.run()
        return ChatManager(dependencies: .live())
    }
}
