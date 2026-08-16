import Foundation

public enum ToolFieldType: String, Codable {
    case number
    case text
    case singleChoice = "single_choice"
    case multipleChoice = "multiple_choice"
    case boolean
    case date
    case time
    case slider
    case stepper
    case dropdown
    case insight
}

public struct SuggestionItem: Codable, Identifiable, Hashable {
    public var id: String { value }
    public let value: String
    public let displayLabel: String
    
    public init(value: String, displayLabel: String) {
        self.value = value
        self.displayLabel = displayLabel
    }
    
    private enum CodingKeys: String, CodingKey {
        case value
        case displayLabel
    }
    
    public init(from decoder: Decoder) throws {
        // 1. Try decoding as keyed container (object style: {"value": "X", "displayLabel": "Y"})
        if let keyedContainer = try? decoder.container(keyedBy: CodingKeys.self) {
            let val: String
            if let stringVal = try? keyedContainer.decode(String.self, forKey: .value) {
                val = stringVal
            } else if let intVal = try? keyedContainer.decode(Int.self, forKey: .value) {
                val = String(intVal)
            } else if let doubleVal = try? keyedContainer.decode(Double.self, forKey: .value) {
                if doubleVal == Double(Int(doubleVal)) {
                    val = String(Int(doubleVal))
                } else {
                    val = String(doubleVal)
                }
            } else {
                val = ""
            }
            
            var label: String = val
            if let displayLabelVal = try? keyedContainer.decode(String.self, forKey: .displayLabel) {
                label = displayLabelVal
            } else {
                // Check fallback key name "label"
                struct FallbackKeys: CodingKey {
                    var stringValue: String
                    init?(stringValue: String) { self.stringValue = stringValue }
                    var intValue: Int?
                    init?(intValue: Int) { return nil }
                }
                if let fallbackContainer = try? decoder.container(keyedBy: FallbackKeys.self),
                   let labelKey = FallbackKeys(stringValue: "label"),
                   let labelVal = try? fallbackContainer.decode(String.self, forKey: labelKey) {
                    label = labelVal
                }
            }
            
            self.value = val
            self.displayLabel = label
            return
        }
        
        // 2. Fallback: decode as single value (primitive: "X" or 50)
        let container = try decoder.singleValueContainer()
        if let doubleVal = try? container.decode(Double.self) {
            if doubleVal == Double(Int(doubleVal)) {
                self.value = String(Int(doubleVal))
                self.displayLabel = String(Int(doubleVal))
            } else {
                self.value = String(doubleVal)
                self.displayLabel = String(doubleVal)
            }
        } else if let intVal = try? container.decode(Int.self) {
            self.value = String(intVal)
            self.displayLabel = String(intVal)
        } else if let stringVal = try? container.decode(String.self) {
            self.value = stringVal
            self.displayLabel = stringVal
        } else {
            throw DecodingError.typeMismatch(
                SuggestionItem.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Suggestion value is neither Number, String, nor Object")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let doubleVal = Double(value) {
            try container.encode(doubleVal)
        } else {
            try container.encode(value)
        }
    }
}

public struct ToolField: Codable, Identifiable {
    public var id: String
    public var label: String
    public var type: ToolFieldType
    public var unit: String?
    public var required: Bool?
    public var suggestions: [SuggestionItem]?
    public var allowCustom: Bool?
    
    // UI layout params
    public var min: Double?
    public var max: Double?
    public var step: Double?
    public var placeholder: String?
    
    public var isRequired: Bool {
        required ?? true
    }
    
    public var isCustomAllowed: Bool {
        allowCustom ?? true
    }
}

public struct GeneratedFile: Codable, Hashable {
    public var path: String
    public var content: String
}

public struct ToolRequest: Codable, Identifiable {
    public var id: UUID { UUID() }
    public var type: String? // request_input, tesaract, internet_use, advanced_memory, file_system
    public var title: String
    public var description: String
    public var fields: [ToolField]
    public var displayMode: String? // sequential, form
    public var html: String? // custom HTML/JS code for Tesaract
    public var query: String? // Search query for internet_use
    public var queries: [String]? // Multi-query search support for internet_use
    public var nodes: [MemoryNode]?
    public var edges: [MemoryEdge]?
    public var action: String? // for file_system (list, create_file, create_folder, read_file, execute_command)
    public var path: String? // for file_system
    public var content: String? // for file_system
    public var command: String? // for file_system (shell command string for execute_command)
    public var files: [GeneratedFile]? // batched create_files action
    public var taskId: UUID?
    public var dueDate: String?
    public var isCompleted: Bool?
    public var groupName: String?
    public var position: Int?
    public var learningId: String? // stable ID for Learning skill update/delete
    public var learningKind: String? // "rule" or "how-to"
    public var learningTopic: String? // short topic used as a visible Learning subheading
    public var mcpServer: String? // Target MCP server name
    public var mcpTool: String? // Target MCP tool name
    public var mcpArguments: [String: AgentValue]? // Arguments for MCP tool call
    public var folder: String? // for apple_notes (target folder name)
    public var noteId: String? // for apple_notes (target note ID)
    
    public var displayTitle: String {
        if type == "file_system" || title == "File System & Terminal Access" || title == "filesystem fetched" || title == "filesystem used" || title == "terminal used" {
            return "terminal used"
        }
        if type == "advanced_memory" || title == "Update Knowledge Graph" || title == "Update Memory Graph" {
            return "updated memory"
        }
        if type == "learning" { return "updated learning" }
        if type == "apple_notes" {
            if let action = action, !action.isEmpty {
                return "Notes: \(action)"
            }
            return "Apple Notes"
        }
        if type == "mcp" {
            let toolName = mcpTool ?? title
            return "MCP: \(toolName)"
        }
        return title
    }
    
    public var mode: DisplayMode {
        if displayMode == "form" {
            return .form
        }
        return .sequential
    }
    
    public enum DisplayMode {
        case sequential
        case form
    }

    enum CodingKeys: String, CodingKey {
        case type, title, description, fields, displayMode, html, query, queries, nodes, edges, action, path, content, command, files, taskId, dueDate, isCompleted, groupName, position, learningId, learningKind, learningTopic, mcpServer, mcpTool, mcpArguments, folder, noteId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedType = try container.decodeIfPresent(String.self, forKey: .type)
        type = decodedType
        
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        title = decodedTitle ?? {
            switch decodedType {
            case "advanced_memory": return "updated memory"
            case "learning": return "updated learning"
            case "internet_use": return "Internet Search"
            case "file_system": return "File System Access"
            case "tesaract": return "Interactive Visualizer"
            case "apple_notes": return "Apple Notes"
            case "mcp": return "MCP Tool"
            default: return "Tool Request"
            }
        }()
        
        description = (try container.decodeIfPresent(String.self, forKey: .description)) ?? ""
        fields = try container.decodeIfPresent([ToolField].self, forKey: .fields) ?? []
        displayMode = try container.decodeIfPresent(String.self, forKey: .displayMode)
        html = try container.decodeIfPresent(String.self, forKey: .html)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        queries = try container.decodeIfPresent([String].self, forKey: .queries)
        nodes = try container.decodeIfPresent([MemoryNode].self, forKey: .nodes)
        edges = try container.decodeIfPresent([MemoryEdge].self, forKey: .edges)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        files = try container.decodeIfPresent([GeneratedFile].self, forKey: .files)
        taskId = try container.decodeIfPresent(UUID.self, forKey: .taskId)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
        learningId = try container.decodeIfPresent(String.self, forKey: .learningId)
        learningKind = try container.decodeIfPresent(String.self, forKey: .learningKind)
        learningTopic = try container.decodeIfPresent(String.self, forKey: .learningTopic)
        mcpServer = try container.decodeIfPresent(String.self, forKey: .mcpServer)
        mcpTool = try container.decodeIfPresent(String.self, forKey: .mcpTool)
        mcpArguments = try container.decodeIfPresent([String: AgentValue].self, forKey: .mcpArguments)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        noteId = try container.decodeIfPresent(String.self, forKey: .noteId)
    }

    public init(type: String?, title: String, description: String, fields: [ToolField], displayMode: String? = nil, html: String? = nil, query: String? = nil, queries: [String]? = nil, nodes: [MemoryNode]? = nil, edges: [MemoryEdge]? = nil, action: String? = nil, path: String? = nil, content: String? = nil, command: String? = nil, files: [GeneratedFile]? = nil, taskId: UUID? = nil, dueDate: String? = nil, isCompleted: Bool? = nil, groupName: String? = nil, position: Int? = nil, learningId: String? = nil, learningKind: String? = nil, learningTopic: String? = nil, mcpServer: String? = nil, mcpTool: String? = nil, mcpArguments: [String: AgentValue]? = nil, folder: String? = nil, noteId: String? = nil) {
        self.type = type
        self.title = title
        self.description = description
        self.fields = fields
        self.displayMode = displayMode
        self.html = html
        self.query = query
        self.queries = queries
        self.nodes = nodes
        self.edges = edges
        self.action = action
        self.path = path
        self.content = content
        self.command = command
        self.files = files
        self.taskId = taskId
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.groupName = groupName
        self.position = position
        self.learningId = learningId
        self.learningKind = learningKind
        self.learningTopic = learningTopic
        self.mcpServer = mcpServer
        self.mcpTool = mcpTool
        self.mcpArguments = mcpArguments
        self.folder = folder
        self.noteId = noteId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(fields, forKey: .fields)
        try container.encodeIfPresent(displayMode, forKey: .displayMode)
        try container.encodeIfPresent(html, forKey: .html)
        try container.encodeIfPresent(query, forKey: .query)
        try container.encodeIfPresent(queries, forKey: .queries)
        try container.encodeIfPresent(nodes, forKey: .nodes)
        try container.encodeIfPresent(edges, forKey: .edges)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(files, forKey: .files)
        try container.encodeIfPresent(taskId, forKey: .taskId)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(groupName, forKey: .groupName)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(learningId, forKey: .learningId)
        try container.encodeIfPresent(learningKind, forKey: .learningKind)
        try container.encodeIfPresent(learningTopic, forKey: .learningTopic)
        try container.encodeIfPresent(mcpServer, forKey: .mcpServer)
        try container.encodeIfPresent(mcpTool, forKey: .mcpTool)
        try container.encodeIfPresent(mcpArguments, forKey: .mcpArguments)
        try container.encodeIfPresent(folder, forKey: .folder)
        try container.encodeIfPresent(noteId, forKey: .noteId)
    }
}

public struct ToolRequestParser {
    private static var parseCache: [String: ToolRequest?] = [:]
    private static let lock = NSLock()
    
    public static func parse(text: String) -> ToolRequest? {
        lock.lock()
        if let cached = parseCache[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // Strip internal reasoning thoughts before parsing tool requests to avoid false matches inside reasoning text
        let sanitizedText = text
            .replacingOccurrences(of: #"(?is)<think>.*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<thought>.*?</thought>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)\[THINKING\].*?\[/THINKING\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let result: ToolRequest? = {
            if let functionStyleRequest = parseFunctionStyleToolCall(sanitizedText) {
                return functionStyleRequest
            }
            if let nativeToolRequest = parseNativeToolCall(text: sanitizedText) {
                return nativeToolRequest
            }
            if let jsonRequest = parseJSON(text: sanitizedText) {
                return jsonRequest
            }
            return parseCommandBlockToolCall(sanitizedText)
        }()
        
        lock.lock()
        parseCache[text] = result
        lock.unlock()
        
        return result
    }

    /// When models describe commands in markdown code blocks after failures (e.g. ```bash brew install ...```),
    /// parse them as an execute_command tool call so the agent automatically continues execution without stalling.
    private static func parseCommandBlockToolCall(_ text: String) -> ToolRequest? {
        let lower = text.lowercased()
        let isTutorialOrRefusal = lower.contains("i cannot") ||
                                  lower.contains("i can't") ||
                                  lower.contains("restricted from") ||
                                  lower.contains("security and privacy reasons") ||
                                  lower.contains("follow these steps") ||
                                  lower.contains("steps yourself") ||
                                  lower.contains("you will need to") ||
                                  lower.contains("you can run") ||
                                  lower.contains("you can start") ||
                                  lower.contains("try running") ||
                                  lower.contains("how to start") ||
                                  lower.contains("start using it")
        if isTutorialOrRefusal {
            return nil
        }

        let pattern = #"(?is)```(?:bash|zsh|sh|shell)\s*\n(.*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1,
              let match = matches.first,
              let cmdRange = Range(match.range(at: 1), in: text) else { return nil }

        var cmd = String(text[cmdRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return nil }

        // Remove `/bin/zsh -c "..."` or `/bin/bash -c "..."` wrapping if present
        if cmd.hasPrefix("/bin/zsh -c \"") && cmd.hasSuffix("\"") {
            cmd = String(cmd.dropFirst("/bin/zsh -c \"".count).dropLast(1))
        } else if cmd.hasPrefix("/bin/bash -c \"") && cmd.hasSuffix("\"") {
            cmd = String(cmd.dropFirst("/bin/bash -c \"".count).dropLast(1))
        } else if cmd.hasPrefix("/bin/zsh -c '") && cmd.hasSuffix("'") {
            cmd = String(cmd.dropFirst("/bin/zsh -c '".count).dropLast(1))
        } else if cmd.hasPrefix("zsh -c \"") && cmd.hasSuffix("\"") {
            cmd = String(cmd.dropFirst("zsh -c \"".count).dropLast(1))
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSoleCodeBlock = trimmed.hasPrefix("```") && trimmed.hasSuffix("```")
        let hasDirectExecutionIntent = lower.contains("i will run") ||
                                      lower.contains("i'll run") ||
                                      lower.contains("let's run") ||
                                      lower.contains("running the following") ||
                                      lower.contains("executing the command") ||
                                      lower.contains("executing:") ||
                                      isSoleCodeBlock
        guard hasDirectExecutionIntent else { return nil }

        return ToolRequest(
            type: "file_system",
            title: "terminal used",
            description: "Executing terminal command...",
            fields: [],
            action: "execute_command",
            command: cmd
        )
    }

    /// Some models follow the compact tool signature shown in their prompt or special model tokens
    /// and emit `[internet_use(query='...', description='...')]` or `<|tool_call_start|>[...]<|tool_call_end|>`
    /// instead of a JSON envelope. Parse keyword and positional arguments into a validated ToolRequest.
    private static func parseFunctionStyleToolCall(_ text: String) -> ToolRequest? {
        var unbracketed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if unbracketed.hasPrefix("<|tool_call_start|>") {
            unbracketed = String(unbracketed.dropFirst("<|tool_call_start|>".count))
        }
        if unbracketed.hasSuffix("<|tool_call_end|>") {
            unbracketed = String(unbracketed.dropLast("<|tool_call_end|>".count))
        }
        unbracketed = unbracketed.trimmingCharacters(in: .whitespacesAndNewlines)
        if unbracketed.hasPrefix("[") && unbracketed.hasSuffix("]") {
            unbracketed = String(unbracketed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Pattern for tool_name(args...)
        let pattern = #"(?is)^\s*([a-zA-Z0-9_-]+)\s*\(\s*(.*?)\s*\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: unbracketed, range: NSRange(unbracketed.startIndex..., in: unbracketed)),
              let nameRange = Range(match.range(at: 1), in: unbracketed),
              let argsRange = Range(match.range(at: 2), in: unbracketed) else { return nil }

        let toolName = String(unbracketed[nameRange]).lowercased()
        let rawArgs = String(unbracketed[argsRange])
        let kwargs = parsePythonKwargs(rawArgs)

        if toolName == "internet_use" || toolName == "web_search" {
            let query = kwargs["query"] ?? kwargs["q"] ?? kwargs["search_query"] ?? kwargs["_positional"] ?? ""
            let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanQuery.isEmpty else { return nil }
            return ToolRequest(
                type: "internet_use",
                title: kwargs["title"] ?? "Searching the web",
                description: kwargs["description"] ?? "Retrieving current information",
                fields: [],
                query: cleanQuery
            )
        } else if toolName == "file_system" || toolName == "terminal" || toolName == "execute_command" {
            let action = kwargs["action"] ?? "execute_command"
            let cmd = kwargs["command"] ?? kwargs["cmd"] ?? kwargs["_positional"]
            return ToolRequest(
                type: "file_system",
                title: "terminal used",
                description: kwargs["description"] ?? "Executing local file system action...",
                fields: [],
                action: action,
                path: kwargs["path"] ?? kwargs["file_path"],
                content: kwargs["content"],
                command: cmd
            )
        } else if toolName == "task_management" {
            let action = kwargs["action"] ?? "create"
            let title = kwargs["title"] ?? kwargs["groupname"] ?? kwargs["_positional"] ?? "Task action"
            return ToolRequest(
                type: "task_management",
                title: title,
                description: kwargs["description"] ?? "",
                fields: [],
                action: action,
                taskId: kwargs["taskid"].flatMap(UUID.init(uuidString:)),
                dueDate: kwargs["duedate"],
                groupName: kwargs["groupname"]
            )
        } else if toolName == "apple_notes" {
            let action = kwargs["action"] ?? "create_note"
            let title = kwargs["title"] ?? kwargs["name"] ?? "Apple Notes"
            return ToolRequest(
                type: "apple_notes",
                title: title,
                description: kwargs["description"] ?? "",
                fields: [],
                query: kwargs["query"] ?? kwargs["_positional"],
                action: action,
                content: kwargs["content"],
                folder: kwargs["folder"],
                noteId: kwargs["noteid"] ?? kwargs["id"]
            )
        }

        return nil
    }

    private static func parsePythonKwargs(_ rawArgs: String) -> [String: String] {
        var result: [String: String] = [:]
        let trimmed = rawArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return result }

        // 1. Check if it is a single quoted or unquoted string (positional argument)
        let posPattern = #"^\s*(['"])(.*?)\1\s*$"#
        if let regex = try? NSRegularExpression(pattern: posPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let valRange = Range(match.range(at: 2), in: trimmed) {
            let val = String(trimmed[valRange])
                .replacingOccurrences(of: #"\'"#, with: "'")
                .replacingOccurrences(of: #"\""#, with: "\"")
            result["_positional"] = val
            return result
        }

        // 2. Parse key=value pairs
        let pattern = #"(?is)(?:^|,\s*)([a-zA-Z0-9_]+)\s*[:=]\s*(?:(['"])(.*?)\2|\[(.*?)\]|\{(.*?)\}|([^,]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: trimmed) else { continue }
            let key = String(trimmed[keyRange]).lowercased()
            
            if match.range(at: 3).location != NSNotFound, let valRange = Range(match.range(at: 3), in: trimmed) {
                var val = String(trimmed[valRange])
                val = val.replacingOccurrences(of: #"\'"#, with: "'")
                         .replacingOccurrences(of: #"\""#, with: "\"")
                         .replacingOccurrences(of: #"\\"#, with: "\\")
                result[key] = val
            } else if match.range(at: 6).location != NSNotFound, let valRange = Range(match.range(at: 6), in: trimmed) {
                let val = String(trimmed[valRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if val != "[]" && val != "{}" && val != "None" && val != "null" {
                    result[key] = val
                }
            }
        }
        return result
    }

    /// Gemma, Qwen, Hermès, Llama, and local OpenAI-compatible models emit tool calls using
    /// `<|tool_call|>call:file_system{...}<tool_call|>` or `<|tool_call_start|>[...]<|tool_call_end|>`
    /// instead of a standalone JSON response. Normalize all native tool calls so they use the
    /// same execution path as cloud-model JSON calls.
    private static func parseNativeToolCall(text: String) -> ToolRequest? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains("<|tool_call|>") || cleaned.contains("<|tool_call>") || cleaned.contains("<tool_call>") || cleaned.contains("call:") || cleaned.contains("<|tool_call_start|>") else {
            return nil
        }

        // Accept provider-native XML function calls before looking for JSON
        // braces. Values still flow through normal decoding and validation.
        if let xmlRequest = parseXMLNativeToolCall(cleaned) {
            return xmlRequest
        }
        
        // Isolate the tool call block after <|tool_call_start|>, <|tool_call|>, <tool_call>, or call:
        var toolCallSub: String = cleaned
        if let callRange = cleaned.range(of: "<|tool_call_start|>") ?? cleaned.range(of: "<|tool_call|>") ?? cleaned.range(of: "<|tool_call>") ?? cleaned.range(of: "<tool_call>") ?? cleaned.range(of: "call:") {
            toolCallSub = String(cleaned[callRange.upperBound...])
            if let endRange = toolCallSub.range(of: "<|tool_call_end|>") ?? toolCallSub.range(of: "</tool_call>") ?? toolCallSub.range(of: "<|tool_call|>") {
                toolCallSub = String(toolCallSub[..<endRange.lowerBound])
            }
        }
        
        // Find inner JSON object { ... } within the tool call section
        guard let start = toolCallSub.firstIndex(of: "{") else {
            return nil
        }
        let jsonStr = {
            if let end = toolCallSub.lastIndex(of: "}") {
                return String(toolCallSub[start...end])
            }
            return String(toolCallSub[start...])
        }()
        
        // 1. Try parsing directly via parseJSON if it has standard structure
        if let parsed = parseJSON(text: jsonStr) {
            return parsed
        }
        
        // 2. Parse dictionary representation
        let dict = (jsonStr.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        
        func extractField(_ name: String) -> String? {
            if let strVal = dict[name] as? String { return strVal }
            // Gemma's native chat template represents quote characters as
            // `<|"|>` inside tool calls, e.g. `url:<|"|>https://…<|"|>`.
            // Normalize those transport tokens before scanning fields.
            let source = jsonStr
                .replacingOccurrences(of: "<|\"|>", with: "\"")
                .replacingOccurrences(of: "<|'|>", with: "'")
            // Local models frequently emit JavaScript-like objects with
            // unquoted keys. Scan quoted values while honoring escapes; the
            // previous regex stopped at the first `\"` inside HTML and wrote
            // only a tiny prefix of generated files.
            let pattern = #"[\"']?"# + NSRegularExpression.escapedPattern(for: name) + #"[\"']?\s*:\s*([\"'])"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  let quoteRange = Range(match.range(at: 1), in: source) else {
                // Last-resort support for unquoted native values such as
                // `path:/Users/name/Documents`.
                let barePattern = #"[\"']?"# + NSRegularExpression.escapedPattern(for: name) + #"[\"']?\s*:\s*([^,}\n]+)"#
                guard let bareRegex = try? NSRegularExpression(pattern: barePattern),
                      let bareMatch = bareRegex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                      let valueRange = Range(bareMatch.range(at: 1), in: source) else { return nil }
                return String(source[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let quote = source[quoteRange.lowerBound]
            var index = quoteRange.upperBound
            var escaped = false
            while index < source.endIndex {
                let character = source[index]
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == quote {
                    let rawValue = String(source[quoteRange.upperBound..<index])
                    // Decode JSON escapes such as \n and \". Single-quoted
                    // values are uncommon but still return their raw content.
                    if quote == "\"",
                       let wrapped = ("\"" + rawValue + "\"").data(using: .utf8),
                       let decoded = try? JSONSerialization.jsonObject(with: wrapped) as? String {
                        return decoded
                    }
                    return rawValue
                }
                index = source.index(after: index)
            }
            return String(source[quoteRange.upperBound..<index])
        }
        
        // Identify tool type from text markers
        let lower = cleaned.lowercased()
        // Native tool APIs commonly place the tool name outside the arguments,
        // leaving the inner object without our required `type`. Restore it so
        // Dynamic Input, Insights, and Tesaract use the normal decoder too.
        if lower.contains("request_input") || lower.contains("dynamic_input") || lower.contains("dynamic_insights") || lower.contains("tool_1") || lower.contains("tool_2") {
            var normalized = dict
            normalized["type"] = "request_input"
            if let data = try? JSONSerialization.data(withJSONObject: normalized),
               let request = try? JSONDecoder().decode(ToolRequest.self, from: data),
               !request.fields.isEmpty {
                return request
            }
        } else if lower.contains("tesaract") || lower.contains("teseract") || lower.contains("tesseract") || lower.contains("tool_3") {
            var normalized = dict
            normalized["type"] = "tesaract"
            if let data = try? JSONSerialization.data(withJSONObject: normalized),
               let request = try? JSONDecoder().decode(ToolRequest.self, from: data) {
                return request
            }
        }

        if lower.contains("file_system") || lower.contains("tool_6") || extractField("path") != nil || extractField("command") != nil {
            let action = extractField("action") ?? "execute_command"
            return ToolRequest(
                type: "file_system",
                title: "terminal used",
                description: "Executing local file system action...",
                fields: [],
                action: action,
                path: extractField("path"),
                content: extractField("content"),
                command: extractField("command")
            )
        } else if lower.contains("task_management") || lower.contains("tool_7") {
            let action = extractField("action") ?? "create"
            let title = extractField("title") ?? extractField("groupName") ?? "Task action"
            let taskId = extractField("taskId").flatMap(UUID.init(uuidString:))
            return ToolRequest(
                type: "task_management",
                title: title,
                description: extractField("description") ?? "",
                fields: [],
                action: action,
                taskId: taskId,
                dueDate: extractField("dueDate"),
                groupName: extractField("groupName"),
                position: dict["position"] as? Int
            )
        } else if lower.contains("internet_use") || lower.contains("tool_4") {
            return ToolRequest(
                type: "internet_use",
                title: extractField("title") ?? "Searching the web...",
                description: extractField("description") ?? "",
                fields: [],
                query: extractField("query")
            )
        } else if lower.contains("advanced_memory") || lower.contains("tool_5") {
            return ToolRequest(
                type: "advanced_memory",
                title: extractField("title") ?? "Updating memory graph...",
                description: extractField("description") ?? "",
                fields: [],
                action: extractField("action") ?? "upsert"
            )
        } else if lower.contains("\"type\":\"learning\"") || lower.contains("type: learning") {
            return ToolRequest(
                type: "learning",
                title: extractField("title") ?? "Updating learning...",
                description: extractField("description") ?? "",
                fields: [],
                action: extractField("action") ?? "list",
                content: extractField("content"),
                learningId: extractField("learningId"),
                learningKind: extractField("learningKind"),
                learningTopic: extractField("learningTopic")
            )
        }
        
        return nil
    }

    private static func parseXMLNativeToolCall(_ text: String) -> ToolRequest? {
        let functionPattern = #"(?is)<function\s*=\s*[\"']?([^>\"'\s]+)[\"']?\s*>(.*?)</function>"#
        guard let functionRegex = try? NSRegularExpression(pattern: functionPattern),
              let functionMatch = functionRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(functionMatch.range(at: 1), in: text),
              let bodyRange = Range(functionMatch.range(at: 2), in: text) else { return nil }

        let functionName = String(text[nameRange])
        let body = String(text[bodyRange])
        let parameterPattern = #"(?is)<parameter\s*=\s*[\"']?([^>\"'\s]+)[\"']?\s*>(.*?)</parameter>"#
        guard let parameterRegex = try? NSRegularExpression(pattern: parameterPattern) else { return nil }
        let matches = parameterRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
        var arguments: [String: Any] = [:]

        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: body),
                  let valueRange = Range(match.range(at: 2), in: body) else { continue }
            let key = String(body[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(body[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if rawValue == "true" || rawValue == "false" {
                arguments[key] = rawValue == "true"
            } else if let integer = Int(rawValue) {
                arguments[key] = integer
            } else if let double = Double(rawValue) {
                arguments[key] = double
            } else if let data = rawValue.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      JSONSerialization.isValidJSONObject(object) {
                arguments[key] = object
            } else {
                arguments[key] = rawValue
            }
        }

        guard let normalized = normalizedWrappedToolRequest([
            "name": functionName,
            "arguments": arguments
        ]),
              let data = try? JSONSerialization.data(withJSONObject: normalized),
              let request = try? JSONDecoder().decode(ToolRequest.self, from: data),
              isDispatchableToolRequest(request) else { return nil }
        return request
    }
    
    public static func parseJSON(text: String) -> ToolRequest? {
        // Find all candidate opening braces in the response text
        var indices: [String.Index] = []
        var curIdx = text.startIndex
        while curIdx < text.endIndex {
            if text[curIdx] == "{" {
                indices.append(curIdx)
            }
            curIdx = text.index(after: curIdx)
        }
        
        // Scan each brace from first to last to find the decodable ToolRequest structure
        for startIdx in indices {
            var braceCount = 0
            var jsonEndIndex: String.Index?
            var inString = false
            var isEscaped = false
            
            var currentIndex = startIdx
            while currentIndex < text.endIndex {
                let char = text[currentIndex]
                
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString.toggle()
                } else if !inString {
                    if char == "{" {
                        braceCount += 1
                    } else if char == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            jsonEndIndex = text.index(after: currentIndex)
                            break
                        }
                    }
                }
                currentIndex = text.index(after: currentIndex)
            }
            
            guard let endIndex = jsonEndIndex else {
                continue
            }
            
            let jsonString = String(text[startIdx..<endIndex])
            guard let jsonData = jsonString.data(using: .utf8) else {
                continue
            }

            // Normalize OpenAI-compatible and local-model tool envelopes:
            // {"name":"request_input","arguments":{...}} and
            // {"function":{"name":"tesaract","arguments":"{...}"}}.
            // Previously these decoded as an empty ToolRequest (or not at all),
            // so Dynamic Input and Tesaract never reached dispatch.
            if let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let normalized = normalizedWrappedToolRequest(raw),
               let normalizedData = try? JSONSerialization.data(withJSONObject: normalized),
               let request = try? JSONDecoder().decode(ToolRequest.self, from: normalizedData),
               isDispatchableToolRequest(request) {
                return request
            }

            // Some local models incorrectly wrap a requested command in a
            // `tool_response` object. It is still an unexecuted request when
            // it contains an action/command, so normalize it before decoding
            // the standard tool schema.
            if let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let response = raw["tool_response"] as? [String: Any],
               let action = response["action"] as? String,
               let command = response["command"] as? String,
               !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ToolRequest(
                    type: "file_system",
                    title: "terminal used",
                    description: "Executing local command...",
                    fields: [],
                    action: action,
                    path: response["path"] as? String,
                    command: command
                )
            }

            // Gemma often emits the compact form `{ "action": ..., "command": ... }`
            // and omits our `type` wrapper. Treat it as a terminal request.
            if let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let action = raw["action"] as? String,
               let command = raw["command"] as? String,
               !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ToolRequest(
                    type: "file_system",
                    title: "terminal used",
                    description: "Executing local command...",
                    fields: [],
                    action: action,
                    path: raw["path"] as? String,
                    content: raw["content"] as? String,
                    command: command
                )
            }

            // Infer compact native filesystem actions too. This deliberately
            // uses an allowlist: an arbitrary object with an `action` field is
            // not executable, while a known filesystem verb is normalized and
            // then still passes registry validation and command policy.
            if let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let action = raw["action"] as? String {
                let filesystemActions: Set<String> = [
                    "execute_command", "command", "terminal", "run_command", "shell", "shell_command", "exec",
                    "list", "ls", "list_directory", "list_files", "get_directory_contents",
                    "read_file", "read", "cat", "get_file", "read_text_file",
                    "create_file", "write_file", "save_file", "update_file", "create_files",
                    "create_folder", "create_directory", "make_directory", "mkdir", "new_folder", "make_folder",
                    "organize_images", "organize_downloads", "organize_directory", "organize_documents", "organize_desktop"
                ]
                let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if filesystemActions.contains(normalizedAction) {
                    var normalized = raw
                    normalized["type"] = "file_system"
                    normalized["title"] = normalized["title"] ?? "terminal used"
                    normalized["description"] = normalized["description"] ?? "Executing filesystem action"
                    normalized["fields"] = normalized["fields"] ?? []
                    if let normalizedData = try? JSONSerialization.data(withJSONObject: normalized),
                       let request = try? JSONDecoder().decode(ToolRequest.self, from: normalizedData) {
                        return request
                    }
                }
            }

            // Search models sometimes emit only {"query":"…"}. Restrict
            // this inference to objects whose keys are all search metadata so
            // ordinary JSON data with a query field is not treated as a tool.
            if let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let singleQuery = (raw["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let multiQueries = (raw["queries"] as? [String])?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if (singleQuery != nil && !singleQuery!.isEmpty) || (multiQueries != nil && !multiQueries!.isEmpty) {
                    let allowedSearchKeys: Set<String> = ["query", "queries", "title", "description", "type", "tool", "tool_name", "name"]
                    if Set(raw.keys).isSubset(of: allowedSearchKeys) {
                        return ToolRequest(
                            type: "internet_use",
                            title: raw["title"] as? String ?? "Searching the web",
                            description: raw["description"] as? String ?? "Retrieving current information",
                            fields: [],
                            query: singleQuery ?? multiQueries?.first,
                            queries: multiQueries
                        )
                    }
                }
            }
            
            do {
                let decoder = JSONDecoder()
                let request = try decoder.decode(ToolRequest.self, from: jsonData)
                if !request.fields.isEmpty || request.type == "tesaract" || request.type == "internet_use" || request.type == "advanced_memory" || request.type == "file_system" || request.type == "task_management" || request.type == "apple_notes" {
                    return request
                }
            } catch {
                continue // Not a valid ToolRequest JSON block, check the next one
            }
        }
        
        return nil
    }

    private static func normalizedWrappedToolRequest(_ raw: [String: Any]) -> [String: Any]? {
        let function = raw["function"] as? [String: Any]
        // Some local models use the tool name itself as the envelope key:
        // {"file_system":{"action":"create_folder","path":"project_x"}}.
        // Detect that shape before resolving the conventional name fields.
        let supportedEnvelopeNames = [
            "request_input", "dynamic_input", "dynamic_insights", "tesaract", "tesseract",
            "internet_use", "web_search", "advanced_memory", "memory", "file_system",
            "filesystem", "terminal_access", "task_management", "learning",
            "apple_notes", "notes", "apple_notes_api", "notes_app"
        ]
        let keyedEnvelope = raw.first { key, value in
            let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
            return value is [String: Any] && supportedEnvelopeNames.contains(normalized)
        }
        let rawName = (function?["name"] as? String)
            ?? (raw["tool_name"] as? String)
            ?? (raw["tool"] as? String)
            ?? (raw["name"] as? String)
            ?? (raw["type"] as? String)
            ?? keyedEnvelope?.key
        guard let rawName else { return nil }

        let name = rawName.lowercased().replacingOccurrences(of: "-", with: "_")
        let type: String
        if name.contains("request_input") || name.contains("dynamic_input") || name.contains("dynamic_insight") || name == "tool_1" || name == "tool_2" {
            type = "request_input"
        } else if name.contains("tesaract") || name.contains("teseract") || name.contains("tesseract") || name == "tool_3" {
            type = "tesaract"
        } else if name.contains("internet_use") || name.contains("internet_search") || name.contains("web_search") || name == "tool_4" {
            type = "internet_use"
        } else if name.contains("advanced_memory") || name == "memory" || name == "tool_5" {
            type = "advanced_memory"
        } else if name.contains("file_system") || name.contains("filesystem") || name.contains("terminal_access") || name == "tool_6" {
            type = "file_system"
        } else if name.contains("apple_notes") || name.contains("notes_app") || name == "notes" || name == "apple_notes_api" {
            type = "apple_notes"
        } else if name.contains("task_management") || name == "tool_7" {
            type = "task_management"
        } else if name == "learning" {
            type = "learning"
        } else if name.hasPrefix("mcp_") || name == "mcp_call" || name == "mcp" || name == "mcp_tool" || MCPServerManager.shared.allTools.contains(where: { $0.qualifiedName == name || $0.name.lowercased() == name }) {
            type = "mcp"
        } else {
            return nil
        }

        let rawArguments = function?["arguments"] ?? raw["arguments"] ?? keyedEnvelope?.value
        var arguments: [String: Any]
        if let dictionary = rawArguments as? [String: Any] {
            arguments = dictionary
        } else if let string = rawArguments as? String,
                  let data = string.data(using: .utf8),
                  let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = dictionary
        } else {
            arguments = raw
            arguments.removeValue(forKey: "tool_name")
            arguments.removeValue(forKey: "tool")
            arguments.removeValue(forKey: "name")
            arguments.removeValue(forKey: "function")
            arguments.removeValue(forKey: "arguments")
        }
        arguments["type"] = type

        if type == "mcp" {
            if arguments["title"] == nil { arguments["title"] = "MCP: \(rawName)" }
            if arguments["description"] == nil { arguments["description"] = "Executing \(rawName)..." }
            if arguments["mcpTool"] == nil { arguments["mcpTool"] = rawName }
            if let server = arguments["server"] as? String { arguments["mcpServer"] = server }
            if let tool = arguments["tool"] as? String { arguments["mcpTool"] = tool }
        }

        if type == "tesaract", arguments["html"] == nil {
            arguments["html"] = arguments["code"] ?? arguments["content"]
        }

        if type == "request_input", arguments["fields"] == nil {
            arguments["fields"] = arguments["inputs"] ?? arguments["questions"]
        }

        if type == "request_input", var fields = arguments["fields"] as? [[String: Any]] {
            for index in fields.indices {
                if fields[index]["id"] == nil { fields[index]["id"] = fields[index]["name"] ?? "field_\(index + 1)" }
                if fields[index]["label"] == nil { fields[index]["label"] = fields[index]["title"] ?? fields[index]["prompt"] ?? "Input \(index + 1)" }
                if fields[index]["suggestions"] == nil { fields[index]["suggestions"] = fields[index]["options"] }
                let rawType = (fields[index]["type"] as? String)?.lowercased() ?? "text"
                let normalizedType: String
                switch rawType {
                case "string", "input", "textfield", "text_field": normalizedType = "text"
                case "choice", "radio", "singlechoice": normalizedType = "single_choice"
                case "multi_choice", "checkbox", "multiplechoice": normalizedType = "multiple_choice"
                case "toggle", "bool": normalizedType = "boolean"
                case "select", "menu": normalizedType = "dropdown"
                default: normalizedType = rawType
                }
                fields[index]["type"] = normalizedType
            }
            arguments["fields"] = fields
        }
        return arguments
    }

    private static func isDispatchableToolRequest(_ request: ToolRequest) -> Bool {
        if !request.fields.isEmpty { return true }
        return [
            "tesaract",
            "internet_use",
            "advanced_memory",
            "file_system",
            "apple_notes",
            "task_management",
            "learning",
            "mcp"
        ].contains(request.type ?? "")
    }
    
    public static func parseHeuristicFallback(text: String) -> ToolRequest? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. App installation. Prefer this to the app-launch heuristic below so
        // requests such as "install Chrome" never become `open -a 'the'`.
        if let installRange = normalized.range(of: "\\binstal{1,2}(?:l|ling)?\\s+(.+)", options: .regularExpression) {
            let requestedApp = String(text[installRange]).replacingOccurrences(
                of: "^.*?\\binstal{1,2}(?:l|ling)?\\s+",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " please", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

            if !requestedApp.isEmpty, requestedApp.count <= 60 {
                let caskNames = [
                    "chrome": "google-chrome",
                    "google chrome": "google-chrome",
                    "firefox": "firefox",
                    "visual studio code": "visual-studio-code",
                    "vscode": "visual-studio-code",
                    "discord": "discord",
                    "slack": "slack",
                    "zoom": "zoom"
                ]
                let cask = caskNames[requestedApp.lowercased()] ?? requestedApp
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                let command = """
                if command -v brew >/dev/null 2>&1; then
                  BREW="$(command -v brew)"
                else
                  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || exit $?
                  if [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew;
                  elif [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew;
                  else echo "Homebrew installation completed, but brew was not found in a standard location."; exit 1; fi
                fi
                "$BREW" install --cask \(cask)
                """
                return ToolRequest(
                    type: "file_system",
                    title: "Install \(requestedApp.capitalized)",
                    description: "Installing \(requestedApp) with Homebrew...",
                    fields: [],
                    action: "execute_command",
                    command: command
                )
            }
        }
        
        // 2. YouTube Search Heuristic Check (e.g. "open safari and search youtube for 'best tech videos'")
        if (normalized.contains("youtube") && (normalized.contains("search") || normalized.contains("find") || normalized.contains("look up") || normalized.contains("go to"))) || normalized.contains("youtube.com/results") {
            var searchQuery = ""
            if let firstQuote = text.firstIndex(of: "\""), let lastQuote = text.lastIndex(of: "\""), firstQuote != lastQuote {
                searchQuery = String(text[text.index(after: firstQuote)..<lastQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let forRange = normalized.range(of: "search for ") {
                searchQuery = String(text[forRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let searchRange = normalized.range(of: "search ") {
                searchQuery = String(text[searchRange.upperBound...]).replacingOccurrences(of: "youtube", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if !searchQuery.isEmpty {
                let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
                let urlStr = "https://www.youtube.com/results?search_query=\(encodedQuery)"
                return ToolRequest(
                    type: "file_system",
                    title: "Search YouTube: \"\(searchQuery)\"",
                    description: "Searching YouTube for '\(searchQuery)'...",
                    fields: [],
                    action: "execute_command",
                    command: "open \"\(urlStr)\""
                )
            }
        }
        
        // 3. Direct Website URL Opening (e.g. "open youtube.com", "open google.com", "go to github.com")
        if normalized.contains(".com") || normalized.contains(".org") || normalized.contains(".io") || normalized.contains(".net") || normalized.contains("https://") || normalized.contains("http://") {
            let words = normalized.components(separatedBy: .whitespacesAndNewlines)
            if let targetDomain = words.first(where: { $0.contains(".com") || $0.contains(".org") || $0.contains(".io") || $0.contains("http") }) {
                var cleanUrl = targetDomain.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if !cleanUrl.hasPrefix("http://") && !cleanUrl.hasPrefix("https://") {
                    cleanUrl = "https://" + cleanUrl
                }
                return ToolRequest(
                    type: "file_system",
                    title: "Open Website: \(targetDomain)",
                    description: "Opening \(targetDomain)...",
                    fields: [],
                    action: "execute_command",
                    command: "open \"\(cleanUrl)\""
                )
            }
        }
        
        // 4. Application launching heuristic check (e.g. "open spotify", "launch safari", "open calculator")
        let openTriggers = ["open ", "launch ", "start ", "run "]
        for trigger in openTriggers {
            if normalized.hasPrefix(trigger) || normalized.contains(" " + trigger) {
                if let range = normalized.range(of: trigger) {
                    let sub = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    var cleanApp = ""
                    for char in sub {
                        if char == "." || char == "?" || char == "!" || char == "\n" || char == "," || char == " " { break }
                        cleanApp.append(char)
                    }
                    cleanApp = cleanApp.replacingOccurrences(of: "for me", with: "", options: .caseInsensitive)
                                       .replacingOccurrences(of: "please", with: "", options: .caseInsensitive)
                                       .replacingOccurrences(of: "app", with: "", options: .caseInsensitive)
                                       .trimmingCharacters(in: .whitespacesAndNewlines)
                    let genericWords = Set(["a", "an", "the", "app", "application", "it", "this", "that"])
                    if !cleanApp.isEmpty && cleanApp.count <= 25 && !genericWords.contains(cleanApp.lowercased()) {
                        let capitalApp = cleanApp.capitalized
                        return ToolRequest(
                            type: "file_system",
                            title: "Open \(capitalApp)",
                            description: "Opening application \(capitalApp)...",
                            fields: [],
                            action: "execute_command",
                            command: "open -a '\(cleanApp)'"
                        )
                    }
                }
            }
        }
        
        // Search check: if assistant states they are searching/checking the web
        if normalized.contains("searching the web for") || 
           normalized.contains("searching the internet for") ||
           normalized.contains("let me search the web for") ||
           normalized.contains("let me check the web for") ||
           normalized.contains("i will search the web for") ||
           normalized.contains("i need to search the web for") ||
           normalized.contains("performing a web search for") {
            
            var extractedQuery = ""
            if let forRange = normalized.range(of: "for ") {
                let sub = text[forRange.upperBound...]
                let cleanSub = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                var queryPart = ""
                for char in cleanSub {
                    if char == "." || char == "?" || char == "!" || char == "\n" {
                        break
                    }
                    queryPart.append(char)
                }
                extractedQuery = queryPart.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if !extractedQuery.isEmpty {
                return ToolRequest(
                    type: "internet_use",
                    title: "Internet Search",
                    description: "Searching the web...",
                    fields: [],
                    query: extractedQuery
                )
            }
        }
        
    
    return nil
    }
}

public struct ParsedReasoningResponse {
    public let reasoningText: String?
    public let mainText: String
    public let isThinkingComplete: Bool
    
    nonisolated public init(reasoningText: String?, mainText: String, isThinkingComplete: Bool) {
        self.reasoningText = reasoningText
        self.mainText = mainText
        self.isThinkingComplete = isThinkingComplete
    }
}

extension ChatMessage {
    public var isToolRequest: Bool {
        ToolRequestParser.parseJSON(text: self.text) != nil
    }
    
    public var isToolResponse: Bool {
        if text.contains("tool_response") || text.contains("\"tool_response\"") {
            return true
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["tool_response"] != nil
    }
    
    public var isStreamingJSON: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Local model templates often begin streaming native tool transport
        // before the JSON payload is complete. Treat it as a tool action from
        // the first marker so raw `<|tool_call|>` never flashes in the chat.
        if trimmed.contains("<|tool_call|>") || trimmed.contains("<|tool_call>") || trimmed.contains("<tool_call>") || trimmed.contains("call:") {
            return true
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("```json") {
            return true
        }
        if trimmed.hasPrefix("```") {
            let clean = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.hasPrefix("{") || clean.contains("\"type\"") || clean.contains("\"request_input\"")
        }
        return false
    }
    
    public var isStreamingSearchJSON: Bool {
        guard isStreamingJSON else { return false }
        let normalized = text.lowercased()
        return normalized.contains("internet_use")
    }
    
    public var isStreamingFileSystemJSON: Bool {
        let normalized = text.lowercased()
        return normalized.contains("file_system") &&
            (isStreamingJSON || normalized.contains("<|tool_call|>") || normalized.contains("<tool_call>"))
    }

    public var isStreamingAppleNotesJSON: Bool {
        let normalized = text.lowercased()
        return (normalized.contains("apple_notes") || normalized.contains("notes_app")) &&
            (isStreamingJSON || normalized.contains("<|tool_call|>") || normalized.contains("<tool_call>"))
    }

    public var isStreamingTaskJSON: Bool {
        let normalized = text.lowercased()
        return (normalized.contains("task_management") || normalized.contains("tasks_management") || normalized.contains("tool_7")) &&
            (isStreamingJSON || normalized.contains("<|tool_call|>") || normalized.contains("<tool_call>"))
    }
    
    private static var strippedTextCache: [String: String] = [:]
    private static let strippedTextLock = NSLock()
    
    private static func findJSONRange(in text: String) -> Range<String.Index>? {
        guard text.contains("{") else { return nil }
        guard text.contains("\"type\"") || text.contains("\"request_input\"") || text.contains("\"fields\"") else { return nil }
        
        guard let startBrace = text.range(of: "{")?.lowerBound else { return nil }
        
        var braceCount = 0
        var inString = false
        var isEscaped = false
        var jsonEndIndex: String.Index? = nil
        
        var curIdx = startBrace
        while curIdx < text.endIndex {
            let char = text[curIdx]
            if isEscaped {
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        jsonEndIndex = text.index(after: curIdx)
                        break
                    }
                }
            }
            curIdx = text.index(after: curIdx)
        }
        
        if let endIndex = jsonEndIndex {
            return startBrace..<endIndex
        } else {
            return startBrace..<text.endIndex
        }
    }
    
    public var parsedReasoning: ParsedReasoningResponse {
        return ChatMessage.extractReasoning(from: self.text)
    }

    
    nonisolated public static func extractReasoning(from text: String) -> ParsedReasoningResponse {
        var raw = text
        // Native local-model tool calls are execution instructions, never
        // user-facing prose. Their parsed ToolRequest still executes from the
        // original message text; hide the transport syntax in the bubble.
        raw = raw.replacingOccurrences(
            of: #"<\|tool_call_start\|>.*?<\|tool_call_end\|>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        raw = raw.replacingOccurrences(
            of: #"<\|tool_call\|>.*?<\|tool_call\|>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        raw = raw.replacingOccurrences(
            of: #"<\|tool_call>.*?<tool_call\|>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        raw = raw.replacingOccurrences(
            of: #"<tool_call>.*?</tool_call>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Some Gemma templates include a suffix in the tool name (for example
        // `tool_7__tasks_management`). Remove that transport envelope even if
        // its formatting differs from the usual native call syntax.
        while let start = raw.range(of: "<|tool_call|>"),
              let end = raw.range(of: "<|tool_call|>", range: start.upperBound..<raw.endIndex) {
            raw.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // During streaming the closing marker has not arrived yet. Remove the
        // incomplete transport tail immediately so it can never flash as chat
        // text while the tool-call JSON is still being assembled.
        if let start = raw.range(of: "<|tool_call_start|>") {
            raw.removeSubrange(start.lowerBound..<raw.endIndex)
        }
        if let start = raw.range(of: "<|tool_call|>") {
            raw.removeSubrange(start.lowerBound..<raw.endIndex)
        }
        if let start = raw.range(of: "<|tool_call>") {
            raw.removeSubrange(start.lowerBound..<raw.endIndex)
        }
        if let start = raw.range(of: "<tool_call>") {
            raw.removeSubrange(start.lowerBound..<raw.endIndex)
        }
        
        // 1. Check GLM format with <|begin_of_box|> ... <|begin_of_box|> ... <|end_of_box|>
        if raw.contains("<|begin_of_box|>") {
            let parts = raw.components(separatedBy: "<|begin_of_box|>")
            if parts.count >= 3 {
                // <|begin_of_box|> reasoning <|begin_of_box|> main text <|end_of_box|>
                let reasoning = parts[1].replacingOccurrences(of: "<|end_of_box|>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let main = parts[2...].joined(separator: "\n").replacingOccurrences(of: "<|end_of_box|>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let isComplete = raw.contains("<|end_of_box|>") || parts.count > 2
                return ParsedReasoningResponse(reasoningText: reasoning.isEmpty ? nil : reasoning, mainText: main, isThinkingComplete: isComplete)
            } else if parts.count == 2 {
                let secondPart = parts[1]
                if secondPart.contains("<|end_of_box|>") {
                    let subParts = secondPart.components(separatedBy: "<|end_of_box|>")
                    let reasoning = subParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let main = subParts.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    return ParsedReasoningResponse(reasoningText: reasoning.isEmpty ? nil : reasoning, mainText: main, isThinkingComplete: true)
                } else {
                    // Streaming thinking block before second box
                    let reasoning = secondPart.trimmingCharacters(in: .whitespacesAndNewlines)
                    return ParsedReasoningResponse(reasoningText: reasoning.isEmpty ? nil : reasoning, mainText: "", isThinkingComplete: false)
                }
            }
        }
        
        // 2. Check <think> ... </think>, <thought> ... </thought>, [THINKING] ... [/THINKING].
        // Some OpenAI-compatible servers emit one complete tag pair for every
        // streamed reasoning delta. Collect *all* of those pairs; treating only
        // the first pair as reasoning leaks the remaining XML tags into the chat.
        for (openTag, closeTag) in [("<think>", "</think>"), ("<thought>", "</thought>"), ("[THINKING]", "[/THINKING]")] {
            if raw.contains(openTag) {
                var remaining = raw[...]
                var reasoningParts: [String] = []
                var mainParts: [String] = []
                var isComplete = true

                while let openRange = remaining.range(of: openTag) {
                    let before = String(remaining[..<openRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !before.isEmpty {
                        mainParts.append(before)
                    }

                    let afterOpen = remaining[openRange.upperBound...]
                    guard let closeRange = afterOpen.range(of: closeTag) else {
                        let partialReasoning = String(afterOpen)
                        if !partialReasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            reasoningParts.append(partialReasoning)
                        }
                        isComplete = false
                        remaining = ""[...]
                        break
                    }

                    let reasoning = String(afterOpen[..<closeRange.lowerBound])
                    if !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        reasoningParts.append(reasoning)
                    }
                    remaining = afterOpen[closeRange.upperBound...]
                }

                let trailingMain = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trailingMain.isEmpty {
                    mainParts.append(trailingMain)
                }

                return ParsedReasoningResponse(
                    reasoningText: reasoningParts.isEmpty ? nil : reasoningParts.joined().trimmingCharacters(in: .whitespacesAndNewlines),
                    mainText: mainParts.joined(separator: "\n\n"),
                    isThinkingComplete: isComplete
                )
            }
        }
        
        // Clean any leftover standalone tags
        let cleanText = raw.replacingOccurrences(of: "<|begin_of_box|>", with: "")
                           .replacingOccurrences(of: "<|end_of_box|>", with: "")
        
        // 3. Check for bare "thought" prefix block without XML tags.
        let lowerClean = cleanText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerClean.hasPrefix("thought\n") || lowerClean.hasPrefix("thought:\n") {
            let actualRaw = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Find the start of the next block.
            if let backtickRange = actualRaw.range(of: "```") {
                let reasoning = String(actualRaw[..<backtickRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedReasoning = reasoning.replacingOccurrences(of: "^(?i)thought:?\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                let main = String(actualRaw[backtickRange.lowerBound...])
                return ParsedReasoningResponse(reasoningText: cleanedReasoning.isEmpty ? nil : cleanedReasoning, mainText: main, isThinkingComplete: true)
            } else {
                let cleanedReasoning = actualRaw.replacingOccurrences(of: "^(?i)thought:?\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                // Never zero out mainText; make sure the content remains visible
                return ParsedReasoningResponse(reasoningText: cleanedReasoning.isEmpty ? nil : cleanedReasoning, mainText: actualRaw, isThinkingComplete: true)
            }
        }
        
        return ParsedReasoningResponse(reasoningText: nil, mainText: cleanText, isThinkingComplete: true)
    }

    public var introText: String {
        let text = self.parsedReasoning.mainText
        guard let jsonRange = ChatMessage.findJSONRange(in: text) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var intro = String(text[..<jsonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip trailing markdown JSON code block markers (e.g. ```json, ```JSON, ```)
        let lower = intro.lowercased()
        if let range = lower.range(of: "```json", options: .backwards) {
            let after = lower[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if after.isEmpty {
                intro = String(intro[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let range = lower.range(of: "```", options: .backwards) {
            let after = lower[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if after.isEmpty {
                intro = String(intro[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return intro
    }
    
    public var conclusionText: String {
        let text = self.parsedReasoning.mainText
        guard let jsonRange = ChatMessage.findJSONRange(in: text) else {
            return ""
        }
        var conclusion = String(text[jsonRange.upperBound...])
        
        // Strip leading markdown tags like ```
        conclusion = conclusion.trimmingCharacters(in: .whitespacesAndNewlines)
        if conclusion.hasPrefix("```") {
            conclusion = String(conclusion.dropFirst(3))
        }
        return conclusion.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var strippedText: String {
        let originalText = self.text
        
        ChatMessage.strippedTextLock.lock()
        if let cached = ChatMessage.strippedTextCache[originalText] {
            ChatMessage.strippedTextLock.unlock()
            return cached
        }
        ChatMessage.strippedTextLock.unlock()
        
        let intro = introText
        let conclusion = conclusionText
        let result: String
        if intro.isEmpty {
            result = conclusion
        } else if conclusion.isEmpty {
            result = intro
        } else {
            result = intro + "\n\n" + conclusion
        }
        
        ChatMessage.strippedTextLock.lock()
        ChatMessage.strippedTextCache[originalText] = result
        ChatMessage.strippedTextLock.unlock()
        
        return result
    }

}

public let toolRequestInstructions = """
SYSTEM INSTRUCTION - DYNAMIC INPUT, SEARCH & MEMORY GRAPH FRAMEWORK:

You have available tools. You MUST output at most ONE JSON block per response.

════════════════════════════════════
TOOL 1 — DYNAMIC INPUT (popup card)
════════════════════════════════════
Purpose: Collect static, user-specific values (weight, height, age, gender, dates, choices) via a floating popup card.
When to use: ONLY when you are missing essential personal data required to perform a calculation or personalisation task AND the user has NOT yet provided it.
How to use: Output ONLY the JSON block. NO conversational text before or after it.
Field types allowed: "number", "text", "single_choice", "multiple_choice", "boolean", "date", "time", "stepper", "dropdown".

════════════════════════════════════
TOOL 3 — TESARACT (custom HTML/JS blocks)
════════════════════════════════════
Purpose: Render an entirely custom, interactive, and intuitive block built dynamically with HTML, CSS, and JS.
When to use: ONLY when the user's task requires a specialized dashboard, advanced calculator, game, interactive diagram, or visual simulation that is not possible with simple sliders or static metric lists.
How to use: Set "type" to "tesaract". Provide a "title", a "description", and write the full standalone HTML code (including embedded CSS styling inside <style> and JavaScript interactivity/logic inside <script>) in the "html" string field. The app will compile and render it in a premium container.
DO NOT repeat Tool 3 after it has already been shown. ONE visualization per conversation topic.

════════════════════════════════════
TOOL 4 — INTERNET USE (web search)
════════════════════════════════════
Purpose: Perform a real-time web search to fetch search results from DuckDuckGo.
When to use: ONLY when the user's request requires current, real-time, or external factual information (e.g. current stock prices, date/events, weather, coding specs of recent libraries, news).
How to use: Output ONLY the JSON block. Do not write conversational text.

════════════════════════════════════
TOOL 5 — ADVANCED MEMORY (knowledge graph)
════════════════════════════════════
Purpose: Save, update, or remove user facts, preferences, goals, entities, and relationships in a structured graph.
When to use: When the user shares personal facts (e.g. names, age, location, goals, hobbies, likes, dislikes), asks to "remember" or "save" context, or asks to "forget" or "clear" memory. Map this information to nodes (entities) and edges (relations).
How to use: Output ONLY the JSON block. Set the type to "advanced_memory". Optional "action": "upsert" (default to add/update), "delete" (to remove nodes/edges), or "clear" (to wipe memory graph). Provide factual entity nodes and edges whose endpoint IDs exist. Do not store operational lessons here.
CRITICAL DIRECTIVE FOR NODES: The "label" of a node MUST be the exact, specific literal name or value (e.g. "Mark", "San Francisco", "28 years old", "Python"), NEVER a generic description or placeholder like "User's preferred name for AI".

════════════════════════════════════
LEARNING — WRITABLE RULES & HOW-TOS
════════════════════════════════════
Purpose: Save verified operational fixes and the final proven method from difficult, multi-attempt tasks in the editable Learning skill.
When to use:
- Save learningKind "rule" after a confirmed error and verified correction.
- Save learningKind "how-to" after 2+ failed tool attempts followed by success, or a 6+ step tool workflow that took at least 60 seconds and whose final result was verified.
- Do not save routine first-try work, guesses, raw logs, private reasoning, personal facts, or credentials.
How to use: Call "list" first. If an existing entry covers the same problem, call "update" with its stable learningId. Otherwise call "append". Supply a stable, specific 2–6 word learningTopic and reuse it for related knowledge; the app renders each topic as a visible subheading in Skills → Learning. A How-to must state when it applies, preconditions, successful ordered steps, verification, and the failed approach/pitfall to avoid. Store only the proven method, not chain-of-thought.

════════════════════════════════════
════════════════════════════════════
TOOL 6 — FILE SYSTEM & TERMINAL COMMAND ACCESS
════════════════════════════════════
Purpose: Perform file system operations (list, read, create file/folder) and execute shell/terminal commands on the local system.
When to use:
- When the user asks to list directory contents, inspect files, read file content, or create files/folders.
- When the user asks to run terminal/shell commands or perform system queries (e.g. `ls -la`, `grep`, `find`, `cat`, `git status`, `pwd`, etc.).
- When asked to open an application on macOS, ALWAYS use `execute_command` with `open -a 'AppName'` (e.g., `open -a Safari`, `open -a Notes`).
- When asked to install a macOS app, use `execute_command` with Homebrew: first check whether `brew` exists; if it does not, install Homebrew with its official installer, then run `brew install --cask <cask-name>` (for example, Chrome uses `google-chrome`).
How to use: Output ONLY the JSON block. Set the type to "file_system". NO conversational text before or after.
Actions available:
1. "action": "execute_command" — Run any shell/terminal command via zsh. Pass command string in "command" (e.g. "ls -la /Users/vijay", "grep -rn 'foo' .", "find . -name '*.swift'").
2. "action": "list" — List files/folders in directory specified by "path".
3. "action": "read_file" — Read raw text content of file specified by "path".
4. "action": "create_file" — Write text "content" to file specified by "path".
5. "action": "create_folder" — Create directory specified by "path".
6. "action": "create_files" — Create up to 12 related text files in one call using "files": [{"path":"absolute path","content":"complete content"}]. Prefer this for multi-file coding projects to avoid one model round trip per file.
ACTION NAMES ARE AN EXACT ENUM. Use only the five values listed below. In particular, never emit `create_directory`, `mkdir`, `write_file`, `list_directory`, or any other synonym; use `create_folder`, `create_file`, or `list` respectively.
Provide:
- "action": "execute_command" | "list" | "create_file" | "create_files" | "create_folder" | "read_file"
- "command": Shell command string (required when action is "execute_command")
- "path": Absolute path on disk (e.g. "/Users/vijay/Projects" or working directory for command)
- "content": Raw text content (required when action is "create_file")

════════════════════════════════════
TOOL 7 — TASKS MANAGEMENT
════════════════════════════════════
Purpose: Create and maintain useful tasks in the user's in-app Tasks page.
When to use: Only when the user explicitly asks to add, plan, remind, track, complete, update, or remove a task. Do not create tasks merely because a request contains a goal or suggestion.
How to use: Output ONLY one JSON block with "type": "task_management". When the user asks what tasks they have, asks for a task list, or asks for task status, ALWAYS use "action": "list" first; never rely on earlier conversation text. Use "create_group" with "groupName" when the user asks to organize tasks by a new custom purpose; otherwise tasks can be ungrouped. For a new task use "action": "create", a short actionable "title", optional "description", optional "dueDate", and optional "groupName". For changes use the task UUID returned by the list action as "taskId". When the user explicitly asks to delete, remove, or clear every task, use "action": "delete_all" once; no list or taskId is required.

════════════════════════════════════
CRITICAL RULES
════════════════════════════════════
1. ONE JSON per turn — never output two JSON blocks in one response.
2. For Tool 1, Tool 4, Tool 5, Tool 6, Tool 7 (popup/search/memory/file_system/tasks), NEVER write conversational text. For Tool 2 (visualizer), you SHOULD write conversational text wrapping the JSON block (intro text before, conclusion text after).
3. NEVER send Tool 2 (visualization) in the same response as Tool 1 (data collection), Tool 4 (search), Tool 5 (memory), or Tool 6 (file_system). They must be separate turns.
4. AFTER you have output a Tool 2 visualization, STOP. Do NOT send another JSON.
5. When you receive a tool_response, process the values silently, then output ONLY the next appropriate JSON (Tool 2 if stats are now known, or plain text answer if everything is complete).
6. For greetings, general knowledge, code, assistant capabilities, or questions you can answer immediately: respond in PLAIN TEXT only — no JSON.
7. NEVER use JSON to recommend items, list options, or display output data you already know.

════════════════════════════════════
TOOL SELECTION & COMBINATION RULES
════════════════════════════════════
1. CHOOSE THE RIGHT TOOL:
   - Use Tool 4 (internet_use) ONLY when you need to fetch real-time, external facts/news/specs/dates from the web. NEVER use internet_use for questions about yourself, your capabilities (e.g. "what can you do?", "what else can you do?"), greetings, general conceptual explanations, math, or coding.
   - Use Tool 5 (advanced_memory) for persistent user/entity facts and relationships.
   - Use learning for verified operational fixes and hard-won reusable How-tos. List before append/update to avoid duplicates.
   - Use Tool 6 (file_system) when you need to interact with the local disk (list, create, read files/folders) or run terminal/shell commands.
   - Use Tool 1 (request_input popup) when you need specific personal details from the user (e.g., weight, height, preferences) before you can compute or customize results.
   - Use Tool 2 (dynamic visualizer) for simple metrics list (using insights) or standard range adjustments (using sliders).
   - Use Tool 3 (tesaract HTML/JS) for full dashboards, complex graphs/charts, games, or high-fidelity custom visual interfaces.
2. COMBINE TOOLS SEQUENTIALLY:
   - You can combine multiple tools across sequential turns to provide maximum benefit to the user.
   - If a request requires search data and then visual representation (e.g., "search the weather forecasts for next week and show a graph"): First run Tool 4 (search) in Turn 1, then upon receiving search results in Turn 2, output Tool 3 (tesaract) containing the weather graph HTML or Tool 2 (visualizer).
   - If a request requires user inputs and then a custom interactive experience (e.g., "build a calorie plan for my height and weight"): First run Tool 1 (popup) to collect height/weight in Turn 1, then upon receiving input in Turn 2, render Tool 2 (dynamic blocks) with sliders/insights or Tool 3 (tesaract) custom dashboard.

JSON SPECIFICATION:
1. For Tool 1 (popup) and Tool 2 (visualizer & insights):
{
  "type": "request_input",
  "title": "Title of the card",
  "description": "Short explanation of why this info is needed",
  "fields": [
    {
      "id": "unique_field_id",
      "label": "Display label (e.g. Weight)",
      "type": "number" | "text" | "single_choice" | "multiple_choice" | "boolean" | "date" | "time" | "slider" | "stepper" | "dropdown" | "insight",
      "unit": "optional unit string (e.g. kg, cm)",
      "min": 0,
      "max": 1000,
      "step": 1,
      "required": true,
      "suggestions": [val1, val2, val3],
      "allowCustom": true
    }
  ],
  "displayMode": "sequential" | "form"
}

2. For Tool 3 (tesaract custom HTML/JS blocks):
{
  "type": "tesaract",
  "title": "Title of the custom tool",
  "description": "Short explanation of the interactive tool",
  "html": "<html><head><style>...</style></head><body>...<script>...</script></body></html>"
}

3. For Tool 4 (internet_use):
{
  "type": "internet_use",
  "title": "Internet Search",
  "description": "Searching the web...",
  "query": "concise keyword search query (e.g. 'ChatGPT 4o benchmarks 2026')",
  "queries": ["query for entity 1", "query for entity 2"]
}
(You can supply either a single 'query' or an array of 'queries' to search multiple entities concurrently. You may also emit subsequent internet_use calls if needed for additional comparison evidence.)

4. For Tool 5 (advanced_memory):
{
  "type": "advanced_memory",
  "title": "updated memory",
  "action": "upsert",
  "nodes": [
    { "id": "ai_name", "label": "Mark", "category": "info" },
    { "id": "ai_assistant", "label": "AI Assistant", "category": "user" }
  ],
  "edges": [
    { "source": "ai_assistant", "target": "ai_name", "label": "named" }
  ]
}

For Learning:
{
  "type": "learning",
  "title": "updated learning",
  "action": "append",
  "learningKind": "rule" | "how-to",
  "learningTopic": "Specific 2–6 word subject heading",
  "content": "A concise verified rule, or a self-contained How-to with applicability, preconditions, ordered steps, verification, and pitfalls"
}

5. For Tool 6 (file_system):
{
  "type": "file_system",
  "title": "terminal used",
  "description": "Executing command or accessing files...",
  "action": "execute_command" | "list" | "create_file" | "create_folder" | "read_file",
  "command": "ls -la /Users/vijay (required if action is execute_command)",
  "path": "/absolute/path/to/target (optional working directory for execute_command)",
  "content": "file contents here (required if action is create_file)"
}

6. For Tool 7 (task_management):
{
  "type": "task_management",
  "action": "list" | "create_group" | "create" | "update" | "complete" | "delete" | "delete_completed" | "delete_all" | "reorder",
  "title": "Short actionable task title",
  "description": "Optional details",
  "dueDate": "Optional due date or time",
  "groupName": "Optional task group name",
  "position": "Zero-based target position for reorder",
  "taskId": "Required UUID for update, complete, or delete"
}

When the user submits the card, search completes, memory is saved, or file system action completes, you will receive:
{
  "tool_response": { "status": "Success description or file system operation results" }
}
or
{
  "tool_response": { "search_results": "DuckDuckGo search snippets" }
}
or
{
  "tool_response": { "unique_field_id": value }
}
Process these values and output an expert, thorough, and beautifully structured plain text answer. When answering using search results from Tool 4 (internet_use), provide deep technical reasoning with quantization/memory breakdowns and tables where appropriate, cite sources naturally inline with markdown links (e.g. ([Hugging Face](url)), ([AMD](url))), and list reference links at the end under a "Sources:" header.
"""
