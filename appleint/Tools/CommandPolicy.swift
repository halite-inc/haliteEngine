import Foundation

/// Guardrails for commands requested by a model. Manual terminal input remains
/// user-controlled; automated commands must be scoped and non-destructive.
enum CommandPolicy {
    enum Decision { case allow, requiresConfirmation(String), block(String) }

    static func evaluate(_ rawCommand: String) -> Decision {
        let command = rawCommand.lowercased()
        
        // Block subshell / eval / backtick evasion patterns that could
        // wrap any destructive or prohibited command past keyword filters.
        let evasionPatterns = ["$(", "`", "eval ", "eval\t", "xargs ", "| sh", "| bash", "| zsh", "exec "]
        if evasionPatterns.contains(where: { command.contains($0) }) {
            return .requiresConfirmation("This command uses indirect execution (subshell, eval, or pipe-to-shell) which could run arbitrary operations. Ask the user for explicit confirmation.")
        }
        
        let destructive = ["rm ", "rm -", "trash ", "rmdir ", "mkfs", "diskutil erase", "dd if=", "chmod -r", "chown -r", "> /dev/", "git reset --hard"]
        if destructive.contains(where: { command.contains($0) }) {
            return .requiresConfirmation("This command can permanently delete, overwrite, or alter data. Ask the user for explicit confirmation before running it.")
        }
        let prohibited = ["sudo ", "launchctl", "killall", "pkill"]
        if prohibited.contains(where: { command.contains($0) }) {
            return .block("This command is not permitted for automated execution.")
        }
        return .allow
    }
}
