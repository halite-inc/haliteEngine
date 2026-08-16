import Foundation

public enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

public struct AttachedFile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var fileExtension: String
    public var fileSize: Int64
    public var mimeType: String
    public var textContent: String?
    public var pageCount: Int?
    
    public var isPDF: Bool {
        fileExtension.lowercased() == "pdf"
    }

    public init(
        id: UUID = UUID(),
        name: String,
        fileExtension: String,
        fileSize: Int64,
        mimeType: String,
        textContent: String? = nil,
        pageCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.textContent = textContent
        self.pageCount = pageCount
    }
}

public struct ChatMessage: Codable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var timestamp: Date
    public var attachedImageBase64: String?
    public var attachmentID: UUID?
    public var attachedFiles: [AttachedFile]?
    
    public var generationStartTime: Date?
    public var generationEndTime: Date?
    
    public init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        timestamp: Date = Date(),
        attachedImageBase64: String? = nil,
        attachmentID: UUID? = nil,
        attachedFiles: [AttachedFile]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachedImageBase64 = attachedImageBase64
        self.attachmentID = attachmentID
        self.attachedFiles = attachedFiles
    }
}

public struct UserTask: Codable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var details: String
    public var dueDate: String?
    public var isCompleted: Bool
    public var createdAt: Date
    public var groupName: String?

    public init(id: UUID = UUID(), title: String, details: String = "", dueDate: String? = nil, isCompleted: Bool = false, createdAt: Date = Date(), groupName: String? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.groupName = groupName
    }
}

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case lmStudio = "lmstudio"
    case mlx = "mlx"
    case gemini = "gemini"
    case openRouter = "openrouter"
    case openAI = "openai"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .lmStudio: return "LM Studio Server"
        case .mlx: return "Apple MLX (Native Metal)"
        case .gemini: return "Gemini API"
        case .openRouter: return "OpenRouter API"
        case .openAI: return "ChatGPT (OpenAI)"
        }
    }
    
    public var shortDisplayName: String {
        switch self {
        case .lmStudio: return "LM Studio"
        case .mlx: return "Apple MLX"
        case .gemini: return "Gemini"
        case .openRouter: return "OpenRouter"
        case .openAI: return "ChatGPT"
        }
    }
}

public struct ChatPersona: Identifiable, Hashable, Codable {
    public var id: String { name }
    public var name: String
    public var icon: String
    public var instructions: String
    public var temperature: Double

    public static let legacyGeneralAssistantInstructions = "You are an exceptionally capable, insightful, and versatile AI assistant operating at the highest standard of technical and intellectual excellence. You approach every topic—from software engineering and advanced mathematics to science, finance, law, philosophy, and creative problem solving—with first-principles depth, structured clarity, rigorous accuracy, and actionable value. You provide complete, production-grade solutions, quantitative analyses, and structured comparison tables where appropriate, while adapting warmly and naturally to any user-requested tone or format."

    public static let generalAssistantInstructions = """
    You are a precise, natural, high-quality assistant.

    Answer the user's actual question directly. Match the response length to the task: be brief for simple questions and expand only when complexity or the user requires it. Lead with the answer; use 3–5 high-confidence points when a list helps.

    Prioritize accuracy, relevance, and practical usefulness. Never guess facts, numbers, APIs, specifications, or completed actions. Use available tools or web search only when the request needs current or independently verifiable information, or when the user explicitly asks. State material uncertainty briefly.

    Avoid repetition, filler, excessive headings, unnecessary tables, generic warnings, and encyclopedia-style background. For coding, provide a working solution first and explain only the decisions needed to use or verify it. Before responding, silently remove anything irrelevant, repetitive, speculative, or lower-value.
    """
    
    public static let presets: [ChatPersona] = [
        ChatPersona(
            name: "General Assistant",
            icon: "sparkles",
            instructions: generalAssistantInstructions,
            temperature: 0.7
        ),
        ChatPersona(
            name: "Coding Companion",
            icon: "cpu",
            instructions: "You are a Principal Software Architect and elite polyglot developer. You write clean, robust, production-grade, idiomatic code with thorough edge-case handling, performance optimization, and clear architectural rationale. You provide complete implementations without placeholders.",
            temperature: 0.2
        ),
        ChatPersona(
            name: "Creative Writer",
            icon: "pencil.and.outline",
            instructions: "You are a master writer, storyteller, and rhetorical stylist. You craft evocative, deeply engaging, nuanced, and stylistically rich prose, narratives, and essays.",
            temperature: 1.0
        ),
        ChatPersona(
            name: "Concise Summarizer",
            icon: "text.alignleft",
            instructions: "You are a high-density executive intelligence summarizer. You extract core takeaways, structured metrics, critical trade-offs, and actionable decisions with zero fluff.",
            temperature: 0.3
        )
    ]
}

public struct ChatThread: Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var provider: Provider
    public var systemInstructions: String
    public var temperature: Double
    public var lmStudioModelId: String?
    public var mlxModelId: String?
    public var geminiModelId: String?
    public var openRouterModelId: String?
    public var openAIModelId: String?
    public var isToolUseEnabled: Bool
    public var showSystemMessages: Bool
    public var messages: [ChatMessage]
    public var createdAt: Date
    public var chatMemory: String?
    public var memoryNodes: [MemoryNode]
    public var memoryEdges: [MemoryEdge]
    /// New chats start without cross-chat memory/task injection.
    public var isolatesContext: Bool
    
    public init(
        id: UUID = UUID(),
        title: String = "New Chat",
        provider: Provider = .gemini,
        systemInstructions: String = ChatPersona.presets[0].instructions,
        temperature: Double = ChatPersona.presets[0].temperature,
        lmStudioModelId: String? = nil,
        mlxModelId: String? = nil,
        geminiModelId: String? = "gemini-2.5-flash",
        openRouterModelId: String? = "google/gemini-2.0-flash-001",
        openAIModelId: String? = "gpt-4o",
        isToolUseEnabled: Bool = true,
        showSystemMessages: Bool = false,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        chatMemory: String? = nil,
        memoryNodes: [MemoryNode] = [],
        memoryEdges: [MemoryEdge] = [],
        isolatesContext: Bool = false
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.systemInstructions = systemInstructions
        self.temperature = min(max(temperature, 0), 1)
        self.lmStudioModelId = lmStudioModelId
        self.mlxModelId = mlxModelId
        self.geminiModelId = geminiModelId
        self.openRouterModelId = openRouterModelId
        self.openAIModelId = openAIModelId
        self.isToolUseEnabled = isToolUseEnabled
        self.showSystemMessages = showSystemMessages
        self.messages = messages
        self.createdAt = createdAt
        self.chatMemory = chatMemory
        self.memoryNodes = memoryNodes
        self.memoryEdges = memoryEdges
        self.isolatesContext = isolatesContext
    }
    
    // Custom Decodable implementation for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, title, provider, systemInstructions, temperature, lmStudioModelId, mlxModelId, geminiModelId, openRouterModelId, openAIModelId, messages, createdAt, isToolUseEnabled, showSystemMessages, chatMemory, memoryNodes, memoryEdges, isolatesContext
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        provider = try container.decodeIfPresent(Provider.self, forKey: .provider) ?? .gemini
        systemInstructions = try container.decode(String.self, forKey: .systemInstructions)
        temperature = min(max(try container.decode(Double.self, forKey: .temperature), 0), 1)
        lmStudioModelId = try container.decodeIfPresent(String.self, forKey: .lmStudioModelId)
        mlxModelId = try container.decodeIfPresent(String.self, forKey: .mlxModelId)
        geminiModelId = try container.decodeIfPresent(String.self, forKey: .geminiModelId) ?? "gemini-2.5-flash"
        openRouterModelId = try container.decodeIfPresent(String.self, forKey: .openRouterModelId) ?? "google/gemini-2.0-flash-001"
        openAIModelId = try container.decodeIfPresent(String.self, forKey: .openAIModelId) ?? "gpt-4o"
        isToolUseEnabled = try container.decodeIfPresent(Bool.self, forKey: .isToolUseEnabled) ?? true
        showSystemMessages = try container.decodeIfPresent(Bool.self, forKey: .showSystemMessages) ?? false
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        chatMemory = try container.decodeIfPresent(String.self, forKey: .chatMemory)
        memoryNodes = try container.decodeIfPresent([MemoryNode].self, forKey: .memoryNodes) ?? []
        memoryEdges = try container.decodeIfPresent([MemoryEdge].self, forKey: .memoryEdges) ?? []
        isolatesContext = try container.decodeIfPresent(Bool.self, forKey: .isolatesContext) ?? false
    }
    
    public var activeModelName: String {
        switch provider {
        case .gemini: return geminiModelId ?? "gemini-2.5-flash"
        case .openRouter: return openRouterModelId ?? "google/gemini-2.0-flash-001"
        case .openAI: return openAIModelId ?? "gpt-4o"
        case .lmStudio: return lmStudioModelId ?? "LM Studio local model"
        case .mlx: return mlxModelId ?? "None (Select Model)"
        }
    }
}

public struct MemoryNode: Codable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var category: String // e.g. "user", "project", "interest", "health", "info"
    
    public init(id: String, label: String, category: String) {
        self.id = id
        self.label = label
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case id, label, category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawLabel = try container.decodeIfPresent(String.self, forKey: .label)
        let rawId = try container.decodeIfPresent(String.self, forKey: .id)
        
        let decodedLabel = rawLabel ?? rawId ?? "Unnamed Node"
        let decodedId = rawId ?? decodedLabel.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        
        self.label = decodedLabel
        self.id = decodedId.isEmpty ? "node_\(UUID().uuidString.prefix(6))" : decodedId
        self.category = (try container.decodeIfPresent(String.self, forKey: .category)) ?? "info"
    }
}

public struct MemoryEdge: Codable, Identifiable, Hashable {
    public var id: String { "\(source)-\(target)-\(label)" }
    public var source: String
    public var target: String
    public var label: String // relationship description, e.g. "likes", "built", "studies"
    
    public init(source: String, target: String, label: String) {
        self.source = source
        self.target = target
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case source, target, label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = (try container.decodeIfPresent(String.self, forKey: .source)) ?? "user"
        self.target = (try container.decodeIfPresent(String.self, forKey: .target)) ?? ""
        self.label = (try container.decodeIfPresent(String.self, forKey: .label)) ?? "related_to"
    }
}

public struct GlobalMemoryPayload: Codable {
    public var nodes: [MemoryNode]
    public var edges: [MemoryEdge]
    
    public init(nodes: [MemoryNode], edges: [MemoryEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct PrePromptItem: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var category: String
    public var iconName: String
    public var iconColorName: String
    public var isEnabled: Bool
    public var statusText: String
    public var summary: String
    public var rawContent: String
    
    public init(id: String, title: String, category: String, iconName: String, iconColorName: String, isEnabled: Bool, statusText: String, summary: String, rawContent: String) {
        self.id = id
        self.title = title
        self.category = category
        self.iconName = iconName
        self.iconColorName = iconColorName
        self.isEnabled = isEnabled
        self.statusText = statusText
        self.summary = summary
        self.rawContent = rawContent
    }
}

public struct CustomSkill: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var instructions: String
    public var isEnabled: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, summary: String, instructions: String, isEnabled: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.summary = summary
        self.instructions = instructions
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
