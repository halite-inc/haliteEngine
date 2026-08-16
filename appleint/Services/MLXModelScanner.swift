import Foundation
import Combine

nonisolated public struct LocalMLXModel: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var author: String
    public var path: String
    public var quantization: String
    public var isMLXNative: Bool
    public var fileSizeBytes: Int64
    
    public var displayName: String {
        if !author.isEmpty && author != "models" {
            return "\(author)/\(name)"
        }
        return name
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
    
    public init(
        id: String,
        name: String,
        author: String,
        path: String,
        quantization: String,
        isMLXNative: Bool,
        fileSizeBytes: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.path = path
        self.quantization = quantization
        self.isMLXNative = isMLXNative
        self.fileSizeBytes = fileSizeBytes
    }
}

@MainActor
public final class MLXModelScanner: ObservableObject {
    @Published public var models: [LocalMLXModel] = []
    @Published public var isScanning: Bool = false
    @Published public var lastScanDate: Date? = nil
    @Published public var isServerRunning: Bool = false
    @Published public var runningModelId: String? = nil
    private var activeProcess: Process? = nil
    
    public init() {
        scanModels()
        checkServerRunning()
    }
    
    public func checkServerRunning() {
        guard let url = URL(string: "http://localhost:8080/v1/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.httpMethod = "GET"
        Task {
            if let (_, response) = try? await URLSession.shared.data(for: req),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                await MainActor.run {
                    self.isServerRunning = true
                }
            } else {
                await MainActor.run {
                    if self.activeProcess == nil {
                        self.isServerRunning = false
                    }
                }
            }
        }
    }
    
    public func startServer(for model: LocalMLXModel, port: Int = 8080) {
        stopServer()
        
        let modelPath = model.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        
        let script = """
        if [ -x "$HOME/.local/bin/uv" ]; then
            exec "$HOME/.local/bin/uv" run --with mlx-lm python3 -m mlx_lm.server --model "\(modelPath)" --port \(port)
        elif command -v uv >/dev/null 2>&1; then
            exec uv run --with mlx-lm python3 -m mlx_lm.server --model "\(modelPath)" --port \(port)
        else
            exec python3 -m mlx_lm.server --model "\(modelPath)" --port \(port)
        fi
        """
        process.arguments = ["-c", script]
        
        do {
            try process.run()
            self.activeProcess = process
            self.isServerRunning = true
            self.runningModelId = model.id
        } catch {
            print("Failed to start MLX server: \(error)")
        }
    }
    
    public func stopServer() {
        if let process = activeProcess, process.isRunning {
            process.terminate()
        }
        activeProcess = nil
        isServerRunning = false
        runningModelId = nil
    }
    
    public var candidateSearchPaths: [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        var paths: [URL] = [
            home.appendingPathComponent(".lmstudio/models", isDirectory: true),
            home.appendingPathComponent(".cache/lm-studio/models", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/LM Studio/models", isDirectory: true),
            home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true),
            home.appendingPathComponent("models", isDirectory: true)
        ]
        
        // Custom user-defined model paths from UserDefaults if any
        if let customPath = UserDefaults.standard.string(forKey: "customMLXModelDirectory"),
           !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paths.insert(URL(fileURLWithPath: customPath, isDirectory: true), at: 0)
        }
        
        return paths.filter { fileManager.fileExists(atPath: $0.path) }
    }
    
    public func scanModels() {
        guard !isScanning else { return }
        isScanning = true
        
        let searchPaths = candidateSearchPaths
        
        Task.detached(priority: .userInitiated) {
            var discovered: [LocalMLXModel] = []
            var seenPaths = Set<String>()
            let fm = FileManager.default
            
            for rootURL in searchPaths {
                guard fm.fileExists(atPath: rootURL.path) else { continue }
                
                // Scan directories up to depth 3
                if let enumerator = fm.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) {
                    while let url = enumerator.nextObject() as? URL {
                        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        
                        if isDirectory {
                            // Check if this directory is an MLX or HuggingFace model package
                            let path = url.path
                            if seenPaths.contains(path) { continue }
                            
                            if let items = try? fm.contentsOfDirectory(atPath: path) {
                                let hasConfig = items.contains("config.json")
                                let hasSafetensors = items.contains(where: { $0.hasSuffix(".safetensors") })
                                let hasMLXWeights = items.contains(where: { $0.contains("mlx") || $0.hasSuffix(".npz") || $0.hasSuffix(".safetensors") })
                                
                                if hasConfig && (hasSafetensors || hasMLXWeights) {
                                    seenPaths.insert(path)
                                    enumerator.skipDescendants()
                                    
                                    let folderName = url.lastPathComponent
                                    let authorName = url.deletingLastPathComponent().lastPathComponent
                                    let quant = Self.extractQuantization(from: folderName)
                                    
                                    // Calculate folder size
                                    var totalSize: Int64 = 0
                                    for item in items {
                                        let itemURL = url.appendingPathComponent(item)
                                        if let size = (try? itemURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                                            totalSize += Int64(size)
                                        }
                                    }
                                    
                                    let modelId = authorName.isEmpty || authorName == "models" ? folderName : "\(authorName)/\(folderName)"
                                    discovered.append(LocalMLXModel(
                                        id: modelId,
                                        name: folderName,
                                        author: authorName,
                                        path: path,
                                        quantization: quant,
                                        isMLXNative: true,
                                        fileSizeBytes: totalSize
                                    ))
                                }
                            }
                        } else if url.pathExtension.lowercased() == "gguf" {
                            let path = url.path
                            if seenPaths.contains(path) { continue }
                            seenPaths.insert(path)
                            
                            let fileName = url.deletingPathExtension().lastPathComponent
                            let authorName = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                            let quant = Self.extractQuantization(from: fileName)
                            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                            
                            let modelId = authorName.isEmpty || authorName == "models" ? fileName : "\(authorName)/\(fileName)"
                            discovered.append(LocalMLXModel(
                                id: modelId,
                                name: fileName,
                                author: authorName,
                                path: path,
                                quantization: quant,
                                isMLXNative: false,
                                fileSizeBytes: size
                            ))
                        }
                    }
                }
            }
            
            // Sort: MLX-native models first, then alphabetical by name
            discovered.sort { m1, m2 in
                if m1.isMLXNative != m2.isMLXNative {
                    return m1.isMLXNative && !m2.isMLXNative
                }
                return m1.displayName.localizedCaseInsensitiveCompare(m2.displayName) == .orderedAscending
            }
            
            let finalDiscovered = discovered
            await MainActor.run {
                self.models = finalDiscovered
                self.isScanning = false
                self.lastScanDate = Date()
            }
        }
    }
    
    nonisolated public static func extractQuantization(from name: String) -> String {
        let upper = name.uppercased()
        if upper.contains("MLX-4BIT") || upper.contains("4BIT") || upper.contains("4-BIT") { return "4-bit" }
        if upper.contains("MLX-8BIT") || upper.contains("8BIT") || upper.contains("8-BIT") { return "8-bit" }
        if upper.contains("MLX-5BIT") || upper.contains("5BIT") || upper.contains("5-BIT") { return "5-bit" }
        if upper.contains("MLX-6BIT") || upper.contains("6BIT") || upper.contains("6-BIT") { return "6-bit" }
        if upper.contains("MLX-3BIT") || upper.contains("3BIT") || upper.contains("3-BIT") { return "3-bit" }
        if upper.contains("Q4_K_M") || upper.contains("Q4_K") || upper.contains("Q4_0") { return "Q4" }
        if upper.contains("Q8_0") || upper.contains("Q8_K") { return "Q8" }
        if upper.contains("Q5_K_M") || upper.contains("Q5_K") { return "Q5" }
        if upper.contains("Q6_K") { return "Q6" }
        if upper.contains("FP16") || upper.contains("F16") { return "FP16" }
        if upper.contains("BF16") { return "BF16" }
        return "Native"
    }
}
