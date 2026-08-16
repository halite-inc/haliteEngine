import Foundation

/// Deterministic filesystem recipes live in Swift, not a large model prompt.
enum FileSystemSkill {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif"]
    static let instructions = """
    PURPOSE
    Handle local files and folders quickly, safely, and deterministically. Route filesystem requests through `file_system`; choose the smallest verified action that satisfies the user’s actual request.

    AVAILABLE ACTIONS
    • `list` — inspect a directory before making assumptions.
    • `read_file` — read a requested text file.
    • `create_folder` — create a requested folder, including parents.
    • `create_file` — create or write a requested file.
    • `create_files` — create and verify up to 12 related text files in one call; prefer this for multi-file coding projects.
    • `execute_command` — use only when a native action cannot complete the work.
    • Action identifiers are exact. Never invent or substitute synonyms such as `create_directory`; the directory-creation action is always `create_folder`.
    • `organize_images` — move image files from a requested Downloads location into `Images`.
    • `organize_directory` — sort recognized files in the requested supported folder into clear media, document, project, design, code, font, archive, and installer folders.

    WORKFLOW
    1. Read the user’s scope exactly: target folder, file types, and desired outcome.
    2. Inspect first when the file state matters; do not guess filenames or paths.
    3. Use a native action or deterministic skill before constructing a shell command.
    4. For shell work, use one short, idempotent, scoped command. Never use an unbounded path, broad recursive operation, or fragile glob when a safe alternative exists.
    5. Verify the result mechanically: file exists, directory exists, move succeeded, command exit code is zero, or expected contents changed.
    6. Report only the verified outcome. Do not answer with a plan or claim success before verification.

    COMPLEX REQUESTS
    • For requests with multiple rules (for example: organize by project, rename, detect duplicates, preserve selected files, use dates, or create nested folders), inspect the target with `list` first.
    • Convert the inspection into the smallest safe sequence: create folders, move/rename one scoped group at a time, then verify each result.
    • Use `execute_command` only for work native actions cannot express. Quote every path, use `find … -maxdepth 1` for loose-file work, avoid fragile globs, and never combine unrelated destructive operations.
    • If the requested classification depends on file contents, ambiguous names, or user preferences, inspect and ask one focused question instead of guessing.

    ORGANIZATION RULES
    • Explicit “images/photos/pictures” requests use `organize_images` only.
    • Generic “organize files” requests use `organize_directory` with the exact requested folder path.
    • Preserve unknown file types and folders unless the user explicitly asks to handle them, and report their extensions so the user can decide.
    • Never overwrite a file: resolve name collisions with a numbered suffix.
    • Keep operations at the requested directory level unless recursion is explicitly requested.

    SAFETY
    • Never delete, overwrite, replace, empty, or recursively modify user data unless the user explicitly asks.
    • Treat credentials, keys, hidden files, and system directories as sensitive; do not expose their contents unnecessarily.
    • Stop and return a structured error for invalid paths, missing files, permission failures, timeouts, or failed verification.
    • Terminal output is bounded; inspect the result and use a changed approach rather than repeating an identical failed command.

    RESPONSE STYLE
    Execute first. Then give a concise outcome: what changed, where it changed, how many files were affected, and any actionable error. Never expose a shell plan as the final response.
    """

    static func routedAction(for userGoal: String) -> (action: String, path: String)? {
        let goal = userGoal.lowercased()
        guard goal.contains("organize") else { return nil }
        let path: String
        if goal.contains("download") { path = "~/Downloads" }
        else if goal.contains("document") { path = "~/Documents" }
        else if goal.contains("desktop") { path = "~/Desktop" }
        else { return nil }
        // Preserve the zero-model fast path for straightforward requests.
        // Any extra rule belongs to the model-driven inspect/act/verify loop.
        let complexTerms = [" by ", "rename", "duplicate", "project", "nested", "subfolder", "date", "oldest", "newest", "except", "exclude", "only ", "keep ", "merge", "content", "filename", "similar"]
        guard !complexTerms.contains(where: { goal.contains($0) }) else { return nil }
        let imagesOnly = goal.contains("image") || goal.contains("photo") || goal.contains("picture")
        return (imagesOnly ? "organize_images" : "organize_directory", path)
    }

    /// Deterministic route for a small, unambiguous scaffold request such as
    /// "create a folder project_x and create main.py inside it". Keeping this
    /// out of model tool-call formatting makes the basic operation reliable.
    static func routedSimpleCreation(for userGoal: String) -> (folder: String, filename: String?)? {
        let lower = userGoal.lowercased()
        guard lower.contains("create") || lower.contains("make"),
              lower.contains("folder") || lower.contains("directory") else { return nil }

        let folderPattern = #"(?i)\b(?:folder|directory)\s+(?:(?:called|named)\s+)?[\"']?([a-z0-9][a-z0-9._-]*)"#
        guard let folderRegex = try? NSRegularExpression(pattern: folderPattern),
              let folderMatch = folderRegex.firstMatch(in: userGoal, range: NSRange(userGoal.startIndex..., in: userGoal)),
              let folderRange = Range(folderMatch.range(at: 1), in: userGoal) else { return nil }
        let folder = String(userGoal[folderRange])

        let filePattern = #"(?i)\b([a-z0-9][a-z0-9._-]*\.[a-z0-9]+)\b"#
        let filename: String? = {
            guard lower.contains("inside"),
                  let fileRegex = try? NSRegularExpression(pattern: filePattern),
                  let fileMatch = fileRegex.firstMatch(in: userGoal, range: NSRange(userGoal.startIndex..., in: userGoal)),
                  let fileRange = Range(fileMatch.range(at: 1), in: userGoal) else { return nil }
            return String(userGoal[fileRange])
        }()
        return (folder, filename)
    }

    static func organizeImages(in rawPath: String) -> String {
        let root = (rawPath as NSString).expandingTildeInPath
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else { return "Error: Directory does not exist at path: \(rawPath)" }
        let destination = URL(fileURLWithPath: root).appendingPathComponent("Images", isDirectory: true)
        do {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            let entries = try manager.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            let images = try entries.filter { url in
                guard imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
                return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }
            var moved: [String] = []
            for source in images {
                var target = destination.appendingPathComponent(source.lastPathComponent); var suffix = 2
                while manager.fileExists(atPath: target.path) { target = destination.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) \(suffix).\(source.pathExtension)"); suffix += 1 }
                try manager.moveItem(at: source, to: target)
                guard manager.fileExists(atPath: target.path) else { return "Error: Could not verify moved file \(source.lastPathComponent)." }
                moved.append(target.lastPathComponent)
            }
            return moved.isEmpty ? "No image files were found in \(rawPath)." : "Moved \(moved.count) image file(s) into \(destination.path): \(moved.joined(separator: ", "))"
        } catch { return "Error organizing images: \(error.localizedDescription)" }
    }

    static func organizeDownloads(in rawPath: String) -> String {
        let categories: [(folder: String, extensions: Set<String>)] = [
            ("Images", imageExtensions),
            ("Documents", ["pdf", "doc", "docx", "txt", "rtf", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "csv", "tsv", "odt", "ods", "odp", "epub"]),
            ("Archives", ["zip", "rar", "7z", "tar", "gz", "bz2"]),
            ("Videos", ["mp4", "mov", "mkv", "avi", "webm"]),
            ("Audio", ["mp3", "m4a", "wav", "aiff", "flac"]),
            ("Installers", ["dmg", "pkg", "app"]),
            ("3D Projects", ["blend", "blend1", "fbx", "obj", "stl", "dae", "glb", "gltf", "usd", "usda", "usdc", "usdz"]),
            ("Design", ["psd", "psb", "ai", "sketch", "fig", "xd", "afdesign", "afphoto", "afpub", "svg"]),
            ("Code", ["swift", "py", "js", "ts", "jsx", "tsx", "java", "c", "cc", "cpp", "h", "hpp", "cs", "go", "rs", "rb", "php", "html", "css", "scss", "json", "yaml", "yml", "xml", "sql", "sh", "zsh", "ipynb"]),
            ("Fonts", ["ttf", "otf", "woff", "woff2"]),
            ("Torrents", ["torrent"])
        ]
        let root = (rawPath as NSString).expandingTildeInPath
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return "Error: Cannot read \(rawPath)." }
        var counts: [String: Int] = [:]
        var unclassifiedExtensions = Set<String>()
        do {
            for source in entries {
                guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                guard let category = categories.first(where: { $0.extensions.contains(source.pathExtension.lowercased()) }) else {
                    unclassifiedExtensions.insert(source.pathExtension.isEmpty ? "no extension" : ".\(source.pathExtension.lowercased())")
                    continue
                }
                let destinationFolder = URL(fileURLWithPath: root).appendingPathComponent(category.folder, isDirectory: true)
                try manager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                var target = destinationFolder.appendingPathComponent(source.lastPathComponent); var suffix = 2
                while manager.fileExists(atPath: target.path) { target = destinationFolder.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) \(suffix).\(source.pathExtension)"); suffix += 1 }
                try manager.moveItem(at: source, to: target)
                guard manager.fileExists(atPath: target.path) else { return "Error: Could not verify \(source.lastPathComponent)." }
                counts[category.folder, default: 0] += 1
            }
            let result = counts.isEmpty ? "No recognized files needed organizing in \(rawPath)." : "Organized \(rawPath): " + counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + "."
            guard !unclassifiedExtensions.isEmpty else { return result }
            return result + " Left unrecognized file type(s) untouched: \(unclassifiedExtensions.sorted().joined(separator: ", "))."
        } catch { return "Error organizing Downloads: \(error.localizedDescription)" }
    }
}
