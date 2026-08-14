import Foundation

// Provider adapters translate their wire format into these types. Nothing above
// this boundary needs to know whether a model is served by LM Studio, Ollama, or
// another OpenAI-compatible runtime.
public typealias ToolArguments = [String: AgentValue]

public indirect enum AgentValue: Codable, Hashable {
    case string(String), number(Double), boolean(Bool), array([AgentValue]), object([String: AgentValue]), null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .boolean(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([AgentValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: AgentValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .boolean(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }
}

public struct AgentToolCall: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let arguments: ToolArguments
    public init(id: String = UUID().uuidString, name: String, arguments: ToolArguments = [:]) {
        self.id = id; self.name = name; self.arguments = arguments
    }
    public var signature: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "\(name):\(encoded)"
    }
}

public struct AgentToolError: Codable, Hashable, Error { public let code: String; public let message: String; public let retryable: Bool }
public struct AgentToolResult: Codable, Hashable {
    public let callID: String; public let toolName: String; public let success: Bool
    public let payload: ToolArguments?; public let error: AgentToolError?
    public init(callID: String, toolName: String, success: Bool, payload: ToolArguments? = nil, error: AgentToolError? = nil) {
        self.callID = callID; self.toolName = toolName; self.success = success; self.payload = payload; self.error = error
    }
}

public enum AgentEvent: Hashable { case text(String), reasoning(String), toolCall(AgentToolCall), completed, error(AgentToolError) }
public struct ModelRequest: Sendable {
    public let messages: [String]
    public let systemInstruction: String
    public let tools: [AgentToolDefinition]
    public init(messages: [String], systemInstruction: String, tools: [AgentToolDefinition]) { self.messages = messages; self.systemInstruction = systemInstruction; self.tools = tools }
}
public enum ModelProviderEvent: Sendable { case text(String), reasoning(String), toolCall(AgentToolCall), completed, error(AgentToolError) }
public protocol ModelProvider: Sendable {
    var id: String { get }
    func generate(request: ModelRequest) async throws -> AsyncStream<ModelProviderEvent>
}
public enum AgentRunState: String, Codable { case idle, planning, generating, awaitingApproval, executingTool, awaitingUser, rendering, searching, verifying, completed, failed, cancelled }
public enum UltraTaskStatus: String, Codable, Hashable { case pending, inProgress, completed, blocked }
public struct UltraTaskItem: Codable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var status: UltraTaskStatus
    public init(id: String = UUID().uuidString, title: String, status: UltraTaskStatus = .pending) {
        self.id = id; self.title = title; self.status = status
    }
}
public struct UltraTaskRun: Codable, Hashable {
    public let goal: String
    public var items: [UltraTaskItem]
    public var isFinished: Bool
    public init(goal: String, items: [UltraTaskItem]) {
        self.goal = goal; self.items = items; self.isFinished = false
    }
}
public enum ToolRisk: String, Codable { case readOnly, reversible, destructive, external }
public struct AgentPlan: Codable, Hashable { public let goal: String; public let successCriteria: String; public let createdAt: Date; public init(goal: String, successCriteria: String) { self.goal = goal; self.successCriteria = successCriteria; self.createdAt = Date() } }
public struct AgentLimits: Codable { public var maxSteps = 16; public var maxSameToolRetries = 2; public var maxConsecutiveFailures = 3; public var maxContinuationNudges = 1; public var maxToolOutputCharacters = 12_000; public var maxToolOutputLines = 300 }
public struct ToolExecution: Codable, Hashable { public let call: AgentToolCall; public let result: AgentToolResult; public let date: Date }
public struct AgentRun: Codable, Identifiable {
    public let id: UUID; public let userGoal: String; public var state: AgentRunState; public var stepCount: Int
    public var completedToolCalls: [ToolExecution]; public var failedToolCalls: [ToolExecution]; public var pendingToolCall: AgentToolCall?
    public var repeatedCallCount: Int; public var consecutiveFailureCount: Int; public var continuationNudges: Int; public let startedAt: Date; public var plan: AgentPlan?
    public init(userGoal: String) { id = UUID(); self.userGoal = userGoal; state = .planning; stepCount = 0; completedToolCalls = []; failedToolCalls = []; pendingToolCall = nil; repeatedCallCount = 0; consecutiveFailureCount = 0; continuationNudges = 0; startedAt = Date(); plan = .init(goal: userGoal, successCriteria: "Provide a verified result or a specific recoverable failure.") }
}

public struct AgentToolDefinition: Codable, Hashable { public let name: String; public let description: String; public let isEnabled: Bool }
public protocol AgentTool { var definition: AgentToolDefinition { get }; func validate(_ call: AgentToolCall) throws }
public struct RegisteredAgentTool: AgentTool {
    public let definition: AgentToolDefinition
    public let requiredArguments: Set<String>
    public init(name: String, description: String, isEnabled: Bool, requiredArguments: Set<String> = []) { self.definition = .init(name: name, description: description, isEnabled: isEnabled); self.requiredArguments = requiredArguments }
    public func validate(_ call: AgentToolCall) throws {
        let missing = requiredArguments.filter { key in
            guard let value = call.arguments[key] else { return true }
            if case .string(let text) = value {
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }
        if !missing.isEmpty { throw AgentToolError(code: "INVALID_ARGUMENTS", message: "Missing required arguments: \(missing.sorted().joined(separator: ", ")).", retryable: true) }
    }
}
public final class ToolRegistry {
    private var tools: [String: any AgentTool] = [:]
    public init() {}
    public func register(_ tool: any AgentTool) { tools[tool.definition.name] = tool }
    public func tool(named name: String) -> (any AgentTool)? { tools[name] }
    public func availableDefinitions() -> [AgentToolDefinition] { tools.values.map(\.definition).filter(\.isEnabled).sorted { $0.name < $1.name } }
}

// Main-actor isolation gives the UI and a run one serialized transition path.
@MainActor public final class AgentController {
    public private(set) var activeRun: AgentRun?
    private var signatures: [String: Int] = [:]
    public var limits = AgentLimits()
    public init() {}
    public func begin(goal: String) { activeRun = AgentRun(userGoal: goal); signatures = [:] }
    public func beginExecution() { activeRun?.state = .generating }
    public func prepare(_ call: AgentToolCall) -> AgentToolError? {
        guard var run = activeRun, ![.cancelled, .completed, .failed].contains(run.state) else { return AgentToolError(code: "RUN_NOT_ACTIVE", message: "The agent run is no longer active.", retryable: false) }
        guard run.stepCount < limits.maxSteps else { run.state = .failed; activeRun = run; return AgentToolError(code: "STEP_LIMIT", message: "The agent reached its configured step limit.", retryable: false) }
        let count = (signatures[call.signature] ?? 0) + 1; signatures[call.signature] = count
        guard count <= limits.maxSameToolRetries else { run.repeatedCallCount += 1; activeRun = run; return AgentToolError(code: "DUPLICATE_TOOL_CALL", message: "This exact call already ran without a meaningful state change.", retryable: false) }
        run.stepCount += 1; run.pendingToolCall = call; run.state = .executingTool; activeRun = run; return nil
    }
    public func record(_ result: AgentToolResult, awaitingUser: Bool = false) {
        guard var run = activeRun, let call = run.pendingToolCall else { return }
        let execution = ToolExecution(call: call, result: result, date: Date())
        if result.success {
            run.completedToolCalls.append(execution)
            run.consecutiveFailureCount = 0
            // Recovery nudges guard consecutive model stalls. A successful
            // action is meaningful progress, so the next step gets a fresh
            // single recovery opportunity.
            run.continuationNudges = 0
        } else {
            run.failedToolCalls.append(execution)
            run.consecutiveFailureCount += 1
        }
        run.pendingToolCall = awaitingUser ? call : nil; run.state = awaitingUser ? .awaitingUser : (result.success ? .generating : .verifying)
        if run.consecutiveFailureCount >= limits.maxConsecutiveFailures { run.state = .failed }
        activeRun = run
    }
    public func requestContinuationNudge() -> Bool {
        guard var run = activeRun, run.state != .awaitingUser, run.state != .cancelled, run.continuationNudges < limits.maxContinuationNudges else { return false }
        run.continuationNudges += 1; activeRun = run; return true
    }
    public func cancel() { activeRun?.state = .cancelled }
    public func complete() { activeRun?.state = .completed }
    public func fail() { activeRun?.state = .failed }
}
