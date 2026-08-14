import Foundation
import SwiftUI
import Combine

// MARK: - MCP Config Models

public struct MCPServerConfig: Codable, Equatable, Hashable {
    public var command: String?
    public var args: [String]?
    public var env: [String: String]?
    public var url: String?
    public var disabled: Bool?

    public init(
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        url: String? = nil,
        disabled: Bool? = nil
    ) {
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.disabled = disabled
    }

    public var isEnabled: Bool {
        !(disabled ?? false)
    }
}

public struct MCPConfigFile: Codable, Equatable {
    public var mcpServers: [String: MCPServerConfig]

    public init(mcpServers: [String: MCPServerConfig] = [:]) {
        self.mcpServers = mcpServers
    }
}

// MARK: - MCP Tool Model

public struct MCPTool: Identifiable, Codable, Hashable {
    public var id: String { "\(serverName)::\(name)" }
    public let serverName: String
    public let name: String
    public let description: String
    public let inputSchemaRaw: [String: AgentValue]

    public init(serverName: String, name: String, description: String, inputSchemaRaw: [String: AgentValue] = [:]) {
        self.serverName = serverName
        self.name = name
        self.description = description
        self.inputSchemaRaw = inputSchemaRaw
    }

    public var qualifiedName: String {
        "mcp_\(serverName.replacingOccurrences(of: "-", with: "_"))_\(name.replacingOccurrences(of: "-", with: "_"))"
    }

    public var parameterNames: [String] {
        if case .object(let properties) = inputSchemaRaw["properties"] {
            return properties.keys.sorted()
        }
        return []
    }
}

// MARK: - Server Runtime State

public enum MCPServerStatus: Equatable, Hashable {
    case stopped
    case starting
    case connected(toolCount: Int)
    case error(String)

    public var displayText: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Connecting…"
        case .connected(let count): return "Connected (\(count) \(count == 1 ? "tool" : "tools"))"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    public var color: Color {
        switch self {
        case .stopped: return .secondary
        case .starting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    public var icon: String {
        switch self {
        case .stopped: return "circle"
        case .starting: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

public struct MCPServerRuntime: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public var config: MCPServerConfig
    public var status: MCPServerStatus
    public var tools: [MCPTool]

    public init(name: String, config: MCPServerConfig, status: MCPServerStatus = .stopped, tools: [MCPTool] = []) {
        self.name = name
        self.config = config
        self.status = status
        self.tools = tools
    }
}

// MARK: - Single Process MCP Client Actor (JSON-RPC 2.0 over Stdio)

private actor MCPProcessClient {
    let serverName: String
    let config: MCPServerConfig
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var nextRequestId = 1
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var buffer = Data()
    private var isRunning = false

    init(serverName: String, config: MCPServerConfig) {
        self.serverName = serverName
        self.config = config
    }

    func start() async throws -> [MCPTool] {
        if let urlStr = config.url, !urlStr.isEmpty {
            return try await startSSE(urlString: urlStr)
        }

        guard let command = config.command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "MCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "No command or URL specified for server '\(serverName)'."])
        }

        stop()

        let proc = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        // Resolve PATH for npx, uvx, node, python, etc.
        var env = ProcessInfo.processInfo.environment
        let userHome = FileManager.default.homeDirectoryForCurrentUser.path
        let customPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(userHome)/.cargo/bin",
            "\(userHome)/.local/bin"
        ]
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = (customPaths + [currentPath]).joined(separator: ":")

        if let customEnv = config.env {
            for (k, v) in customEnv {
                env[k] = v
            }
        }
        proc.environment = env

        // Run command via zsh login shell to ensure full environment, aliases, and paths work
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let commandWithArgs = ([command] + (config.args ?? [])).map { arg in
            if arg.contains(" ") || arg.contains("\"") {
                return "\"\(arg.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return arg
        }.joined(separator: " ")
        proc.arguments = ["-l", "-c", commandWithArgs]

        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        self.process = proc
        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe
        self.isRunning = true

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            Task {
                await self.handleIncomingData(chunk)
            }
        }

        try proc.run()

        // Handshake: initialize
        let initParams: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [:]
            ],
            "clientInfo": [
                "name": "appleint",
                "version": "1.0.0"
            ]
        ]
        let initResponse = try await sendRequest(method: "initialize", params: initParams)
        _ = initResponse

        // Send notifications/initialized
        sendNotification(method: "notifications/initialized", params: [:])

        // Query tools/list
        let toolsResponse = try await sendRequest(method: "tools/list", params: [:])
        let toolsList = parseToolsFromResponse(toolsResponse)
        return toolsList
    }

    func stop() {
        isRunning = false
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: NSError(domain: "MCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server stopped"]))
        }
        pendingRequests.removeAll()
        buffer.removeAll()
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let params: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]
        let response = try await sendRequest(method: "tools/call", params: params, timeoutSeconds: 60)
        return formatToolCallResponse(response)
    }

    private func sendRequest(method: String, params: [String: Any], timeoutSeconds: Double = 30) async throws -> [String: Any] {
        guard let inPipe = stdinPipe, let proc = process, proc.isRunning else {
            throw NSError(domain: "MCP", code: 2, userInfo: [NSLocalizedDescriptionKey: "MCP server '\(serverName)' is not running."])
        }

        let id = nextRequestId
        nextRequestId += 1

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MCP", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize JSON-RPC request."])
        }
        line += "\n"

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation

            if let writeData = line.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(writeData)
            }

            // Timeout timer
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                await self?.timeoutRequest(id: id, method: method, seconds: timeoutSeconds)
            }
        }
    }

    private func timeoutRequest(id: Int, method: String, seconds: Double) {
        if let cont = pendingRequests.removeValue(forKey: id) {
            cont.resume(throwing: NSError(domain: "MCP", code: 4, userInfo: [NSLocalizedDescriptionKey: "MCP request timed out after \(Int(seconds))s for method '\(method)'."]))
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        guard let inPipe = stdinPipe, let proc = process, proc.isRunning else { return }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let writeData = line.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(writeData)
        }
    }

    private func handleIncomingData(_ data: Data) {
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.subdata(in: 0..<newlineIndex)
            buffer.removeSubrange(0...newlineIndex)
            if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty {
                processIncomingLine(line)
            }
        }
    }

    private func processIncomingLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let id = json["id"] as? Int {
            let continuation = pendingRequests.removeValue(forKey: id)
            if let continuation {
                if let error = json["error"] as? [String: Any] {
                    let message = (error["message"] as? String) ?? "Unknown MCP error"
                    continuation.resume(throwing: NSError(domain: "MCP", code: (error["code"] as? Int) ?? -1, userInfo: [NSLocalizedDescriptionKey: message]))
                } else if let result = json["result"] as? [String: Any] {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: json)
                }
            }
        }
    }

    private func parseToolsFromResponse(_ response: [String: Any]) -> [MCPTool] {
        guard let toolsArray = response["tools"] as? [[String: Any]] else {
            return []
        }
        var results: [MCPTool] = []
        for item in toolsArray {
            let name = (item["name"] as? String) ?? ""
            guard !name.isEmpty else { continue }
            let desc = (item["description"] as? String) ?? ""
            var inputSchema: [String: AgentValue] = [:]
            if let schemaDict = item["inputSchema"] as? [String: Any] {
                inputSchema = convertDictToAgentValues(schemaDict)
            }
            results.append(MCPTool(serverName: serverName, name: name, description: desc, inputSchemaRaw: inputSchema))
        }
        return results
    }

    private func formatToolCallResponse(_ response: [String: Any]) -> String {
        if let isError = response["isError"] as? Bool, isError {
            let contentList = response["content"] as? [[String: Any]] ?? []
            let texts = contentList.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return "Error from MCP tool: \(texts.isEmpty ? "Action failed" : texts)"
        }

        if let contentList = response["content"] as? [[String: Any]] {
            var parts: [String] = []
            for item in contentList {
                if let text = item["text"] as? String {
                    parts.append(text)
                } else if let type = item["type"] as? String, type == "image", let dataStr = item["data"] as? String {
                    parts.append("[Image data: \(dataStr.prefix(30))…]")
                }
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n\n")
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "Tool executed successfully."
    }

    private func convertDictToAgentValues(_ dict: [String: Any]) -> [String: AgentValue] {
        var output: [String: AgentValue] = [:]
        for (k, v) in dict {
            output[k] = convertAnyToAgentValue(v)
        }
        return output
    }

    private func convertAnyToAgentValue(_ value: Any) -> AgentValue {
        if let s = value as? String { return .string(s) }
        if let n = value as? Double { return .number(n) }
        if let i = value as? Int { return .number(Double(i)) }
        if let b = value as? Bool { return .boolean(b) }
        if let arr = value as? [Any] { return .array(arr.map(convertAnyToAgentValue)) }
        if let d = value as? [String: Any] { return .object(convertDictToAgentValues(d)) }
        return .null
    }

    // SSE / HTTP endpoint fallback
    private func startSSE(urlString: String) async throws -> [MCPTool] {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "MCP", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlString)"])
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MCP", code: 6, userInfo: [NSLocalizedDescriptionKey: "SSE server returned status \((resp as? HTTPURLResponse)?.statusCode ?? 0)"])
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseToolsFromResponse(json)
        }
        return []
    }
}

// MARK: - MCPServerManager Observable Controller

@MainActor
public final class MCPServerManager: ObservableObject {
    public static let shared = MCPServerManager()

    @Published public var servers: [MCPServerRuntime] = []
    @Published public var allTools: [MCPTool] = []
    @Published public var rawConfigJSON: String = ""
    @Published public var configError: String? = nil
    @Published public var isReloading: Bool = false

    private var clients: [String: MCPProcessClient] = [:]

    public var configDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("appleint", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("mcp.json")
    }

    private init() {
        loadConfigAndStart()
    }

    // MARK: - Lifecycle

    public func loadConfigAndStart() {
        loadConfigFile()
        restartAllServers()
    }

    public func loadConfigFile() {
        let url = configFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let defaultContent = defaultMCPJSONContent()
            try? defaultContent.write(to: url, atomically: true, encoding: .utf8)
            rawConfigJSON = defaultContent
        } else if let content = try? String(contentsOf: url, encoding: .utf8) {
            rawConfigJSON = content
        } else {
            rawConfigJSON = defaultMCPJSONContent()
        }
        parseConfigFromRaw()
    }

    public func saveRawConfigJSON(_ jsonText: String) throws {
        // Validate JSON
        guard let data = jsonText.data(using: .utf8) else {
            throw NSError(domain: "MCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid text encoding."])
        }
        let decoder = JSONDecoder()
        let config = try decoder.decode(MCPConfigFile.self, from: data)

        // Save to disk
        try jsonText.write(to: configFileURL, atomically: true, encoding: .utf8)
        self.rawConfigJSON = jsonText
        self.configError = nil

        // Sync and reload servers
        applyConfig(config)
        restartAllServers()
    }

    public func restartAllServers() {
        isReloading = true
        Task {
            // Stop old clients
            for (_, client) in clients {
                await client.stop()
            }
            clients.removeAll()

            var updatedServers: [MCPServerRuntime] = []
            var updatedTools: [MCPTool] = []

            for server in self.servers {
                var current = server
                if !server.config.isEnabled {
                    current.status = .stopped
                    current.tools = []
                    updatedServers.append(current)
                    continue
                }

                current.status = .starting
                let client = MCPProcessClient(serverName: server.name, config: server.config)
                self.clients[server.name] = client

                do {
                    let tools = try await client.start()
                    current.status = .connected(toolCount: tools.count)
                    current.tools = tools
                    updatedTools.append(contentsOf: tools)
                } catch {
                    current.status = .error(error.localizedDescription)
                    current.tools = []
                }
                updatedServers.append(current)
            }

            self.servers = updatedServers
            self.allTools = updatedTools
            self.isReloading = false
        }
    }

    public func restartServer(named name: String) {
        guard let index = servers.firstIndex(where: { $0.name == name }) else { return }
        let config = servers[index].config
        if let existing = clients[name] {
            Task { await existing.stop() }
        }
        clients.removeValue(forKey: name)

        if !config.isEnabled {
            servers[index].status = .stopped
            servers[index].tools = []
            refreshAllToolsList()
            return
        }

        servers[index].status = .starting
        let client = MCPProcessClient(serverName: name, config: config)
        clients[name] = client

        Task {
            do {
                let tools = try await client.start()
                self.servers[index].status = .connected(toolCount: tools.count)
                self.servers[index].tools = tools
            } catch {
                self.servers[index].status = .error(error.localizedDescription)
                self.servers[index].tools = []
            }
            self.refreshAllToolsList()
        }
    }

    public func toggleServer(named name: String, isEnabled: Bool) {
        guard let data = rawConfigJSON.data(using: .utf8),
              var config = try? JSONDecoder().decode(MCPConfigFile.self, from: data),
              var srv = config.mcpServers[name] else { return }

        srv.disabled = !isEnabled
        config.mcpServers[name] = srv

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(config),
           let jsonStr = String(data: encoded, encoding: .utf8) {
            try? saveRawConfigJSON(jsonStr)
        }
    }

    public func callTool(serverName: String, toolName: String, arguments: [String: Any]) async throws -> String {
        guard let client = clients[serverName] else {
            throw NSError(domain: "MCP", code: 10, userInfo: [NSLocalizedDescriptionKey: "MCP server '\(serverName)' is not connected."])
        }
        return try await client.callTool(name: toolName, arguments: arguments)
    }

    // MARK: - Helpers

    private func parseConfigFromRaw() {
        guard let data = rawConfigJSON.data(using: .utf8) else {
            configError = "Could not read config encoding"
            return
        }
        do {
            let config = try JSONDecoder().decode(MCPConfigFile.self, from: data)
            configError = nil
            applyConfig(config)
        } catch {
            configError = error.localizedDescription
        }
    }

    private func applyConfig(_ config: MCPConfigFile) {
        var newServers: [MCPServerRuntime] = []
        for (name, srvConfig) in config.mcpServers.sorted(by: { $0.key < $1.key }) {
            let existing = servers.first(where: { $0.name == name })
            newServers.append(MCPServerRuntime(
                name: name,
                config: srvConfig,
                status: existing?.status ?? .stopped,
                tools: existing?.tools ?? []
            ))
        }
        self.servers = newServers
    }

    private func refreshAllToolsList() {
        var tools: [MCPTool] = []
        for srv in servers where srv.config.isEnabled {
            tools.append(contentsOf: srv.tools)
        }
        self.allTools = tools
    }

    public func formatJSONString(_ input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let formattedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let formattedString = String(data: formattedData, encoding: .utf8) else {
            return nil
        }
        return formattedString
    }

    public func addTemplate(name: String, config: MCPServerConfig) {
        guard let data = rawConfigJSON.data(using: .utf8) else { return }
        var configFile = (try? JSONDecoder().decode(MCPConfigFile.self, from: data)) ?? MCPConfigFile()
        configFile.mcpServers[name] = config
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(configFile),
           let jsonStr = String(data: encoded, encoding: .utf8) {
            try? saveRawConfigJSON(jsonStr)
        }
    }

    public func defaultMCPJSONContent() -> String {
        """
        {
          "mcpServers": {
            "fetch": {
              "command": "uvx",
              "args": [
                "mcp-server-fetch"
              ]
            }
          }
        }
        """
    }
}
