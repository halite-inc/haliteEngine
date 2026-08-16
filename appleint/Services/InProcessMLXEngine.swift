import Foundation
import Combine
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers

public enum MLXEngineState: Equatable, Sendable {
    case idle
    case loading(model: String, progress: Double)
    case ready(model: String)
    case generating(model: String)
    case failed(String)
}

public actor MLXInProcessRunner {
    private var container: ModelContainer?
    private var activePath: String?
    
    public init() {}
    
    public func isLoaded(path: String) -> Bool {
        return container != nil && activePath == path
    }
    
    public func load(path: String) async throws -> ModelContainer {
        if let existing = container, activePath == path {
            return existing
        }
        
        // Free previously loaded model from Unified Memory
        container = nil
        activePath = nil
        Memory.clearCache()
        
        let directoryURL = URL(fileURLWithPath: path)
        let factory = LLMModelFactory.shared
        
        let loadedContainer = try await factory.loadContainer(
            from: directoryURL,
            using: #huggingFaceTokenizerLoader()
        )
        
        self.container = loadedContainer
        self.activePath = path
        return loadedContainer
    }
    
    public func unload() {
        container = nil
        activePath = nil
        Memory.clearCache()
    }
    
    public func generate(
        prompt: String,
        messages: [ChatMessage],
        maxTokens: Int = 4096,
        temperature: Float = 0.6,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let container = container else {
            throw NSError(domain: "MLXInProcessEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model loaded in memory."])
        }
        
        // Build prompt from chat transcript history if multiple messages exist
        var promptText = prompt
        if !messages.isEmpty {
            var formatted = ""
            for msg in messages {
                let role = msg.role == .user ? "user" : "assistant"
                let text = msg.text
                if !text.isEmpty {
                    formatted += "<|\(role)|>\n\(text)<|end|>\n"
                }
            }
            if !formatted.isEmpty {
                formatted += "<|user|>\n\(prompt)<|end|>\n<|assistant|>\n"
                promptText = formatted
            }
        }
        
        let resultOutput = try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: promptText))
            let params = GenerateParameters(temperature: temperature)
            
            var generatedCount = 0
            let genResult = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: context
            ) { tokenIds in
                if let lastId = tokenIds.last {
                    let piece = context.tokenizer.decode(tokenIds: [lastId])
                    if !piece.isEmpty {
                        onToken(piece)
                    }
                }
                generatedCount += 1
                if generatedCount >= maxTokens {
                    return .stop
                }
                return .more
            }
            return genResult.output
        }
        
        return resultOutput
    }
}

@MainActor
public final class InProcessMLXEngine: ObservableObject {
    public static let shared = InProcessMLXEngine()
    
    public static let engineVersion = "1.0.0"
    public static let frameworkVersion = "mlx-swift 0.31.6"
    public static let metalBackend = "Metal Toolchain 17F109"
    
    @Published public var state: MLXEngineState = .idle
    @Published public var lastTokenSpeed: Double = 0.0
    @Published public var lastTotalTokens: Int = 0
    @Published public var loadedModelPath: String? = nil
    @Published public var loadedModelDisplayName: String? = nil
    @Published public var isInjecting: Bool = false
    
    private let runner = MLXInProcessRunner()
    
    public init() {}
    
    public func isModelLoaded(path: String) -> Bool {
        return loadedModelPath == path
    }
    
    public func inject(model: LocalMLXModel) async {
        isInjecting = true
        do {
            try await ensureModelLoaded(path: model.path, displayName: model.displayName)
            self.loadedModelPath = model.path
            self.loadedModelDisplayName = model.displayName
            self.isInjecting = false
        } catch {
            self.isInjecting = false
        }
    }
    
    public func ensureModelLoaded(path: String, displayName: String) async throws {
        let isAlreadyLoaded = await runner.isLoaded(path: path)
        if isAlreadyLoaded {
            self.loadedModelPath = path
            self.loadedModelDisplayName = displayName
            self.state = .ready(model: displayName)
            return
        }
        
        self.state = .loading(model: displayName, progress: 0.1)
        do {
            _ = try await runner.load(path: path)
            self.loadedModelPath = path
            self.loadedModelDisplayName = displayName
            self.state = .ready(model: displayName)
        } catch {
            self.state = .failed(error.localizedDescription)
            throw error
        }
    }
    
    public func unload() async {
        await runner.unload()
        self.loadedModelPath = nil
        self.loadedModelDisplayName = nil
        self.state = .idle
    }
    
    public func generateStream(
        prompt: String,
        messages: [ChatMessage],
        modelPath: String,
        modelDisplayName: String,
        maxTokens: Int = 4096,
        temperature: Float = 0.6,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await ensureModelLoaded(path: modelPath, displayName: modelDisplayName)
        
        self.state = .generating(model: modelDisplayName)
        let startTime = CFAbsoluteTimeGetCurrent()
        var tokenCount = 0
        
        do {
            let output = try await runner.generate(
                prompt: prompt,
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature
            ) { chunk in
                tokenCount += 1
                Task { @MainActor in
                    onChunk(chunk)
                }
            }
            
            let duration = max(CFAbsoluteTimeGetCurrent() - startTime, 0.05)
            self.lastTotalTokens = tokenCount
            self.lastTokenSpeed = Double(tokenCount) / duration
            self.state = .ready(model: modelDisplayName)
            return output
        } catch {
            self.state = .failed(error.localizedDescription)
            throw error
        }
    }
}
