import Foundation

/// Centralized, idempotent preferences migrations. New versions append a small
/// migration here instead of scattering one-off compatibility checks in views.
enum AppMigration {
    private static let versionKey = "AppleIntSchemaVersion"
    private static let currentVersion = 2

    static func run() {
        let defaults = UserDefaults.standard
        let installed = defaults.integer(forKey: versionKey)
        guard installed < currentVersion else { return }
        defer { defaults.set(currentVersion, forKey: versionKey) }

        // Preserve an existing composer choice made before the setting became
        // explicitly versioned.
        if defaults.object(forKey: "extendedTextBox.v2") == nil,
           defaults.object(forKey: "extendedTextBox") != nil {
            defaults.set(defaults.bool(forKey: "extendedTextBox"), forKey: "extendedTextBox.v2")
        }

        // Version 2 retires the Local Data Vault. Advanced Memory is the only
        // durable memory system, so delete the old values and toggle once.
        defaults.removeObject(forKey: "ToolRequestPersistedValues")
        defaults.removeObject(forKey: "enableAdvancedMemory")
    }
}
