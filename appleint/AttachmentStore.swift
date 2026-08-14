import Foundation

protocol AttachmentStoring: AnyObject {
    func store(dataURL: String) -> UUID?
    func load(id: UUID) -> String?
}

/// Keeps large image payloads out of the conversation JSON while preserving
/// existing provider code, which still consumes data URLs in memory.
final class AttachmentStore: AttachmentStoring {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func store(dataURL: String) -> UUID? {
        let id = UUID()
        guard let data = dataURL.data(using: .utf8) else { return nil }
        do {
            try data.write(to: fileURL(for: id), options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL(for: id).path)
            return id
        } catch { return nil }
    }

    func load(id: UUID) -> String? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).attachment", isDirectory: false)
    }
}
