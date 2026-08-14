import Foundation

protocol CredentialStoring: Sendable {
    func isConfigured(_ account: String) -> Bool
    func reconcileConfigurationStatus(for accounts: [String])
    func value(for account: String) -> String
    func set(_ value: String, for account: String)
    func migrateLegacyDefaults(_ defaultsKey: String, account: String) -> String
}

/// Injectable adapter used by the application layer. The legacy static store
/// remains the single implementation of the on-disk format so this boundary
/// can be introduced without a credential migration.
struct LiveCredentialStore: CredentialStoring {
    func isConfigured(_ account: String) -> Bool { CredentialStore.isConfigured(account) }
    func reconcileConfigurationStatus(for accounts: [String]) { CredentialStore.reconcileConfigurationStatus(for: accounts) }
    func value(for account: String) -> String { CredentialStore.value(for: account) }
    func set(_ value: String, for account: String) { CredentialStore.set(value, for: account) }
    func migrateLegacyDefaults(_ defaultsKey: String, account: String) -> String {
        CredentialStore.migrateLegacyDefaults(defaultsKey, account: account)
    }
}

/// Stores app credentials in an owner-readable application-support file.
///
/// Debug builds are re-signed whenever they are compiled. Login Keychain items
/// bind access to that changing signature, which makes macOS repeatedly ask the
/// user for their Keychain password. A private 0600 file keeps credentials out
/// of preferences and model prompts without producing authorization dialogs.
enum CredentialStore {
    private static let configuredPrefix = "CredentialStore.configured."
    private static let lock = NSLock()

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("AppleIntChat", isDirectory: true)
            .appendingPathComponent("credentials.json", isDirectory: false)
    }

    static func isConfigured(_ account: String) -> Bool {
        UserDefaults.standard.bool(forKey: configuredPrefix + account)
    }

    static func reconcileConfigurationStatus(for accounts: [String]) {
        for account in accounts {
            UserDefaults.standard.set(!value(for: account).isEmpty, forKey: configuredPrefix + account)
        }
    }

    static func value(for account: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return readStore()[account] ?? ""
    }

    static func set(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        var values = readStore()
        if trimmed.isEmpty {
            values.removeValue(forKey: account)
        } else {
            values[account] = trimmed
        }
        writeStore(values)
        lock.unlock()
        UserDefaults.standard.set(!trimmed.isEmpty, forKey: configuredPrefix + account)
    }

    /// One-time migration for values saved in preferences by early builds.
    static func migrateLegacyDefaults(_ defaultsKey: String, account: String) -> String {
        let existing = value(for: account)
        guard existing.isEmpty else { return existing }
        let legacy = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        guard !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        set(legacy, for: account)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return value(for: account)
    }

    private static func readStore() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func writeStore(_ values: [String: String]) {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard let data = try? JSONEncoder().encode(values) else { return }
        do {
            try data.write(to: storeURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        } catch {
            assertionFailure("Unable to save credentials: \(error.localizedDescription)")
        }
    }
}
