import Foundation

public struct AppleNotesError: LocalizedError, CustomStringConvertible {
    public let message: String
    public var errorDescription: String? { message }
    public var description: String { message }
    
    public init(_ message: String) {
        self.message = message
    }
}

/// Native macOS Apple Notes integration skill.
/// Executes direct AppleScript automation to interact with Notes.app.
public enum AppleNotesSkill {
    public static let instructions = """
    PURPOSE
    Interact directly with Apple Notes on macOS to create, search, read, append, and organize personal notes and folders.

    AVAILABLE ACTIONS
    • `list` — List notes with titles, folders, and modification dates. Optional parameters: `folder`, `limit`.
    • `search` — Search notes matching a query in title or body. Parameter: `query`, optional `limit`.
    • `read` (or `get_note`) — Read full note content and metadata. Parameter: `title` or `noteId`.
    • `create` — Create a new note. Parameters: `title`, `content`, optional `folder`.
    • `append` — Append text/items to an existing note. Parameters: `title` (or `noteId`), `content`.
    • `folders` — List all folders across all accounts in Apple Notes.
    • `delete` — Move a note to Recently Deleted. Parameter: `title` or `noteId`.
    • `show` — Open and focus a note in Notes.app. Parameter: `title` or `noteId`.

    TOOL USAGE
    Emit a tool JSON object:
    {"type": "apple_notes", "action": "create", "title": "Meeting Summary", "content": "Key takeaways...", "folder": "Work"}
    {"type": "apple_notes", "action": "search", "query": "project roadmap"}
    {"type": "apple_notes", "action": "read", "title": "Meeting Summary"}
    {"type": "apple_notes", "action": "append", "title": "Todo List", "content": "- Review PR #42"}
    {"type": "apple_notes", "action": "list"}
    {"type": "apple_notes", "action": "folders"}
    """

    // MARK: - Core AppleScript Runner

    /// Runs an AppleScript script string and returns stdout or throws an AppleNotesError.
    private static func runAppleScript(_ script: String) -> Result<String, AppleNotesError> {
        var errorDict: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let outputDescriptor = scriptObject.executeAndReturnError(&errorDict)
            if let error = errorDict {
                let errorMsg = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
                return .failure(AppleNotesError(errorMsg))
            }
            return .success(outputDescriptor.stringValue ?? "")
        }

        // Fallback to Process /usr/bin/osascript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

            if process.terminationStatus != 0 {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errOutput = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? "Process exited with code \(process.terminationStatus)"
                return .failure(AppleNotesError(errOutput))
            }
            return .success(output)
        } catch {
            return .failure(AppleNotesError("Failed to execute osascript: \(error.localizedDescription)"))
        }
    }

    /// Escapes string for AppleScript double-quoted string literals.
    private static func escapeForAppleScript(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
           .replacingOccurrences(of: "\r", with: "\\r")
           .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - Public Skill Actions

    /// Lists folders across all accounts.
    public static func listFolders() -> [String] {
        let script = """
        tell application "Notes"
            set folderList to {}
            repeat with acc in accounts
                repeat with f in folders of acc
                    set end of folderList to (name of f as string)
                end repeat
            end repeat
            set AppleScript's text item delimiters to "|||"
            return folderList as string
        end tell
        """
        switch runAppleScript(script) {
        case .success(let output):
            guard !output.isEmpty else { return [] }
            return output.components(separatedBy: "|||")
                         .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                         .filter { !$0.isEmpty }
        case .failure:
            return []
        }
    }

    /// Lists notes, optionally filtered by folder and limited in count.
    public static func listNotes(folder: String? = nil, limit: Int = 25) -> [[String: Any]] {
        let folderFilterScript: String
        if let folder = folder, !folder.isEmpty {
            let escapedFolder = escapeForAppleScript(folder)
            folderFilterScript = "set targetNotes to notes of folder \"\(escapedFolder)\""
        } else {
            folderFilterScript = "set targetNotes to every note"
        }

        let script = """
        tell application "Notes"
            \(folderFilterScript)
            set noteCount to count of targetNotes
            set maxCount to \(limit)
            if noteCount < maxCount then set maxCount to noteCount
            set outList to {}
            repeat with i from 1 to maxCount
                set n to item i of targetNotes
                set nId to id of n as string
                set nName to name of n as string
                set nDate to modification date of n as string
                set nFolder to name of container of n as string
                set end of outList to nId & ":::" & nName & ":::" & nFolder & ":::" & nDate
            end repeat
            set AppleScript's text item delimiters to "|||"
            return outList as string
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            guard !output.isEmpty else { return [] }
            let items = output.components(separatedBy: "|||")
            return items.compactMap { item -> [String: Any]? in
                let parts = item.components(separatedBy: ":::")
                guard parts.count >= 2 else { return nil }
                var dict: [String: Any] = [
                    "id": parts[0],
                    "title": parts[1]
                ]
                if parts.count >= 3 { dict["folder"] = parts[2] }
                if parts.count >= 4 { dict["modificationDate"] = parts[3] }
                return dict
            }
        case .failure:
            return []
        }
    }

    /// Searches notes by query in title and plaintext body.
    public static func searchNotes(query: String, limit: Int = 15) -> [[String: Any]] {
        let escapedQuery = escapeForAppleScript(query)
        let script = """
        tell application "Notes"
            set matchedNotes to {}
            set q to "\(escapedQuery)"
            repeat with n in (every note)
                set nName to name of n as string
                set nBody to plaintext of n as string
                if (nName contains q) or (nBody contains q) then
                    set nId to id of n as string
                    set nFolder to name of container of n as string
                    set nDate to modification date of n as string
                    set end of matchedNotes to nId & ":::" & nName & ":::" & nFolder & ":::" & nDate
                    if (count of matchedNotes) >= \(limit) then exit repeat
                end if
            end repeat
            set AppleScript's text item delimiters to "|||"
            return matchedNotes as string
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            guard !output.isEmpty else { return [] }
            let items = output.components(separatedBy: "|||")
            return items.compactMap { item -> [String: Any]? in
                let parts = item.components(separatedBy: ":::")
                guard parts.count >= 2 else { return nil }
                var dict: [String: Any] = [
                    "id": parts[0],
                    "title": parts[1]
                ]
                if parts.count >= 3 { dict["folder"] = parts[2] }
                if parts.count >= 4 { dict["modificationDate"] = parts[3] }
                return dict
            }
        case .failure:
            return []
        }
    }

    /// Reads full content of a note by title or ID.
    public static func readNote(titleOrId: String) -> [String: Any]? {
        let escaped = escapeForAppleScript(titleOrId)
        let script = """
        tell application "Notes"
            set foundNote to missing value
            if "\(escaped)" starts with "x-coredata://" or "\(escaped)" contains "/" then
                try
                    set foundNote to note id "\(escaped)"
                end try
            end if
            if foundNote is missing value then
                set nList to (notes whose name is "\(escaped)")
                if (count of nList) > 0 then
                    set foundNote to item 1 of nList
                else
                    set nList to (notes whose name contains "\(escaped)")
                    if (count of nList) > 0 then
                        set foundNote to item 1 of nList
                    end if
                end if
            end if
            
            if foundNote is missing value then
                return "NOTE_NOT_FOUND"
            end if
            
            set nId to id of foundNote as string
            set nName to name of foundNote as string
            set nFolder to name of container of foundNote as string
            set nDate to modification date of foundNote as string
            set nCreate to creation date of foundNote as string
            set nBody to plaintext of foundNote as string
            
            set AppleScript's text item delimiters to ":::NOTE_DELIM:::"
            return nId & ":::NOTE_DELIM:::" & nName & ":::NOTE_DELIM:::" & nFolder & ":::NOTE_DELIM:::" & nDate & ":::NOTE_DELIM:::" & nCreate & ":::NOTE_DELIM:::" & nBody
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            if output == "NOTE_NOT_FOUND" || output.isEmpty {
                return nil
            }
            let parts = output.components(separatedBy: ":::NOTE_DELIM:::")
            guard parts.count >= 2 else { return nil }
            return [
                "id": parts[0],
                "title": parts[1],
                "folder": parts.count > 2 ? parts[2] : "Notes",
                "modificationDate": parts.count > 3 ? parts[3] : "",
                "creationDate": parts.count > 4 ? parts[4] : "",
                "body": parts.count > 5 ? parts[5] : ""
            ]
        case .failure:
            return nil
        }
    }

    /// Creates a new note in Notes.app.
    public static func createNote(title: String, content: String, folder: String? = nil) -> Result<[String: Any], AppleNotesError> {
        let fullBodyText: String
        let trimmedTitle = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if trimmedContent.hasPrefix(trimmedTitle) {
            fullBodyText = trimmedContent
        } else if trimmedTitle.isEmpty {
            fullBodyText = trimmedContent
        } else {
            fullBodyText = "\(trimmedTitle)\n\n\(trimmedContent)"
        }

        let escapedBody = escapeForAppleScript(fullBodyText)
        let folderTargetScript: String
        if let folder = folder, !folder.isEmpty {
            let escapedFolder = escapeForAppleScript(folder)
            folderTargetScript = """
            set targetFolder to missing value
            repeat with acc in accounts
                repeat with f in folders of acc
                    if name of f is "\(escapedFolder)" then
                        set targetFolder to f
                        exit repeat
                    end if
                end repeat
                if targetFolder is not missing value then exit repeat
            end repeat
            if targetFolder is missing value then
                set targetFolder to default folder of default account
            end if
            set newNote to make new note at targetFolder with properties {body:"\(escapedBody)"}
            """
        } else {
            folderTargetScript = """
            set newNote to make new note with properties {body:"\(escapedBody)"}
            """
        }

        let script = """
        tell application "Notes"
            \(folderTargetScript)
            set nId to id of newNote as string
            set nName to name of newNote as string
            set nFolder to name of container of newNote as string
            set nDate to modification date of newNote as string
            return nId & ":::" & nName & ":::" & nFolder & ":::" & nDate
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            let parts = output.components(separatedBy: ":::")
            let noteInfo: [String: Any] = [
                "id": parts.count > 0 ? parts[0] : "",
                "title": parts.count > 1 ? parts[1] : trimmedTitle,
                "folder": parts.count > 2 ? parts[2] : (folder ?? "Notes"),
                "modificationDate": parts.count > 3 ? parts[3] : ""
            ]
            return .success(noteInfo)
        case .failure(let err):
            return .failure(AppleNotesError("Failed to create note: \(err.message)"))
        }
    }

    /// Appends text to an existing note.
    public static func appendNote(titleOrId: String, content: String) -> Result<[String: Any], AppleNotesError> {
        let escapedTarget = escapeForAppleScript(titleOrId)
        let escapedContent = escapeForAppleScript(content)

        let script = """
        tell application "Notes"
            set targetNote to missing value
            if "\(escapedTarget)" starts with "x-coredata://" or "\(escapedTarget)" contains "/" then
                try
                    set targetNote to note id "\(escapedTarget)"
                end try
            end if
            if targetNote is missing value then
                set nList to (notes whose name is "\(escapedTarget)")
                if (count of nList) > 0 then
                    set targetNote to item 1 of nList
                else
                    set nList to (notes whose name contains "\(escapedTarget)")
                    if (count of nList) > 0 then
                        set targetNote to item 1 of nList
                    end if
                end if
            end if
            
            if targetNote is missing value then
                return "NOTE_NOT_FOUND"
            end if
            
            set oldBody to plaintext of targetNote as string
            set newBody to oldBody & "\n\n" & "\(escapedContent)"
            set body of targetNote to newBody
            
            set nId to id of targetNote as string
            set nName to name of targetNote as string
            set nFolder to name of container of targetNote as string
            set nDate to modification date of targetNote as string
            return nId & ":::" & nName & ":::" & nFolder & ":::" & nDate
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            if output == "NOTE_NOT_FOUND" {
                return .failure(AppleNotesError("Note not found matching '\(titleOrId)'."))
            }
            let parts = output.components(separatedBy: ":::")
            return .success([
                "id": parts.count > 0 ? parts[0] : "",
                "title": parts.count > 1 ? parts[1] : titleOrId,
                "folder": parts.count > 2 ? parts[2] : "Notes",
                "modificationDate": parts.count > 3 ? parts[3] : ""
            ])
        case .failure(let err):
            return .failure(AppleNotesError("Failed to append to note: \(err.message)"))
        }
    }

    /// Deletes a note by title or ID.
    public static func deleteNote(titleOrId: String) -> Result<String, AppleNotesError> {
        let escapedTarget = escapeForAppleScript(titleOrId)
        let script = """
        tell application "Notes"
            set targetNote to missing value
            if "\(escapedTarget)" starts with "x-coredata://" or "\(escapedTarget)" contains "/" then
                try
                    set targetNote to note id "\(escapedTarget)"
                end try
            end if
            if targetNote is missing value then
                set nList to (notes whose name is "\(escapedTarget)")
                if (count of nList) > 0 then
                    set targetNote to item 1 of nList
                end if
            end if
            
            if targetNote is missing value then
                return "NOTE_NOT_FOUND"
            end if
            
            set deletedName to name of targetNote as string
            delete targetNote
            return deletedName
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            if output == "NOTE_NOT_FOUND" {
                return .failure(AppleNotesError("Note not found matching '\(titleOrId)'."))
            }
            return .success(output)
        case .failure(let err):
            return .failure(AppleNotesError("Failed to delete note: \(err.message)"))
        }
    }

    /// Focuses/opens a note in Notes.app.
    public static func showNote(titleOrId: String) -> Result<String, AppleNotesError> {
        let escapedTarget = escapeForAppleScript(titleOrId)
        let script = """
        tell application "Notes"
            activate
            set targetNote to missing value
            if "\(escapedTarget)" starts with "x-coredata://" or "\(escapedTarget)" contains "/" then
                try
                    set targetNote to note id "\(escapedTarget)"
                end try
            end if
            if targetNote is missing value then
                set nList to (notes whose name is "\(escapedTarget)")
                if (count of nList) > 0 then
                    set targetNote to item 1 of nList
                end if
            end if
            
            if targetNote is not missing value then
                show targetNote
                return "SHOWN"
            else
                return "NOTE_NOT_FOUND"
            end if
        end tell
        """

        switch runAppleScript(script) {
        case .success(let output):
            if output == "NOTE_NOT_FOUND" {
                return .failure(AppleNotesError("Note not found matching '\(titleOrId)'."))
            }
            return .success("Note displayed in Apple Notes.")
        case .failure(let err):
            return .failure(AppleNotesError("Failed to show note: \(err.message)"))
        }
    }

    // MARK: - Central Execution Router

    /// Dispatches a ToolRequest for Apple Notes and returns a structured JSON string.
    public static func execute(action: String, title: String? = nil, content: String? = nil, folder: String? = nil, query: String? = nil, noteId: String? = nil) -> String {
        let canonicalAction = action.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()

        var responsePayload: [String: Any] = [:]

        switch canonicalAction {
        case "list", "list_notes", "get_notes":
            let notes = listNotes(folder: folder)
            responsePayload = [
                "action": "list",
                "folder": folder ?? "All",
                "count": notes.count,
                "notes": notes
            ]

        case "folders", "list_folders", "get_folders":
            let folderList = listFolders()
            responsePayload = [
                "action": "folders",
                "count": folderList.count,
                "folders": folderList
            ]

        case "search", "search_notes", "find_notes", "find":
            let searchQuery = query ?? title ?? content ?? ""
            if searchQuery.isEmpty {
                responsePayload = ["error": "Search query parameter is required."]
            } else {
                let results = searchNotes(query: searchQuery)
                responsePayload = [
                    "action": "search",
                    "query": searchQuery,
                    "count": results.count,
                    "results": results
                ]
            }

        case "read", "read_note", "get_note", "get":
            let target = noteId ?? title ?? query ?? ""
            if target.isEmpty {
                responsePayload = ["error": "Note title or noteId parameter is required to read a note."]
            } else if let note = readNote(titleOrId: target) {
                responsePayload = [
                    "action": "read",
                    "note": note
                ]
            } else {
                responsePayload = ["error": "Note not found matching '\(target)'."]
            }

        case "create", "create_note", "new_note", "add_note", "write_note":
            let noteTitle = title ?? "Untitled Note"
            let noteContent = content ?? ""
            switch createNote(title: noteTitle, content: noteContent, folder: folder) {
            case .success(let noteInfo):
                responsePayload = [
                    "action": "create",
                    "status": "success",
                    "message": "Note created successfully in Apple Notes.",
                    "note": noteInfo
                ]
            case .failure(let err):
                responsePayload = [
                    "action": "create",
                    "status": "error",
                    "error": err.message
                ]
            }

        case "append", "append_note", "update_note", "add_to_note":
            let target = noteId ?? title ?? ""
            let appendText = content ?? query ?? ""
            if target.isEmpty || appendText.isEmpty {
                responsePayload = ["error": "Both target note title/noteId and content are required to append to a note."]
            } else {
                switch appendNote(titleOrId: target, content: appendText) {
                case .success(let noteInfo):
                    responsePayload = [
                        "action": "append",
                        "status": "success",
                        "message": "Content appended successfully to Apple Note.",
                        "note": noteInfo
                    ]
                case .failure(let err):
                    responsePayload = [
                        "action": "append",
                        "status": "error",
                        "error": err.message
                    ]
                }
            }

        case "delete", "delete_note", "remove_note":
            let target = noteId ?? title ?? ""
            if target.isEmpty {
                responsePayload = ["error": "Note title or noteId parameter is required to delete a note."]
            } else {
                switch deleteNote(titleOrId: target) {
                case .success(let deletedName):
                    responsePayload = [
                        "action": "delete",
                        "status": "success",
                        "message": "Note '\(deletedName)' moved to Recently Deleted in Apple Notes."
                    ]
                case .failure(let err):
                    responsePayload = [
                        "action": "delete",
                        "status": "error",
                        "error": err.message
                    ]
                }
            }

        case "show", "show_note", "open_note", "open":
            let target = noteId ?? title ?? ""
            switch showNote(titleOrId: target) {
            case .success(let msg):
                responsePayload = [
                    "action": "show",
                    "status": "success",
                    "message": msg
                ]
            case .failure(let err):
                responsePayload = [
                    "action": "show",
                    "status": "error",
                    "error": err.message
                ]
            }

        default:
            responsePayload = [
                "error": "Unknown Apple Notes action '\(action)'. Supported actions: list, search, read, create, append, folders, delete, show."
            ]
        }

        let wrapped: [String: Any] = ["tool_response": responsePayload]
        if let jsonData = try? JSONSerialization.data(withJSONObject: wrapped, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            return jsonStr
        }
        return "{\"tool_response\": {\"status\": \"completed\"}}"
    }
}
