import Foundation
import Observation

@Observable
public final class ChatManager {
    public let agentController = AgentController()
    private var agentControllers: [UUID: AgentController] = [:]
    public private(set) var ultraTaskRuns: [UUID: UltraTaskRun] = [:]
    private let toolRegistry = ToolRegistry()
    private var activeGenerationTasks: [UUID: Task<Void, Never>] = [:]
    /// Distinct model-requested searches made for the current user turn.
    /// Reset for every new message so research can broaden without looping.
    private var searchQueriesByThread: [UUID: [String]] = [:]
    /// Threads whose current user turn explicitly selected the composer Web
    /// toggle. The flag survives tool-response generations, then resets when
    /// the next visible user message starts.
    private var mandatoryWebSearchThreadIds: Set<UUID> = []
    /// Identifies the current stream for each thread, avoiding stale cleanup.
    private var activeGenerationIDs: [UUID: UUID] = [:]
    private let preferences: UserDefaults
    private let networkSession: URLSession
    private let fileManager: FileManager
    private let credentialStore: any CredentialStoring
    private let modelDiscovery: ModelDiscoveryService
    private let threadRepository: any ThreadPersisting
    private let diagnostics: DiagnosticsStore
    private let learningStore: AgentLearningStore
    private let attachmentStore: any AttachmentStoring
    private let providerHealthService: ProviderHealthService

    /// Compatibility surface for the UI. The value is derived from the selected
    /// thread's task, rather than a mutable global flag shared by every chat.
    public var isGenerating: Bool {
        guard let threadId = activeThreadId else { return false }
        return activeGenerationTasks[threadId] != nil
    }

    private func refreshGenerationState() {
        // `isGenerating` is derived from activeGenerationTasks.
    }

    private func controller(for threadId: UUID) -> AgentController {
        if let controller = agentControllers[threadId] { return controller }
        let controller = AgentController(); agentControllers[threadId] = controller; return controller
    }
    public func ultraTaskRun(for threadId: UUID) -> UltraTaskRun? { ultraTaskRuns[threadId] }

    private func beginUltraRun(goal: String, threadId: UUID) {
        guard Self.requestIntent(for: goal).shouldTrackProgress else {
            ultraTaskRuns[threadId] = nil
            return
        }
        ultraTaskRuns[threadId] = UltraTaskRun(goal: goal, items: [
            UltraTaskItem(title: "Plan the requested work", status: .inProgress),
            UltraTaskItem(title: "Verify and present the complete result")
        ])
    }

    private func ultraToolTitle(_ call: AgentToolCall) -> String {
        let readableName: String
        switch call.name {
        case "internet_search": readableName = "Research current sources"
        case "file_system": readableName = "Run terminal or file action"
        case "learning": readableName = "Save verified learning"
        case "apple_notes": readableName = "Apple Notes"
        default: readableName = call.name.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if case .string(let action)? = call.arguments["action"], !action.isEmpty {
            return "\(readableName): \(action.replacingOccurrences(of: "_", with: " "))"
        }
        return readableName
    }

    private func beginUltraToolTask(_ call: AgentToolCall, threadId: UUID) {
        // Track task progress only when genuinely multi-agent / multi-action workflows execute
        if ultraTaskRuns[threadId] == nil,
           let agentRun = controller(for: threadId).activeRun,
           agentRun.completedToolCalls.count >= 1 {
            let completedActions = agentRun.completedToolCalls.map { execution in
                UltraTaskItem(
                    id: execution.call.id,
                    title: ultraToolTitle(execution.call),
                    status: .completed
                )
            }
            ultraTaskRuns[threadId] = UltraTaskRun(goal: agentRun.userGoal, items: completedActions + [
                UltraTaskItem(id: call.id, title: ultraToolTitle(call), status: .inProgress)
            ])
            return
        }
        guard var run = ultraTaskRuns[threadId] else { return }
        if let index = run.items.firstIndex(where: { $0.title == "Plan the requested work" }) {
            run.items[index].status = .completed
        }
        if !run.items.contains(where: { $0.id == call.id }) {
            run.items.insert(
                UltraTaskItem(id: call.id, title: ultraToolTitle(call), status: .inProgress),
                at: max(0, run.items.count)
            )
        }
        ultraTaskRuns[threadId] = run
    }

    private func finishUltraToolTask(callID: String, success: Bool, retryable: Bool, threadId: UUID) {
        guard var run = ultraTaskRuns[threadId],
              let index = run.items.firstIndex(where: { $0.id == callID }) else { return }
        run.items[index].status = success ? .completed : (retryable ? .pending : .blocked)
        ultraTaskRuns[threadId] = run
    }

    @discardableResult
    private func finishUltraRun(threadId: UUID, hasVisibleAnswer: Bool) -> Bool {
        guard var run = ultraTaskRuns[threadId] else { return true }
        if let index = run.items.firstIndex(where: { $0.title == "Plan the requested work" }),
           run.items[index].status == .inProgress { run.items[index].status = .completed }
        let actionsSucceeded = run.items.filter {
            $0.title != "Plan the requested work" && $0.title != "Verify and present the complete result"
        }.allSatisfy { $0.status == .completed }
        if hasVisibleAnswer, actionsSucceeded,
           let index = run.items.firstIndex(where: { $0.title == "Verify and present the complete result" }) {
            run.items[index].status = .completed
        }
        run.isFinished = run.items.allSatisfy { $0.status == .completed }
        ultraTaskRuns[threadId] = run
        return run.isFinished
    }
    // Current active thread ID
    public var activeThreadId: UUID?
    
    // List of threads
    public var threads: [ChatThread] = []
    
    // Status state
    public var isGeneratingMemory: Bool = false
    public var errorMessage: String?
    public var providerHealth: [String: ProviderHealth] = [:]
    public var toolRequestManager: ToolRequestManager
    
    // Live Terminal Log
    public var terminalLogs: [TerminalLogEntry] = []
    public var tasks: [UserTask] = [] {
        didSet { saveTasks() }
    }
    /// Changes whenever editable model context changes. Views that display the
    /// context-token estimate observe this value, so a Skill toggle is
    /// reflected immediately rather than after the next chat message.
    public private(set) var contextRevision: Int = 0
    public var customSkills: [CustomSkill] = [] {
        didSet {
            saveCustomSkills()
            contextRevision &+= 1
        }
    }
    public var taskGroups: [String] = [] { didSet { preferences.set(taskGroups, forKey: "AppleIntTaskGroups") } }
    public var terminalCurrentDirectory: String
    public var isTerminalCommandRunning: Bool = false
    public var activeTerminalCommand: String? = nil
    public var activeTerminalStatusText: String = "Accessing File System & Running Command…"
    private var fileReadCache: [String: (modifiedAt: Date, content: String)] = [:]
    
    public static func terminalCommandStatusText(for command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.contains("npm i") || trimmed.contains("npm install") || trimmed.contains("npx ") {
            return "Installing npm dependencies in terminal…"
        } else if trimmed.contains("brew install") || trimmed.contains("brew reinstall") || trimmed.contains("brew cask") {
            return "Installing packages via Homebrew…"
        } else if trimmed.contains("pip install") || trimmed.contains("pip3 install") {
            return "Installing Python packages with pip…"
        } else if trimmed.contains("yarn add") || trimmed.contains("yarn install") {
            return "Installing Yarn packages in terminal…"
        } else if trimmed.contains("cargo install") || trimmed.contains("cargo build") {
            return "Building & installing with Cargo…"
        } else if trimmed.contains("gem install") {
            return "Installing Ruby gems in terminal…"
        } else if trimmed.contains("pod install") || trimmed.contains("pod update") {
            return "Installing CocoaPods dependencies…"
        } else if trimmed.contains("git clone") {
            return "Cloning git repository in terminal…"
        } else if trimmed.contains("curl ") || trimmed.contains("wget ") {
            return "Downloading files in terminal…"
        } else {
            return "Running terminal command: \(command.prefix(40))…"
        }
    }
    
    nonisolated public static func cleanTerminalOutput(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        
        var text = raw
        // Strip standard ANSI CSI / OSC sequences (colors, cursor positions, erase line/display)
        let ansiPattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])|\x9B[0-?]*[ -/]*[@-~]"#
        text = text.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        
        // Strip stray unescaped cursor movement / clear line codes (e.g. [1G[J, [2K, [?25h, [?25l)
        let strayAnsiPattern = #"\[\d+[A-Za-z]|\[\?[0-9]+[a-zA-Z]|\[[0-9;]*[JjKkGgHh]"#
        text = text.replacingOccurrences(of: strayAnsiPattern, with: "", options: .regularExpression)
        
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        
        // Process carriage returns (\r): overwrites the current line in place (emulating terminal buffer)
        var cleanLines: [String] = []
        let rawLines = text.components(separatedBy: "\n")
        for line in rawLines {
            if line.contains("\r") {
                let segments = line.components(separatedBy: "\r").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if let lastSegment = segments.last {
                    cleanLines.append(lastSegment)
                }
            } else {
                cleanLines.append(line)
            }
        }
        
        // Deduplicate repetitive progress / spinner lines in terminal output
        var deduplicatedLines: [String] = []
        for line in cleanLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if deduplicatedLines.last?.trimmingCharacters(in: .whitespaces).isEmpty != true {
                    deduplicatedLines.append(line)
                }
                continue
            }
            
            if let last = deduplicatedLines.last {
                let lastTrimmed = last.trimmingCharacters(in: .whitespaces)
                let strippedCurrent = trimmed.replacingOccurrences(of: #"\.+$"#, with: "", options: .regularExpression)
                let strippedLast = lastTrimmed.replacingOccurrences(of: #"\.+$"#, with: "", options: .regularExpression)
                if strippedCurrent == strippedLast && strippedCurrent.count > 5 {
                    deduplicatedLines[deduplicatedLines.count - 1] = line
                    continue
                }
            }
            deduplicatedLines.append(line)
        }
        
        return deduplicatedLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
    
    public struct TerminalLogEntry: Identifiable {
        public let id: UUID
        public let timestamp: Date
        public let command: String
        public let directory: String
        public var output: String
        public var exitCode: Int32
        public var isError: Bool
        public let action: String // "execute_command", "list", "create_file", etc.

        public init(id: UUID = UUID(), timestamp: Date = Date(), command: String, directory: String, output: String, exitCode: Int32, isError: Bool, action: String) {
            self.id = id
            self.timestamp = timestamp
            self.command = command
            self.directory = directory
            self.output = output
            self.exitCode = exitCode
            self.isError = isError
            self.action = action
        }
    }

    private var terminalAuditURL: URL {
        appPaths.terminalAudit
    }
    
    public func appendTerminalLog(_ entry: TerminalLogEntry) {
        terminalLogs.append(entry)
        // Keep last 200 entries
        if terminalLogs.count > 200 {
            terminalLogs.removeFirst(terminalLogs.count - 200)
        }
        saveTerminalAudit(entry: entry)
    }

    public func startLiveTerminalLog(command: String, directory: String, action: String = "execute_command") -> UUID {
        let entry = TerminalLogEntry(
            id: UUID(),
            timestamp: Date(),
            command: command,
            directory: directory,
            output: "Executing command...",
            exitCode: 0,
            isError: false,
            action: action
        )
        terminalLogs.append(entry)
        if terminalLogs.count > 200 {
            terminalLogs.removeFirst(terminalLogs.count - 200)
        }
        return entry.id
    }

    public func updateLiveTerminalLog(id: UUID, chunk: String) {
        guard let index = terminalLogs.firstIndex(where: { $0.id == id }) else { return }
        var currentOutput = terminalLogs[index].output
        if currentOutput == "Executing command..." {
            currentOutput = chunk
        } else {
            currentOutput += chunk
        }
        let cleaned = Self.cleanTerminalOutput(currentOutput)
        // Keep output bounded to prevent unbounded memory growth while streaming large outputs
        if cleaned.count > 40_000 {
            terminalLogs[index].output = String(cleaned.suffix(40_000))
        } else {
            terminalLogs[index].output = cleaned
        }
    }

    public func finalizeLiveTerminalLog(id: UUID, finalOutput: String, exitCode: Int32, finalDirectory: String) {
        guard let index = terminalLogs.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = Self.cleanTerminalOutput(finalOutput)
        terminalLogs[index].output = cleaned.isEmpty ? "(No output)" : cleaned
        terminalLogs[index].exitCode = exitCode
        terminalLogs[index].isError = exitCode != 0
        saveTerminalAudit(entry: terminalLogs[index])
    }

    private func saveTerminalAudit(entry: TerminalLogEntry) {
        let formatter = ISO8601DateFormatter()
        let record: [String: Any] = [
            "timestamp": formatter.string(from: entry.timestamp),
            "command": entry.command,
            "directory": entry.directory,
            "exitCode": entry.exitCode,
            "isError": entry.isError,
            "action": entry.action
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              let handle = try? FileHandle(forWritingTo: terminalAuditURL) else {
            if let data = try? JSONSerialization.data(withJSONObject: record) {
                try? (data + Data("\n".utf8)).write(to: terminalAuditURL, options: .atomic)
            }
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
    }
    
    public func clearTerminalLogs() {
        terminalLogs.removeAll()
    }

    public func addTask(title: String, details: String = "", dueDate: String? = nil, groupName: String? = nil) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        if let groupName, !groupName.isEmpty, !taskGroups.contains(groupName) { taskGroups.append(groupName) }
        tasks.insert(UserTask(title: cleanTitle, details: details, dueDate: dueDate, groupName: groupName), at: 0)
    }

    public func updateTask(_ task: UserTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }
    public func moveTasks(from: IndexSet, to: Int) {
        let moved = from.sorted().map { tasks[$0] }
        for index in from.sorted(by: >) { tasks.remove(at: index) }
        let insertionIndex = min(max(0, to - from.filter { $0 < to }.count), tasks.count)
        tasks.insert(contentsOf: moved, at: insertionIndex)
    }
    public func moveTask(id: UUID, by offset: Int) {
        guard let from = tasks.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(0, from + offset), tasks.count - 1)
        guard from != to else { return }
        let task = tasks.remove(at: from)
        tasks.insert(task, at: to)
    }

    public func deleteTask(id: UUID) { tasks.removeAll { $0.id == id } }

    public func deleteMessage(threadId: UUID, messageId: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[index].messages.removeAll { $0.id == messageId }
        saveThreads()
    }

    @MainActor
    public func retryResponse(threadId: UUID, messageId: UUID) async {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadId }),
              let responseIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == messageId }),
              threads[threadIndex].messages[responseIndex].role == .assistant,
              let promptIndex = threads[threadIndex].messages[..<responseIndex].lastIndex(where: Self.isVisibleUserPrompt)
        else { return }

        await resubmitUserMessage(threadId: threadId, messageIndex: promptIndex, replacementText: nil)
    }

    public func branchConversation(threadId: UUID, through messageId: UUID) {
        guard let sourceThread = threads.first(where: { $0.id == threadId }),
              let responseIndex = sourceThread.messages.firstIndex(where: { $0.id == messageId }),
              sourceThread.messages[responseIndex].role == .assistant
        else { return }

        let branchedTitle = sourceThread.title == "New Chat"
            ? "Branched Chat"
            : "\(sourceThread.title) — Branch"
        let branchedThread = ChatThread(
            title: branchedTitle,
            provider: sourceThread.provider,
            systemInstructions: sourceThread.systemInstructions,
            temperature: sourceThread.temperature,
            lmStudioModelId: sourceThread.lmStudioModelId,
            geminiModelId: sourceThread.geminiModelId,
            openRouterModelId: sourceThread.openRouterModelId,
            openAIModelId: sourceThread.openAIModelId,
            isToolUseEnabled: sourceThread.isToolUseEnabled,
            showSystemMessages: sourceThread.showSystemMessages,
            messages: Array(sourceThread.messages.prefix(through: responseIndex)),
            chatMemory: sourceThread.chatMemory,
            memoryNodes: sourceThread.memoryNodes,
            memoryEdges: sourceThread.memoryEdges,
            isolatesContext: sourceThread.isolatesContext
        )
        threads.insert(branchedThread, at: 0)
        activeThreadId = branchedThread.id
        saveThreads()
    }

    @MainActor
    public func editAndResubmitUserMessage(
        threadId: UUID,
        messageId: UUID,
        text: String,
        attachedImageBase64: String?,
        attachedFiles: [AttachedFile]? = nil,
        forceWebSearch: Bool = false
    ) async {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty || attachedImageBase64 != nil || (attachedFiles != nil && !attachedFiles!.isEmpty),
              let threadIndex = threads.firstIndex(where: { $0.id == threadId }),
              let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == messageId }),
              Self.isVisibleUserPrompt(threads[threadIndex].messages[messageIndex])
        else { return }

        await resubmitUserMessage(
            threadId: threadId,
            messageIndex: messageIndex,
            replacementText: cleanText,
            replacementImage: attachedImageBase64,
            replacesImage: true,
            replacementFiles: attachedFiles,
            replacesFiles: true,
            forceWebSearch: forceWebSearch
        )
    }

    private static func isVisibleUserPrompt(_ message: ChatMessage) -> Bool {
        message.role == .user &&
            !message.isToolResponse &&
            !message.text.hasPrefix("[System:") &&
            !message.text.hasPrefix("[SYSTEM:") &&
            !message.text.contains("tool_response")
    }

    @MainActor
    private func resubmitUserMessage(
        threadId: UUID,
        messageIndex: Int,
        replacementText: String?,
        replacementImage: String? = nil,
        replacesImage: Bool = false,
        replacementFiles: [AttachedFile]? = nil,
        replacesFiles: Bool = false,
        forceWebSearch: Bool = false
    ) async {
        guard !isGenerating,
              let threadIndex = threads.firstIndex(where: { $0.id == threadId }),
              threads[threadIndex].messages.indices.contains(messageIndex)
        else { return }

        let original = threads[threadIndex].messages[messageIndex]
        let promptText = replacementText ?? original.text
        let image = replacesImage ? replacementImage : original.attachedImageBase64
        let files = replacesFiles ? replacementFiles : original.attachedFiles
        threads[threadIndex].messages.removeSubrange(messageIndex...)
        activeThreadId = threadId
        saveThreads()
        await sendMessage(
            text: promptText,
            attachedImageBase64: image,
            attachedFiles: files,
            forceWebSearch: forceWebSearch
        )
    }

    public func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            preferences.set(data, forKey: "AppleIntUserTasks")
        }
    }

    private func loadTasks() {
        guard let data = preferences.data(forKey: "AppleIntUserTasks"),
              let saved = try? JSONDecoder().decode([UserTask].self, from: data) else { return }
        tasks = saved
        taskGroups = preferences.stringArray(forKey: "AppleIntTaskGroups") ?? Array(Set(saved.compactMap(\.groupName))).sorted()
    }

    /// Runs a user-entered command using the same zsh login shell used by Terminal.
    /// Each invocation carries the resulting working directory forward, so `cd` works
    /// naturally across commands in the in-app terminal.
    @MainActor
    public func runTerminalCommand(_ command: String) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isTerminalCommandRunning else { return }

        let workingDirectory = terminalCurrentDirectory
        isTerminalCommandRunning = true
        activeTerminalCommand = command
        activeTerminalStatusText = Self.terminalCommandStatusText(for: command)
        let liveLogId = startLiveTerminalLog(command: command, directory: workingDirectory, action: "interactive_command")

        Task { [weak self] in
            let result = await Task.detached {
                Self.executeTerminalCommand(command, in: workingDirectory) { chunk in
                    Task { @MainActor [weak self] in
                        self?.updateLiveTerminalLog(id: liveLogId, chunk: chunk)
                    }
                }
            }.value
            guard let self else { return }
            self.terminalCurrentDirectory = result.directory
            self.finalizeLiveTerminalLog(id: liveLogId, finalOutput: result.output, exitCode: result.exitCode, finalDirectory: result.directory)
            self.isTerminalCommandRunning = false
            self.activeTerminalCommand = nil
            self.activeTerminalStatusText = "Accessing File System & Running Command…"

            if result.exitCode != 0 {
                await self.repairFailedTerminalCommand(
                    command,
                    output: result.output,
                    directory: result.directory,
                    attempt: 1
                )
            }
        }
    }

    /// Asks the currently selected chat model for a replacement command after a
    /// terminal failure. Repairs are deliberately capped to prevent retry loops.
    @MainActor
    private func repairFailedTerminalCommand(
        _ failedCommand: String,
        output: String,
        directory: String,
        attempt: Int
    ) async {
        guard attempt <= 3, let thread = activeThread else { return }
        let prompt = """
        A zsh command run by the user failed. Return exactly one corrected zsh command that fixes the error and continues the user's apparent intent. Do not use Markdown, explanations, labels, or code fences. Do not use destructive commands unless the original command explicitly requested them.

        Working directory: \(directory)
        Failed command: \(failedCommand)
        Exit output:
        \(output)
        """

        guard let modelResponse = await fetchAutomaticTitle(prompt: prompt, for: thread, maxTokens: 240),
              let correctedCommand = Self.extractTerminalCommand(from: modelResponse),
              correctedCommand != failedCommand else {
            appendTerminalLog(TerminalLogEntry(
                timestamp: Date(), command: failedCommand, directory: directory,
                output: "Automatic repair could not produce a safe corrected command.",
                exitCode: 1, isError: true, action: "ai_repair"
            ))
            return
        }

        switch CommandPolicy.evaluate(correctedCommand) {
        case .allow:
            break
        case .requiresConfirmation(let reason), .block(let reason):
            appendTerminalLog(TerminalLogEntry(
                timestamp: Date(), command: correctedCommand, directory: directory,
                output: "Automatic repair was not run. \(reason)",
                exitCode: 1, isError: true, action: "ai_repair"
            ))
            return
        }

        let result = await Task.detached {
            Self.executeTerminalCommand(correctedCommand, in: directory)
        }.value
        terminalCurrentDirectory = result.directory
        appendTerminalLog(TerminalLogEntry(
            timestamp: Date(), command: correctedCommand, directory: directory,
            output: "AI repair attempt \(attempt):\n\(result.output)",
            exitCode: result.exitCode, isError: result.exitCode != 0, action: "ai_repair"
        ))

        if result.exitCode != 0 {
            await repairFailedTerminalCommand(
                correctedCommand,
                output: result.output,
                directory: result.directory,
                attempt: attempt + 1
            )
        }
    }

    nonisolated private static func extractTerminalCommand(from modelResponse: String) -> String? {
        var value = modelResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value
                .replacingOccurrences(of: #"^```(?:zsh|bash|sh|shell)?\\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\\s*```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let marker = value.range(of: "FIXED_COMMAND:", options: [.caseInsensitive]) {
            value = String(value[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty,
              !value.contains("\n\n"),
              !value.lowercased().hasPrefix("i can't") else { return nil }
        return value
    }

    nonisolated private static func executeTerminalCommand(
        _ command: String,
        in directory: String,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) -> (output: String, exitCode: Int32, directory: String) {
        let escapedDirectory = directory.replacingOccurrences(of: "'", with: "'\\\"'\\\"'")
        let directoryMarker = "__APPLEINT_TERMINAL_DIRECTORY__"
        let shellCommand = "cd -- '\(escapedDirectory)' 2>&1 || exit $?; \(command); command_status=$?; printf '\\n\(directoryMarker)%s\\n' \"$PWD\"; exit $command_status"

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", shellCommand]
        process.standardOutput = pipe
        process.standardError = pipe

        var env = ProcessInfo.processInfo.environment
        env["NSUnbufferedIO"] = "YES"
        env["PYTHONUNBUFFERED"] = "1"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["NONINTERACTIVE"] = "1"
        env["CI"] = "1"
        env["TERM"] = "dumb"
        process.environment = env

        let outputLock = NSLock()
        var accumulatedData = Data()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            accumulatedData.append(chunk)
            outputLock.unlock()
            if let str = String(data: chunk, encoding: .utf8), !str.isEmpty {
                onOutput?(str)
            }
        }

        do {
            try process.run()
            let startTime = Date()
            
            // Loop until process exits, times out, or a background server ready state is detected
            while process.isRunning {
                Thread.sleep(forTimeInterval: 0.25)
                
                outputLock.lock()
                let currentText = String(data: accumulatedData, encoding: .utf8) ?? ""
                outputLock.unlock()
                
                let lower = currentText.lowercased()
                let containsServerURL = lower.contains("http://localhost:") ||
                                        lower.contains("http://127.0.0.1:") ||
                                        lower.contains("http://0.0.0.0:") ||
                                        lower.contains("local:   http") ||
                                        lower.contains("local: http")
                let hasReadyIndicator = lower.contains("ready in ") ||
                                        lower.contains("listening on") ||
                                        lower.contains("compiled successfully") ||
                                        lower.contains("server running at") ||
                                        lower.contains("started server on") ||
                                        lower.contains("press h + enter to show help") ||
                                        lower.contains("use --host to expose")
                
                // If a local server URL is printed and the server has initialized, allow it to remain running in the background and return immediately so the AI can provide the localhost link
                if containsServerURL && (hasReadyIndicator || Date().timeIntervalSince(startTime) >= 3.0) {
                    Thread.sleep(forTimeInterval: 0.4) // Let any trailing banner lines arrive
                    break
                }
                
                if Date().timeIntervalSince(startTime) > 600 {
                    process.terminate()
                    break
                }
            }

            pipe.fileHandleForReading.readabilityHandler = nil
            outputLock.lock()
            let remaining = pipe.fileHandleForReading.availableData
            if !remaining.isEmpty {
                accumulatedData.append(remaining)
            }
            let totalData = accumulatedData
            outputLock.unlock()

            let rawOutput = String(data: totalData, encoding: .utf8) ?? ""
            let markerRange = rawOutput.range(of: directoryMarker, options: .backwards)
            let finalDirectory: String
            let output: String

            if let markerRange {
                let afterMarker = rawOutput[markerRange.upperBound...]
                finalDirectory = afterMarker.trimmingCharacters(in: .whitespacesAndNewlines)
                output = String(rawOutput[..<markerRange.lowerBound]).trimmingCharacters(in: .newlines)
            } else {
                finalDirectory = directory
                output = rawOutput.trimmingCharacters(in: .newlines)
            }

            let status = process.isRunning ? 0 : process.terminationStatus
            return (output.isEmpty ? "(No output)" : output, status, finalDirectory)
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return ("Error starting zsh: \(error.localizedDescription)", 1, directory)
        }
    }
    
    // Gemini configurations
    public var geminiAPIKey: String {
        didSet {
            credentialStore.set(geminiAPIKey, for: "GeminiAPIKey")
        }
    }
    public var geminiModelId: String {
        didSet {
            preferences.set(geminiModelId, forKey: "GeminiModelID")
        }
    }
    
    // OpenRouter configurations
    public var openRouterAPIKey: String {
        didSet {
            credentialStore.set(openRouterAPIKey, for: "OpenRouterAPIKey")
        }
    }
    public var openRouterModelId: String {
        didSet {
            preferences.set(openRouterModelId, forKey: "OpenRouterModelID")
        }
    }
    
    // OpenAI configurations
    public var openAIAPIKey: String {
        didSet {
            credentialStore.set(openAIAPIKey, for: "OpenAIAPIKey")
        }
    }
    public var openAIBaseURL: String {
        didSet {
            preferences.set(openAIBaseURL, forKey: "OpenAIBaseURL")
        }
    }
    public var openAIModelId: String {
        didSet {
            preferences.set(openAIModelId, forKey: "OpenAIModelID")
        }
    }
    
    // LM Studio configurations
    public var lmStudioBaseURL: String {
        didSet {
            preferences.set(lmStudioBaseURL, forKey: "LMStudioBaseURL")
        }
    }
    public var lmStudioAvailableModels: [String] = []
    public var lmStudioModelContextLengths: [String: Int] = [:]
    public var autoSwitchLMStudioModel: Bool {
        didSet {
            preferences.set(autoSwitchLMStudioModel, forKey: "AutoSwitchLMStudioModel")
        }
    }
    
    // Apple MLX configurations
    public var mlxBaseURL: String {
        didSet {
            preferences.set(mlxBaseURL, forKey: "MLXBaseURL")
        }
    }
    public var mlxModelId: String? {
        didSet {
            preferences.set(mlxModelId, forKey: "MLXModelID")
        }
    }
    public let mlxScanner = MLXModelScanner()
    
    // Model selection persistence and custom presets
    public var geminiModels: [String] = [] {
        didSet {
            preferences.set(geminiModels, forKey: "GeminiModelsList")
        }
    }
    public var openRouterModels: [String] = [] {
        didSet {
            preferences.set(openRouterModels, forKey: "OpenRouterModelsList")
        }
    }
    public var openRouterFreeMap: [String: Bool] = [:] {
        didSet {
            if let encoded = try? JSONEncoder().encode(openRouterFreeMap) {
                preferences.set(encoded, forKey: "OpenRouterFreeMap")
            }
        }
    }
    
    public func isOpenRouterModelFree(_ modelId: String) -> Bool {
        if modelId.hasSuffix(":free") { return true }
        if let isFree = openRouterFreeMap[modelId] {
            return isFree
        }
        return false
    }
    public var openAIModels: [String] = [] {
        didSet {
            preferences.set(openAIModels, forKey: "OpenAIModelsList")
        }
    }
    public var lmStudioModelId: String? {
        didSet {
            preferences.set(lmStudioModelId, forKey: "LMStudioModelID")
        }
    }
    public var customPresets: [ChatPersona] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPresets) {
                preferences.set(encoded, forKey: "CustomSystemInstructionPresets")
            }
        }
    }

    private static let currentSystemInstructionsKey = "CurrentSystemInstructions"
    private static let currentSystemTemperatureKey = "CurrentSystemInstructionTemperature"
    
    private let appPaths: AppPaths
    private let saveURL: URL
    private let globalMemoryURL: URL
    
    public var globalMemoryNodes: [MemoryNode] = []
    public var globalMemoryEdges: [MemoryEdge] = []
    public var disabledPrePromptIds: Set<String> = []

    public func isPrePromptEnabled(_ id: String) -> Bool {
        return !disabledPrePromptIds.contains(id)
    }
    
    public func togglePrePrompt(_ id: String) {
        if disabledPrePromptIds.contains(id) {
            disabledPrePromptIds.remove(id)
        } else {
            disabledPrePromptIds.insert(id)
        }
        saveDisabledPrePrompts()
    }
    
    public func setAllPrePromptsEnabled(_ enabled: Bool) {
        if enabled {
            disabledPrePromptIds.removeAll()
        } else {
            disabledPrePromptIds = Set([
                "system_instructions", "persona_obedience",
                "thinking_mode", "cross_check", "mandatory_search",
                "tool_schemas", "thread_memory", "knowledge_graph", "time_context"
            ])
        }
        saveDisabledPrePrompts()
    }

    private func saveDisabledPrePrompts() {
        preferences.set(Array(disabledPrePromptIds), forKey: "DisabledPrePromptIds")
    }


    
    public convenience init() {
        self.init(dependencies: .live())
    }

    init(dependencies: AppDependencies) {
        self.preferences = dependencies.preferences
        self.networkSession = dependencies.networkSession
        self.fileManager = dependencies.fileManager
        self.credentialStore = dependencies.credentials
        self.modelDiscovery = dependencies.modelDiscovery
        self.threadRepository = dependencies.threadRepository
        self.diagnostics = dependencies.diagnostics
        self.learningStore = dependencies.learningStore
        self.attachmentStore = dependencies.attachmentStore
        self.providerHealthService = dependencies.providerHealth
        self.toolRequestManager = dependencies.toolRequestManager
        self.terminalCurrentDirectory = dependencies.fileManager.homeDirectoryForCurrentUser.path
        self.appPaths = dependencies.paths
        self.saveURL = dependencies.paths.threads
        self.globalMemoryURL = dependencies.paths.globalMemory

        // Load Gemini configurations
        self.geminiAPIKey = credentialStore.migrateLegacyDefaults("GeminiAPIKey", account: "GeminiAPIKey")
        self.geminiModelId = preferences.string(forKey: "GeminiModelID") ?? "gemini-2.5-flash"
        
        // Load OpenRouter configurations
        self.openRouterAPIKey = credentialStore.migrateLegacyDefaults("OpenRouterAPIKey", account: "OpenRouterAPIKey")
        self.openRouterModelId = preferences.string(forKey: "OpenRouterModelID") ?? "google/gemini-2.0-flash-001"
        
        // Load OpenAI configurations
        self.openAIAPIKey = credentialStore.migrateLegacyDefaults("OpenAIAPIKey", account: "OpenAIAPIKey")
        self.openAIBaseURL = preferences.string(forKey: "OpenAIBaseURL") ?? "https://api.openai.com/v1"
        self.openAIModelId = preferences.string(forKey: "OpenAIModelID") ?? "gpt-4o"
        
        // Load LM Studio base URL
        self.lmStudioBaseURL = preferences.string(forKey: "LMStudioBaseURL") ?? "http://localhost:1234/v1"
        
        // Load Apple MLX configurations
        self.mlxBaseURL = preferences.string(forKey: "MLXBaseURL") ?? "http://localhost:8080/v1"
        self.mlxModelId = preferences.string(forKey: "MLXModelID")
        
        // Load model lists and presets
        if let savedGemini = preferences.stringArray(forKey: "GeminiModelsList") {
            self.geminiModels = savedGemini
        } else {
            self.geminiModels = ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-1.5-flash", "gemini-1.5-pro"]
        }
        
        if let savedOpenAI = preferences.stringArray(forKey: "OpenAIModelsList") {
            self.openAIModels = savedOpenAI
        } else {
            self.openAIModels = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1", "o1-mini", "o3-mini"]
        }
        
        if let data = preferences.data(forKey: "OpenRouterFreeMap"),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            self.openRouterFreeMap = decoded
        }
        
        if let savedOpenRouter = preferences.stringArray(forKey: "OpenRouterModelsList") {
            self.openRouterModels = savedOpenRouter
        } else {
            self.openRouterModels = [
                "google/gemini-2.0-flash-exp:free",
                "meta-llama/llama-3.3-70b-instruct:free",
                "deepseek/deepseek-r1:free",
                "qwen/qwen-2.5-72b-instruct:free",
                "mistralai/mistral-7b-instruct:free",
                "google/gemini-2.0-flash-001",
                "openai/gpt-4o",
                "openai/gpt-4o-mini",
                "anthropic/claude-3.5-sonnet"
            ]
        }
        
        self.lmStudioModelId = preferences.string(forKey: "LMStudioModelID")
        if preferences.object(forKey: "AutoSwitchLMStudioModel") == nil {
            self.autoSwitchLMStudioModel = true
        } else {
            self.autoSwitchLMStudioModel = preferences.bool(forKey: "AutoSwitchLMStudioModel")
        }
        
        if let data = preferences.data(forKey: "CustomSystemInstructionPresets"),
           let decoded = try? JSONDecoder().decode([ChatPersona].self, from: data) {
            self.customPresets = decoded
        } else {
            self.customPresets = []
        }
        
        if let savedDisabled = preferences.stringArray(forKey: "DisabledPrePromptIds") {
            self.disabledPrePromptIds = Set(savedDisabled)
        }

        var loadedCustomSkills: [CustomSkill] = []
        if let data = preferences.data(forKey: "AppleIntCustomSkills"),
           let decoded = try? JSONDecoder().decode([CustomSkill].self, from: data) {
            loadedCustomSkills = decoded.filter { !StarterSkillCatalog.retiredSkillIDs.contains($0.id) }
        }

        // Generic starter workflows were retired because they duplicated normal
        // assistant behavior. Keep the migration flag for existing installs,
        // but do not install or route those records on fresh installations.
        if !preferences.bool(forKey: StarterSkillCatalog.installationKey) {
            preferences.set(true, forKey: StarterSkillCatalog.installationKey)
        }
        // Install editable representations of every built-in tool contract and
        // model directive. This migration runs once, preserves all existing
        // user skills, and does not recreate an exposed skill after the user
        // intentionally deletes it.
        // Built-in infrastructure skills cannot be deleted in the UI, so also
        // repair any missing records. This covers installations where an older
        // migration flag was persisted before the initialized array itself.
        let exposedExistingIDs = Set(loadedCustomSkills.map(\.id))
        loadedCustomSkills.append(contentsOf: StarterSkillCatalog.exposedSkills.filter { !exposedExistingIDs.contains($0.id) })
        // Remove obsolete routing clauses from older search contracts now that
        // web search is the app's only online retrieval capability.
        if let index = loadedCustomSkills.firstIndex(where: { $0.id == StarterSkillCatalog.internetSearchID }),
           (loadedCustomSkills[index].instructions.contains("browser_use") ||
            loadedCustomSkills[index].instructions.localizedCaseInsensitiveContains("built-in browser")),
           let current = StarterSkillCatalog.defaultInstructions(for: StarterSkillCatalog.internetSearchID) {
            loadedCustomSkills[index].name = "Internet Search"
            loadedCustomSkills[index].summary = "Source-first web retrieval for substantive answers, with current multi-source evidence and citations. Edit this to customize how the AI uses search."
            loadedCustomSkills[index].instructions = current
        }
        if let index = loadedCustomSkills.firstIndex(where: { $0.id == StarterSkillCatalog.learningID }),
           let current = StarterSkillCatalog.defaultInstructions(for: StarterSkillCatalog.learningID) {
            let installedInstructions = loadedCustomSkills[index].instructions
            let installedBase = installedInstructions.components(separatedBy: StarterSkillCatalog.learningRulesMarker).first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let previousBases = [
                StarterSkillCatalog.previousLearningInstructions,
                StarterSkillCatalog.previousTopiclessLearningInstructions,
                StarterSkillCatalog.previousDomainlessLearningInstructions
            ].compactMap {
                $0.components(separatedBy: StarterSkillCatalog.learningRulesMarker).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if installedInstructions == StarterSkillCatalog.legacyLearningInstructions || previousBases.contains(installedBase ?? "") {
                let savedRules = installedInstructions.range(of: StarterSkillCatalog.learningRulesMarker)
                    .map { String(installedInstructions[$0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let currentBase = current.components(separatedBy: StarterSkillCatalog.learningRulesMarker).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? current
                loadedCustomSkills[index].name = "Learning"
                loadedCustomSkills[index].summary = "Writable reusable prevention rules and topic-organized How-tos learned from difficult completed work."
                loadedCustomSkills[index].instructions = savedRules.isEmpty
                    ? "\(currentBase)\n\n\(StarterSkillCatalog.learningRulesMarker)"
                    : "\(currentBase)\n\n\(StarterSkillCatalog.learningRulesMarker)\n\(savedRules)"
            }
        }
        if let index = loadedCustomSkills.firstIndex(where: { $0.id == StarterSkillCatalog.advancedMemoryID }),
           loadedCustomSkills[index].instructions == StarterSkillCatalog.legacyAdvancedMemoryInstructions,
           let current = StarterSkillCatalog.defaultInstructions(for: StarterSkillCatalog.advancedMemoryID) {
            loadedCustomSkills[index].summary = "Capability for updating the persistent user/entity knowledge graph."
            loadedCustomSkills[index].instructions = current
        }
        if let index = loadedCustomSkills.firstIndex(where: { $0.id == StarterSkillCatalog.dynamicInsightsID }),
           loadedCustomSkills[index].instructions.hasPrefix("request_input(") {
            loadedCustomSkills[index].instructions = "dynamic_insights(title,description,fields:[{id,label,type:\"insight\",placeholder}]); use only to present useful calculated results or alerts as a native insight block"
        }
        preferences.set(true, forKey: StarterSkillCatalog.exposedInstallationKey)
        let installedLibraryIDs = Set(preferences.stringArray(forKey: "InstalledLibraryTools") ?? [])
        let existingSkillIDs = Set(loadedCustomSkills.map(\.id))
        for definition in ChatManager.allLibraryApiDefs where installedLibraryIDs.contains(definition.id) {
            guard let skillID = StarterSkillCatalog.librarySkillID(for: definition.id),
                  !existingSkillIDs.contains(skillID) else { continue }
            loadedCustomSkills.append(CustomSkill(
                id: skillID,
                name: definition.name,
                summary: definition.description,
                instructions: definition.promptDirective
            ))
        }
        self.customSkills = loadedCustomSkills
        // Property observers do not run for assignments made during init.
        // Persist migrations explicitly so exposed skills survive relaunches.
        if let migratedSkills = try? JSONEncoder().encode(loadedCustomSkills) {
            preferences.set(migratedSkills, forKey: "AppleIntCustomSkills")
        }

        // Move only actual legacy library credentials into the private credential store.
        for definition in ChatManager.allLibraryApiDefs {
            let legacyKey = "api_key_\(definition.id)"
            if let legacy = preferences.string(forKey: legacyKey),
               !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = credentialStore.migrateLegacyDefaults(legacyKey, account: "library.\(definition.id)")
            }
        }

        
        // Load data
        loadThreads()
        migrateLegacyGeneralAssistantPrompt()
        if preferences.object(forKey: Self.currentSystemInstructionsKey) == nil,
           let mostRecentThread = threads.first {
            preferences.set(mostRecentThread.systemInstructions, forKey: Self.currentSystemInstructionsKey)
            preferences.set(mostRecentThread.temperature, forKey: Self.currentSystemTemperatureKey)
        }
        loadGlobalMemory()
        migrateLegacyLearningNodes()
        loadTasks()
        configureToolRegistry()
        
        // If there's at least one thread, activate the first one
        if let firstThread = threads.first {
            activeThreadId = firstThread.id
        }
        
        // Hook up ToolRequestManager callbacks
        self.toolRequestManager.onSubmitResponse = { [weak self] jsonResponse, naturalLanguagePrompt in
            guard let self = self else { return }
            let threadId = self.toolRequestManager.activeRequestThreadId
            Task {
                await self.sendToolResponse(text: jsonResponse, threadId: threadId)
            }
        }
        self.toolRequestManager.onCancel = { [weak self] in
            guard let self = self else { return }
            if let threadId = self.toolRequestManager.activeRequestThreadId {
                self.stopGeneration(threadId: threadId)
            } else {
                self.refreshGenerationState()
            }
            self.errorMessage = nil
        }
        
        // Fetch LM Studio models asynchronously at startup
        Task {
            await fetchLMStudioModels()
        }
        Task { await refreshProviderHealth() }
    }
    
    public var activeThread: ChatThread? {
        get {
            threads.first { $0.id == activeThreadId }
        }
        set {
            if let newValue = newValue, let index = threads.firstIndex(where: { $0.id == newValue.id }) {
                threads[index] = newValue
                saveThreads()
            }
        }
    }

    /// Upgrade only the exact former built-in General Assistant prompt. Any
    /// user-edited or custom prompt remains untouched and continues to persist
    /// across chats and launches.
    private func migrateLegacyGeneralAssistantPrompt() {
        let legacy = ChatPersona.legacyGeneralAssistantInstructions
        let current = ChatPersona.generalAssistantInstructions
        var changedThread = false
        for index in threads.indices where threads[index].systemInstructions == legacy {
            threads[index].systemInstructions = current
            changedThread = true
        }
        if preferences.string(forKey: Self.currentSystemInstructionsKey) == legacy {
            preferences.set(current, forKey: Self.currentSystemInstructionsKey)
        }
        if changedThread { saveThreads() }
    }
    
    public func upsertCustomSkill(_ skill: CustomSkill) {
        if let index = customSkills.firstIndex(where: { $0.id == skill.id }) {
            customSkills[index] = skill
        } else {
            customSkills.insert(skill, at: 0)
        }
        configureToolRegistry()
    }

    public func deleteCustomSkill(id: UUID) {
        customSkills.removeAll { $0.id == id }
        configureToolRegistry()
    }

    private func saveCustomSkills() {
        guard let data = try? JSONEncoder().encode(customSkills) else { return }
        preferences.set(data, forKey: "AppleIntCustomSkills")
    }

    public func isExposedSkillEnabled(_ id: UUID) -> Bool {
        customSkills.first(where: { $0.id == id })?.isEnabled == true
    }

    public func setCustomSkillEnabled(_ id: UUID, isEnabled: Bool) {
        guard let index = customSkills.firstIndex(where: { $0.id == id }) else { return }
        customSkills[index].isEnabled = isEnabled
        configureToolRegistry()
    }

    private func exposedSkillInstructions(_ id: UUID) -> String {
        guard let skill = customSkills.first(where: { $0.id == id }), skill.isEnabled else { return "" }
        return skill.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func setLibrarySkill(apiID: String, name: String, summary: String, instructions: String, installed: Bool) {
        guard let id = StarterSkillCatalog.librarySkillID(for: apiID) else { return }
        if let index = customSkills.firstIndex(where: { $0.id == id }) {
            customSkills[index].isEnabled = installed
        } else if installed {
            customSkills.append(CustomSkill(id: id, name: name, summary: summary, instructions: instructions))
        }
    }

    public var installedLibraryAPIIDs: Set<String> {
        Set(preferences.stringArray(forKey: "InstalledLibraryTools") ?? [])
    }

    public func setLibraryAPIInstalled(_ installed: Bool, apiID: String) {
        var ids = installedLibraryAPIIDs
        if installed { ids.insert(apiID) } else { ids.remove(apiID) }
        preferences.set(ids.sorted(), forKey: "InstalledLibraryTools")
        contextRevision &+= 1
    }

    /// Explicit maintenance action for installations that stored library keys
    /// before non-secret configured-status metadata existed.
    public func reconcileLibraryCredentialStatus() {
        credentialStore.reconcileConfigurationStatus(for: ChatManager.allLibraryApiDefs.map { "library.\($0.id)" })
    }

    public func isLibraryCredentialConfigured(apiID: String) -> Bool {
        credentialStore.isConfigured("library.\(apiID)")
    }

    public func loadLibraryCredential(apiID: String) -> String {
        credentialStore.migrateLegacyDefaults("api_key_\(apiID)", account: "library.\(apiID)")
    }

    public func saveLibraryCredential(_ value: String, apiID: String) {
        credentialStore.set(value, for: "library.\(apiID)")
    }

    public func health(for provider: Provider) -> ProviderHealth {
        providerHealth[provider.rawValue] ?? .checking
    }

    public func present(_ error: AppError) {
        errorMessage = error.localizedDescription
    }

    public func refreshProviderHealth() async {
        providerHealth[Provider.gemini.rawValue] = geminiAPIKey.isEmpty ? .unconfigured : .ready
        providerHealth[Provider.openRouter.rawValue] = openRouterAPIKey.isEmpty ? .unconfigured : .ready
        providerHealth[Provider.openAI.rawValue] = openAIAPIKey.isEmpty ? .unconfigured : .ready
        providerHealth[Provider.lmStudio.rawValue] = .checking
        providerHealth[Provider.lmStudio.rawValue] = await providerHealthService.lmStudioHealth(baseURL: lmStudioBaseURL)
        providerHealth[Provider.mlx.rawValue] = .checking
        providerHealth[Provider.mlx.rawValue] = await providerHealthService.mlxHealth(baseURL: mlxBaseURL)
    }
    
    // Create new chat
    public func createNewChat(persona: ChatPersona, provider: Provider = .gemini) {
        preferences.set(persona.instructions, forKey: Self.currentSystemInstructionsKey)
        preferences.set(persona.temperature, forKey: Self.currentSystemTemperatureKey)
        let newThread = ChatThread(
            title: "New Chat (\(persona.name))",
            provider: provider,
            systemInstructions: persona.instructions,
            temperature: persona.temperature,
            lmStudioModelId: lmStudioModelId ?? lmStudioAvailableModels.first,
            mlxModelId: mlxModelId ?? mlxScanner.models.first?.id,
            geminiModelId: geminiModelId,
            openRouterModelId: openRouterModelId,
            openAIModelId: openAIModelId,
            isolatesContext: true
        )
        threads.insert(newThread, at: 0)
        activeThreadId = newThread.id
        saveThreads()
    }
    
    // Create a new chat with the last explicitly selected system settings.
    public func createNewChatWithDefaults() {
        let provider: Provider = {
            if let activeId = activeThreadId,
               let activeThread = threads.first(where: { $0.id == activeId }) {
                return activeThread.provider
            }
            return .gemini
        }()
        
        let isDevSaved = preferences.bool(forKey: "globalDeveloperMode")
        let persona = ChatPersona.presets[0]
        let activeThread = activeThreadId.flatMap { activeId in
            threads.first(where: { $0.id == activeId })
        }
        let currentInstructions = preferences.string(forKey: Self.currentSystemInstructionsKey)
            ?? activeThread?.systemInstructions
            ?? persona.instructions
        let currentTemperature = (preferences.object(forKey: Self.currentSystemTemperatureKey) as? NSNumber)?.doubleValue
            ?? activeThread?.temperature
            ?? persona.temperature
        let newThread = ChatThread(
            title: "New Chat",
            provider: provider,
            systemInstructions: currentInstructions,
            temperature: currentTemperature,
            lmStudioModelId: lmStudioModelId ?? lmStudioAvailableModels.first,
            geminiModelId: geminiModelId,
            openRouterModelId: openRouterModelId,
            showSystemMessages: isDevSaved,
            isolatesContext: true
        )
        threads.insert(newThread, at: 0)
        activeThreadId = newThread.id
        saveThreads()
    }
    
    // Delete chat
    public func deleteChat(id: UUID) {
        cleanupRuntime(for: id)
        threads.removeAll { $0.id == id }
        if activeThreadId == id {
            activeThreadId = threads.first?.id
        }
        saveThreads()
    }
    
    // Update thread title
    public func updateTitle(id: UUID, title: String) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].title = title
            saveThreads()
        }
    }

    /// Creates a concise, model-generated title once a conversation has enough context.
    @MainActor
    private func generateAutomaticTitle(for thread: ChatThread, userMessages: [String]) {
        guard !titleGenerationThreadIds.contains(thread.id) else { return }
        titleGenerationThreadIds.insert(thread.id)

        let prompt = "Create a short, specific chat title (2–6 words) for this conversation. Return only the title, without quotes or punctuation.\n\n" + userMessages.enumerated().map { "User \($0.offset + 1): \($0.element)" }.joined(separator: "\n")

        Task { [weak self] in
            guard let self else { return }
            defer { self.titleGenerationThreadIds.remove(thread.id) }
            guard let title = await self.fetchAutomaticTitle(prompt: prompt, for: thread) else { return }
            let cleanTitle = title
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !cleanTitle.isEmpty, cleanTitle.count <= 60 else { return }
            self.updateTitle(id: thread.id, title: cleanTitle)
        }
    }

    private func fetchAutomaticTitle(prompt: String, for thread: ChatThread, maxTokens: Int = 20) async -> String? {
        do {
            if thread.provider == .gemini {
                guard !geminiAPIKey.isEmpty,
                      let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(thread.geminiModelId ?? geminiModelId):generateContent?key=\(geminiAPIKey)") else { return nil }
                let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]], "generationConfig": ["temperature": 0.2, "maxOutputTokens": maxTokens]]
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await networkSession.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let title = parts.first?["text"] as? String else { return nil }
                return title
            }

            let baseURL: String
            let model: String
            let apiKey: String
            switch thread.provider {
            case .openRouter:
                baseURL = "https://openrouter.ai/api/v1"
                model = thread.openRouterModelId ?? openRouterModelId
                apiKey = openRouterAPIKey
            case .openAI:
                baseURL = openAIBaseURL
                model = thread.openAIModelId ?? openAIModelId
                apiKey = openAIAPIKey
            case .lmStudio:
                baseURL = lmStudioBaseURL
                model = thread.lmStudioModelId ?? lmStudioModelId ?? "default"
                apiKey = ""
            case .mlx:
                baseURL = mlxBaseURL
                model = thread.mlxModelId ?? mlxModelId ?? mlxScanner.models.first?.id ?? "default"
                apiKey = ""
            case .gemini:
                return nil
            }
            guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": [["role": "user", "content": prompt]], "temperature": 0.2, "max_tokens": maxTokens])
            let (data, response) = try await networkSession.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let title = message["content"] as? String else { return nil }
            return title
        } catch {
            return nil
        }
    }
    
    // Update provider
    public func updateProvider(id: UUID, provider: Provider) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].provider = provider
            saveThreads()
        }
    }
    
    // Update LM Studio model selection
    public func updateLMStudioModel(id: UUID, modelId: String?) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].lmStudioModelId = modelId
            saveThreads()
        }
        if let modelId = modelId {
            self.lmStudioModelId = modelId
        }
    }
    
    // Update Apple MLX model selection
    public func updateMLXModel(id: UUID, modelId: String?) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].mlxModelId = modelId
            saveThreads()
        }
        if let modelId = modelId {
            self.mlxModelId = modelId
        }
    }
    
    // Update Gemini model selection
    public func updateGeminiModel(id: UUID, modelId: String?) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].geminiModelId = modelId
            saveThreads()
        }
        if let modelId = modelId {
            self.geminiModelId = modelId
        }
    }
    
    // Update OpenRouter model selection
    public func updateOpenRouterModel(id: UUID, modelId: String?) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].openRouterModelId = modelId
            saveThreads()
        }
        if let modelId = modelId {
            self.openRouterModelId = modelId
        }
    }
    
    // Update OpenAI model selection
    public func updateOpenAIModel(id: UUID, modelId: String?) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].openAIModelId = modelId
            saveThreads()
        }
        if let modelId = modelId {
            self.openAIModelId = modelId
        }
    }
    
    // Remove Gemini Model
    public func removeGeminiModel(_ model: String) {
        geminiModels.removeAll { $0 == model }
        if geminiModelId == model {
            geminiModelId = geminiModels.first ?? "gemini-2.5-flash"
        }
        for i in 0..<threads.count {
            if threads[i].geminiModelId == model {
                threads[i].geminiModelId = geminiModels.first ?? "gemini-2.5-flash"
            }
        }
        saveThreads()
    }
    
    // Remove OpenRouter Model
    public func removeOpenRouterModel(_ model: String) {
        openRouterModels.removeAll { $0 == model }
        if openRouterModelId == model {
            openRouterModelId = openRouterModels.first ?? "google/gemini-2.0-flash-001"
        }
        for i in 0..<threads.count {
            if threads[i].openRouterModelId == model {
                threads[i].openRouterModelId = openRouterModels.first ?? "google/gemini-2.0-flash-001"
            }
        }
        saveThreads()
    }
    
    // Remove OpenAI Model
    public func removeOpenAIModel(_ model: String) {
        openAIModels.removeAll { $0 == model }
        if openAIModelId == model {
            openAIModelId = openAIModels.first ?? "gpt-4o"
        }
        for i in 0..<threads.count {
            if threads[i].openAIModelId == model {
                threads[i].openAIModelId = openAIModels.first ?? "gpt-4o"
            }
        }
        saveThreads()
    }
    
    // Remove LM Studio Model
    public func removeLMStudioModel(_ model: String) {
        lmStudioAvailableModels.removeAll { $0 == model }
        if lmStudioModelId == model {
            lmStudioModelId = lmStudioAvailableModels.first
        }
        for i in 0..<threads.count {
            if threads[i].lmStudioModelId == model {
                threads[i].lmStudioModelId = lmStudioAvailableModels.first
            }
        }
        saveThreads()
    }
    
    // Add Custom Model to Gemini
    public func addCustomGeminiModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !geminiModels.contains(trimmed) else { return }
        geminiModels.append(trimmed)
    }
    
    // Add Custom Model to OpenRouter
    public func addCustomOpenRouterModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !openRouterModels.contains(trimmed) else { return }
        openRouterModels.append(trimmed)
    }
    
    // Add Custom Model to OpenAI
    public func addCustomOpenAIModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !openAIModels.contains(trimmed) else { return }
        openAIModels.append(trimmed)
    }
    
    // Add Custom Model to LM Studio
    public func addCustomLMStudioModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !lmStudioAvailableModels.contains(trimmed) else { return }
        lmStudioAvailableModels.append(trimmed)
    }
    
    // Delete multiple threads
    public func deleteChats(ids: Set<UUID>) {
        for id in ids { cleanupRuntime(for: id) }
        threads.removeAll { ids.contains($0.id) }
        if let activeId = activeThreadId, ids.contains(activeId) {
            activeThreadId = threads.first?.id
        }
        saveThreads()
    }

    private func cleanupRuntime(for threadId: UUID) {
        activeGenerationTasks[threadId]?.cancel()
        activeGenerationTasks[threadId] = nil
        activeGenerationIDs[threadId] = nil
        agentControllers[threadId]?.cancel()
        agentControllers[threadId] = nil
        searchQueriesByThread[threadId] = nil
        mandatoryWebSearchThreadIds.remove(threadId)
        titleGenerationThreadIds.remove(threadId)
        toolNudgedThreadIds.remove(threadId)
        constraintCorrectionThreadIds.remove(threadId)
        truncationContinuationThreadIds.remove(threadId)
        finalAnswerRecoveryThreadIds.remove(threadId)
        pendingHowToThreadIds.remove(threadId)
        if toolRequestManager.activeRequestThreadId == threadId {
            toolRequestManager.clearActiveRequest()
        }
        toolRequestManager.finishProcessing(threadId: threadId)
    }
    
    // Update Tool Use Enabled setting
    public func updateToolUseEnabled(id: UUID, isEnabled: Bool) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].isToolUseEnabled = isEnabled
            saveThreads()
        }
    }
    
    // Update Show System Messages setting
    public func updateShowSystemMessages(id: UUID, show: Bool) {
        preferences.set(show, forKey: "globalDeveloperMode")
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].showSystemMessages = show
        }
        saveThreads()
    }
    
    // Update persona/instructions
    public func updateSettings(id: UUID, instructions: String, temperature: Double) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].systemInstructions = instructions
            threads[index].temperature = min(max(temperature, 0), 1)
            preferences.set(instructions, forKey: Self.currentSystemInstructionsKey)
            preferences.set(threads[index].temperature, forKey: Self.currentSystemTemperatureKey)
            saveThreads()
        }
    }
    
    // Clear chat history
    @MainActor
    public func clearHistory(id: UUID) {
        clearThreadMessages(threadId: id)
    }
    
    // Helper to parse context length integer from LM Studio JSON dictionary
    private func parseLMStudioContextLength(from item: [String: Any]) -> Int? {
        let keys = [
            "loaded_context_length",
            "context_length",
            "max_context_length",
            "context_window",
            "native_context_length",
            "max_tokens",
            "n_ctx"
        ]
        for key in keys {
            if let val = item[key] {
                if let intVal = val as? Int, intVal > 0 { return intVal }
                if let doubleVal = val as? Double, doubleVal > 0 { return Int(doubleVal) }
                if let strVal = val as? String, let parsed = Int(strVal), parsed > 0 { return parsed }
            }
        }
        let subDictKeys = ["info", "config", "parameters", "params"]
        for subKey in subDictKeys {
            if let subDict = item[subKey] as? [String: Any] {
                if let len = parseLMStudioContextLength(from: subDict) {
                    return len
                }
            }
        }
        return nil
    }
    
    // Fetch available models and context lengths from LM Studio Server
    @MainActor
    public func fetchLMStudioModels() async {
        guard let snapshot = await modelDiscovery.discover(baseURL: lmStudioBaseURL) else { return }
        applyLMStudioSnapshot(snapshot)
    }
    
    // Explicit refresh of LM Studio models with UI feedback
    public func refreshLMStudioModelsExplicitly() async {
        self.errorMessage = nil
        guard let snapshot = await modelDiscovery.discover(baseURL: lmStudioBaseURL, force: true) else {
            self.errorMessage = "Failed to connect to LM Studio at \(lmStudioBaseURL). Make sure LM Studio is running, its Local Server is started, and cross-origin (CORS) is allowed."
            return
        }
        guard !snapshot.models.isEmpty else { self.errorMessage = "Connected to LM Studio but no models are currently loaded."; return }
        applyLMStudioSnapshot(snapshot)
    }

    public var injectingLMStudioModelId: String? = nil
    public var injectedLMStudioModels: Set<String> = []
    public var injectStatusMessage: String? = nil

    /// Injects/loads the selected model directly into LM Studio memory space (Metal RAM)
    @MainActor
    public func injectLMStudioModel(modelId: String) async {
        guard !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        injectingLMStudioModelId = modelId
        injectStatusMessage = "Injecting model into memory..."
        
        let trimmedBase = lmStudioBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            injectingLMStudioModelId = nil
            injectStatusMessage = "Invalid LM Studio URL"
            return
        }
        
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": "hello"]
            ],
            "max_tokens": 1,
            "temperature": 0.0,
            "stream": false
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await networkSession.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                injectedLMStudioModels.insert(modelId)
                injectingLMStudioModelId = nil
                injectStatusMessage = "Ready in memory!"
                
                // Refresh snapshot
                await fetchLMStudioModels()
            } else {
                let errText = String(data: data, encoding: .utf8) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                injectingLMStudioModelId = nil
                injectStatusMessage = "Failed to inject: \(errText)"
            }
        } catch {
            injectingLMStudioModelId = nil
            injectStatusMessage = "Error: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func applyLMStudioSnapshot(_ snapshot: LMStudioModelSnapshot) {
        lmStudioAvailableModels = snapshot.models
        lmStudioModelContextLengths = snapshot.contextLengths
        
        if autoSwitchLMStudioModel, let runningModel = snapshot.models.first {
            self.lmStudioModelId = runningModel
            if let activeId = activeThreadId,
               let index = threads.firstIndex(where: { $0.id == activeId }),
               threads[index].provider == .lmStudio {
                threads[index].lmStudioModelId = runningModel
            }
        }
        
        for index in threads.indices where threads[index].provider == .lmStudio && (threads[index].lmStudioModelId == nil || (autoSwitchLMStudioModel && threads[index].id == activeThreadId)) {
            threads[index].lmStudioModelId = snapshot.models.first
        }
        saveThreads()
    }
    
    // Get formatted Context Length pill label for LM Studio model
    public func getLMStudioContextLength(for modelId: String?) -> String {
        let activeModel = modelId ?? lmStudioModelId ?? lmStudioAvailableModels.first
        
        // Auto-trigger fetch if model context length is missing and we have a modelId
        if let model = activeModel, lmStudioModelContextLengths[model] == nil {
            Task {
                await fetchLMStudioModels()
            }
        }
        
        if let explicitLen = activeModel.flatMap({ lmStudioModelContextLengths[$0] }) {
            if explicitLen >= 1024 {
                if explicitLen % 1024 == 0 {
                    return "\(explicitLen / 1024)k ctx"
                } else {
                    return String(format: "%.1fk ctx", Double(explicitLen) / 1024.0)
                }
            } else {
                return "\(explicitLen) ctx"
            }
        }
        guard let model = activeModel else { return "8k ctx" }
        let lower = model.lowercased()
        if lower.contains("128k") {
            return "128k ctx"
        } else if lower.contains("64k") {
            return "64k ctx"
        } else if lower.contains("32k") {
            return "32k ctx"
        } else if lower.contains("16k") {
            return "16k ctx"
        } else if lower.contains("4k") {
            return "4k ctx"
        } else {
            return "8k ctx"
        }
    }
    
    private func contextTokenCapacity(for thread: ChatThread) -> Int {
        switch thread.provider {
        case .lmStudio:
            if let model = thread.lmStudioModelId ?? lmStudioModelId ?? lmStudioAvailableModels.first,
               let explicit = lmStudioModelContextLengths[model], explicit > 0 {
                return explicit
            }
            let label = (thread.lmStudioModelId ?? lmStudioModelId ?? "").lowercased()
            if label.contains("128k") { return 131_072 }
            if label.contains("64k") { return 65_536 }
            if label.contains("32k") { return 32_768 }
            if label.contains("16k") { return 16_384 }
            if label.contains("4k") { return 4_096 }
            return 8_192
        case .mlx:
            return 32_768
        case .gemini:
            return (thread.geminiModelId ?? "").lowercased().contains("pro") ? 2_000_000 : 1_000_000
        case .openAI, .openRouter:
            return 131_072
        }
    }

    /// Reserve ample room for system instructions, the current request, and
    /// model output. A conservative three characters per token prevents local
    /// tokenizers from exceeding their advertised window unexpectedly.
    private func historyCharacterBudget(for thread: ChatThread, reservedOutputTokens: Int? = nil) -> Int {
        let capacity = contextTokenCapacity(for: thread)
        let outputReserve = min(capacity / 2, reservedOutputTokens ?? max(1_024, Int(Double(capacity) * 0.30)))
        let systemTokens = max(0, getCompiledPrePrompt(for: thread.id).count / 3)
        let transportReserve = max(384, Int(Double(capacity) * 0.06))
        let availableHistoryTokens = max(256, capacity - outputReserve - systemTokens - transportReserve)
        return min(96_000, availableHistoryTokens * 3)
    }

    // Cache for compiled system prompt char count to avoid expensive recomputation on every streaming token
    private var cachedPrePromptCounts: [UUID: (timestamp: Date, count: Int)] = [:]

    // Calculate estimated tokens in prompt payload with cached preprompt count
    public func getEstimatedUsedTokens(for thread: ChatThread) -> Int {
        _ = contextRevision
        let now = Date()
        let sysCount: Int
        if let cached = cachedPrePromptCounts[thread.id], now.timeIntervalSince(cached.timestamp) < 4.0 {
            sysCount = cached.count
        } else {
            let compiledSystem = getCompiledPrePrompt(for: thread.id)
            sysCount = compiledSystem.count
            cachedPrePromptCounts[thread.id] = (timestamp: now, count: sysCount)
        }
        
        var totalChars = sysCount
        let visibleMessages = thread.messages.last?.text == "..." ? Array(thread.messages.dropLast()) : thread.messages
        for msg in visibleMessages {
            totalChars += msg.text.count
        }
        return min(contextTokenCapacity(for: thread), max(0, totalChars / 3))
    }
    
    // Get formatted Context Length string for any provider
    public func getThreadContextLength(for thread: ChatThread) -> String {
        switch thread.provider {
        case .lmStudio:
            return getLMStudioContextLength(for: thread.lmStudioModelId)
        case .mlx:
            return "32k–128k ctx"
        case .gemini:
            let model = (thread.geminiModelId ?? "").lowercased()
            if model.contains("pro") {
                return "2M ctx"
            }
            return "1M ctx"
        case .openAI:
            return "128k ctx"
        case .openRouter:
            return "128k ctx"
        }
    }
    
    // Unified metrics calculation for developer mode context indicator
    public func getContextUsageMetrics(for thread: ChatThread) -> (string: String, fraction: Double) {
        let capacity = max(1, contextTokenCapacity(for: thread))
        let usedTokens = getEstimatedUsedTokens(for: thread)
        let fraction = min(1.0, max(0.0, Double(usedTokens) / Double(capacity)))
        
        let usedFormatted: String
        if usedTokens >= 10_000 {
            usedFormatted = String(format: "%.1fk", Double(usedTokens) / 1000.0)
        } else if usedTokens >= 1000 {
            usedFormatted = String(format: "%.2fk", Double(usedTokens) / 1000.0)
        } else {
            usedFormatted = "\(usedTokens)"
        }
        
        let totalStr = getThreadContextLength(for: thread)
        let totalClean = totalStr.replacingOccurrences(of: " ctx", with: "")
        return ("\(usedFormatted)/\(totalClean) ctx", fraction)
    }

    // Get formatted Context Usage string: "<used>/<total> ctx"
    public func getContextUsageString(for thread: ChatThread) -> String {
        return getContextUsageMetrics(for: thread).string
    }

    public func getContextUsageFraction(for thread: ChatThread) -> Double {
        return getContextUsageMetrics(for: thread).fraction
    }
    
    // Clear/reset thread messages to empty context window
    @MainActor
    public func clearThreadMessages(threadId: UUID) {
        if activeGenerationTasks[threadId] != nil {
            stopGeneration(threadId: threadId)
        }
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        var updated = threads[index]
        updated.messages.removeAll()
        threads[index] = updated
        if toolRequestManager.activeRequestThreadId == threadId {
            toolRequestManager.clearActiveRequest()
        }
        toolRequestManager.finishProcessing(threadId: threadId)
        saveThreads()
    }
    
    // Fetch active valid models from OpenRouter API (https://openrouter.ai/api/v1/models)
    public func fetchOpenRouterModels() async {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return }
        var request = URLRequest(url: url)
        let apiKey = openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await networkSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = json["data"] as? [[String: Any]] {
                var fetchedModels: [String] = []
                var freeMap: [String: Bool] = [:]
                
                for item in dataArray {
                    guard let id = item["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    var isFree = id.hasSuffix(":free")
                    if let pricing = item["pricing"] as? [String: Any] {
                        let promptPrice = (pricing["prompt"] as? String) ?? "\(pricing["prompt"] ?? "")"
                        let compPrice = (pricing["completion"] as? String) ?? "\(pricing["completion"] ?? "")"
                        if (promptPrice == "0" || promptPrice == "0.0" || promptPrice == "0.00") &&
                           (compPrice == "0" || compPrice == "0.0" || compPrice == "0.00") {
                            isFree = true
                        }
                    }
                    fetchedModels.append(id)
                    freeMap[id] = isFree
                }
                
                let sorted = fetchedModels.sorted { (m1, m2) -> Bool in
                    let f1 = freeMap[m1] ?? m1.hasSuffix(":free")
                    let f2 = freeMap[m2] ?? m2.hasSuffix(":free")
                    if f1 != f2 { return f1 && !f2 }
                    return m1 < m2
                }
                
                await MainActor.run {
                    if !sorted.isEmpty {
                        self.openRouterModels = sorted
                        self.openRouterFreeMap = freeMap
                    }
                }
            }
        } catch {
            print("Failed to fetch OpenRouter models: \(error)")
        }
    }
    
    // Explicit refresh of OpenRouter models with UI feedback
    public func refreshOpenRouterModelsExplicitly() async {
        self.errorMessage = nil
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return }
        var request = URLRequest(url: url)
        let apiKey = openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await networkSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                self.errorMessage = "Failed to connect to OpenRouter API."
                return
            }
            guard httpResponse.statusCode == 200 else {
                self.errorMessage = "OpenRouter API returned HTTP error \(httpResponse.statusCode)."
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = json["data"] as? [[String: Any]] {
                var fetchedModels: [String] = []
                var freeMap: [String: Bool] = [:]
                
                for item in dataArray {
                    guard let id = item["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    var isFree = id.hasSuffix(":free")
                    if let pricing = item["pricing"] as? [String: Any] {
                        let promptPrice = (pricing["prompt"] as? String) ?? "\(pricing["prompt"] ?? "")"
                        let compPrice = (pricing["completion"] as? String) ?? "\(pricing["completion"] ?? "")"
                        if (promptPrice == "0" || promptPrice == "0.0" || promptPrice == "0.00") &&
                           (compPrice == "0" || compPrice == "0.0" || compPrice == "0.00") {
                            isFree = true
                        }
                    }
                    fetchedModels.append(id)
                    freeMap[id] = isFree
                }
                
                let sorted = fetchedModels.sorted { (m1, m2) -> Bool in
                    let f1 = freeMap[m1] ?? m1.hasSuffix(":free")
                    let f2 = freeMap[m2] ?? m2.hasSuffix(":free")
                    if f1 != f2 { return f1 && !f2 }
                    return m1 < m2
                }
                
                if sorted.isEmpty {
                    self.errorMessage = "Connected to OpenRouter but no valid models were returned."
                } else {
                    self.openRouterModels = sorted
                    self.openRouterFreeMap = freeMap
                }
            } else {
                self.errorMessage = "Unexpected response format from OpenRouter API."
            }
        } catch {
            self.errorMessage = "Failed to fetch OpenRouter models: \(error.localizedDescription)"
        }
    }
    
    // Get injected profile values context for the LLM prompt
    private func getSystemMemoryPrompt() -> String { "" }

    // Get the current date/time context string for system instructions
    private func getCurrentTimeContext() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        formatter.timeZone = TimeZone.current
        let timeString = formatter.string(from: Date())
        let timezone = TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier
        return "\nCURRENT DATE & TIME: \(timeString) (\(timezone))"
    }

    private func configuredEffortLevel() -> String {
        let value = preferences.string(forKey: "aiEffortLevel") ?? "Medium"
        return ["Low", "Medium", "High", "Advanced"].contains(value) ? value : "Medium"
    }

    private func reasoningEffortValue() -> String {
        switch configuredEffortLevel() {
        case "Low": return "low"
        case "Medium": return "medium"
        case "High": return "high"
        case "Advanced": return "high"
        default: return "medium"
        }
    }

    private func lmStudioThinkingIsEnabled() -> Bool {
        preferences.object(forKey: "lmStudioThinkingEnabled") as? Bool ?? true
    }

    private func reasoningIsEnabled(for provider: Provider? = nil) -> Bool {
        if provider == .lmStudio {
            return lmStudioThinkingIsEnabled()
        }
        return configuredEffortLevel() != "Low"
    }

    @MainActor
    public func continueLastResponse() async {
        guard let thread = activeThread else { return }
        self.errorMessage = nil
        
        // Remove empty or placeholder assistant message if left broken
        if let lastMsg = thread.messages.last, lastMsg.role == .assistant {
            let trimmed = lastMsg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "..." || trimmed.isEmpty {
                if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                    threads[index].messages.removeLast()
                    saveThreads()
                }
            }
        }
        
        await sendMessage(text: "Continue from where you left off.")
    }

    // Send message and stream response
    @MainActor
    public func sendMessage(
        text: String,
        attachedImageBase64: String? = nil,
        attachedFiles: [AttachedFile]? = nil,
        forceWebSearch: Bool = false
    ) async {
        if activeThread == nil {
            if let firstThread = threads.first {
                activeThreadId = firstThread.id
            } else {
                createNewChatWithDefaults()
            }
        }
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                         attachedImageBase64 != nil ||
                         (attachedFiles != nil && !attachedFiles!.isEmpty)
        guard let thread = activeThread, hasContent else { return }
        let threadId = thread.id
        
        let effectiveText: String = {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if attachedImageBase64 != nil { return "Describe this image in detail and answer any questions." }
            if let files = attachedFiles, !files.isEmpty { return "Please analyze the attached file(s) and provide a summary of the key information." }
            return ""
        }()
        activeGenerationTasks[threadId]?.cancel()
        activeGenerationIDs[threadId] = nil
        toolRequestManager.clearActiveRequest()
        controller(for: threadId).begin(goal: effectiveText)
        controller(for: threadId).beginExecution()
        beginUltraRun(goal: effectiveText, threadId: threadId)
        searchQueriesByThread[threadId] = []
        if forceWebSearch {
            mandatoryWebSearchThreadIds.insert(threadId)
        } else {
            mandatoryWebSearchThreadIds.remove(threadId)
        }
        constraintCorrectionThreadIds.remove(threadId)
        truncationContinuationThreadIds.remove(threadId)
        pendingHowToThreadIds.remove(threadId)
        toolNudgedThreadIds.remove(threadId)
        finalAnswerRecoveryThreadIds.remove(threadId)
        
        // 1. Add user message
        let attachmentID = attachedImageBase64.flatMap { attachmentStore.store(dataURL: $0) }
        let userMessage = ChatMessage(
            role: .user,
            text: effectiveText,
            attachedImageBase64: attachedImageBase64,
            attachmentID: attachmentID,
            attachedFiles: attachedFiles
        )
        var updatedThread = thread
        // Tool availability is now controlled by the individual Toolbox
        // switches. Retire the hidden per-thread master flag so an older chat
        // cannot silently make every visibly enabled capability unavailable.
        updatedThread.isToolUseEnabled = true
        updatedThread.messages.append(userMessage)
        
        // Update title if it's the first user message
        if updatedThread.messages.filter({ $0.role == .user }).count == 1 {
            let titleSource: String = {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                if let firstFile = attachedFiles?.first { return firstFile.name }
                return effectiveText
            }()
            let words = titleSource.split(separator: " ").prefix(4)
            updatedThread.title = words.joined(separator: " ") + (titleSource.split(separator: " ").count > 4 ? "..." : "")
        }
        
        // 2. Let the selected model decide whether an app launch or other
        // system action is needed. It can invoke the advertised file-system
        // tool with a strict JSON payload; plain user wording never runs a
        // command directly.
        let assistantMessageId = UUID()
        var assistantMessage = ChatMessage(id: assistantMessageId, role: .assistant, text: "...")
        assistantMessage.generationStartTime = Date()
        updatedThread.messages.append(assistantMessage)
        
        // Save initial thread state
        if let index = self.threads.firstIndex(where: { $0.id == threadId }) {
            self.threads[index] = updatedThread
            saveThreads()
        }

        // The Mac clock is the authoritative source for simple local date and
        // time questions. Answer directly instead of spending a model turn or
        // invoking web search (including when Research/Check is enabled).
        if Self.isLocalDateTimeQuestion(effectiveText), !forceWebSearch {
            updateAssistantMessage(
                threadId: threadId,
                messageId: assistantMessageId,
                text: localDateTimeAnswer(for: effectiveText),
                saveToDisk: true
            )
            controller(for: threadId).complete()
            return
        }
        
        let userMessages = updatedThread.messages.filter { $0.role == .user }.map(\.text)
        if userMessages.count == 3 {
            generateAutomaticTitle(for: updatedThread, userMessages: userMessages)
        }

        // Substantive knowledge requests use current web evidence by default.
        // Route the first search deterministically only when an explicit online search
        // is needed. Basic chat, capability questions, explicit opt-outs, and requests
        // owned by another tool are excluded by requestIntent so search can never hijack those workflows.
        let contextualSearchRequest = contextualizedSearchRequest(
            for: threadId,
            currentRequest: effectiveText
        )
        let mustSearchBeforeGeneration = shouldUseInternetSearch(
            for: contextualSearchRequest,
            mandatoryForCurrentTurn: forceWebSearch
        )
        if updatedThread.isToolUseEnabled,
           mustSearchBeforeGeneration,
           (forceWebSearch || !Self.isSelfOrCapabilityQuery(effectiveText)),
           (forceWebSearch || !Self.isNonSearchConversationalOrCapability(effectiveText)),
           isExposedSkillEnabled(StarterSkillCatalog.internetSearchID),
           preferences.object(forKey: "enableInternetSearch") as? Bool ?? true {
            let cleanedSubject = Self.cleanedSearchSubject(contextualSearchRequest)
            let cleanedQuery = forceWebSearch
                ? (cleanedSubject.isEmpty ? contextualSearchRequest : cleanedSubject)
                : cleanedSubject
            if !cleanedQuery.isEmpty {
                let request = ToolRequest(
                    type: "internet_use",
                    title: "Searching the web",
                    description: "Verifying information with current sources…",
                    fields: [],
                    query: cleanedQuery
                )
                if let threadIndex = self.threads.firstIndex(where: { $0.id == threadId }),
                   let placeholderIndex = self.threads[threadIndex].messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    self.threads[threadIndex].messages[placeholderIndex].text = (try? String(data: JSONEncoder().encode(request), encoding: .utf8)) ?? "{\"type\":\"internet_use\"}"
                    saveThreads()
                }
                configureToolRegistry()
                let call = normalizedToolCall(from: request)
                if controller(for: threadId).prepare(call) == nil {
                    performInternetSearch(toolRequest: request, threadId: threadId)
                }
                return
            }
        }

        // Fast deterministic route for an unambiguous folder/file scaffold.
        // This must not depend on a local model choosing one of several JSON
        // tool-call dialects.
        if updatedThread.isToolUseEnabled,
           isExposedSkillEnabled(StarterSkillCatalog.filesystemID),
           preferences.object(forKey: "enableFileSystem") as? Bool ?? true,
           let creation = FileSystemSkill.routedSimpleCreation(for: effectiveText) {
            let request = ToolRequest(
                type: "file_system",
                title: "terminal used",
                description: creation.filename == nil ? "Creating folder…" : "Creating folder and file…",
                fields: [],
                action: "create_folder",
                path: creation.folder
            )
            if let threadIndex = self.threads.firstIndex(where: { $0.id == threadId }),
               let placeholderIndex = self.threads[threadIndex].messages.firstIndex(where: { $0.id == assistantMessageId }) {
                self.threads[threadIndex].messages[placeholderIndex].text = (try? String(data: JSONEncoder().encode(request), encoding: .utf8)) ?? "{\"type\":\"file_system\",\"action\":\"create_folder\"}"
                saveThreads()
            }
            configureToolRegistry()
            let call = normalizedToolCall(from: request)
            if controller(for: threadId).prepare(call) == nil {
                Task { await self.performFileSystemAction(toolRequest: request, threadId: threadId) }
            }
            return
        }

        // Fast deterministic skill route: common filesystem intents do not
        // need a local model to restate a plan or synthesize shell commands.
        if updatedThread.isToolUseEnabled,
           isExposedSkillEnabled(StarterSkillCatalog.filesystemID),
           preferences.object(forKey: "enableFileSystem") as? Bool ?? true,
           let route = FileSystemSkill.routedAction(for: effectiveText) {
            let request = ToolRequest(
                type: "file_system",
                title: "terminal used",
                description: "Running verified filesystem skill…",
                fields: [],
                action: route.action,
                path: route.path
            )
            if let messageIndex = self.threads.firstIndex(where: { $0.id == threadId }),
               let placeholderIndex = self.threads[messageIndex].messages.firstIndex(where: { $0.id == assistantMessageId }) {
                self.threads[messageIndex].messages[placeholderIndex].text = (try? String(data: JSONEncoder().encode(request), encoding: .utf8)) ?? "{\"type\":\"file_system\",\"action\":\"\(route.action)\"}"
                saveThreads()
            }
            Task { await self.performFileSystemAction(toolRequest: request, threadId: threadId) }
            return
        }

        
        // 3. Trigger generation
        executeGeneration(
            threadId: threadId,
            assistantMessageId: assistantMessageId,
            promptText: text,
            provider: updatedThread.provider,
            systemInstructions: updatedThread.systemInstructions,
            temperature: updatedThread.temperature,
            lmStudioModelId: updatedThread.lmStudioModelId,
            mlxModelId: updatedThread.mlxModelId,
            geminiModelId: updatedThread.geminiModelId,
            openRouterModelId: updatedThread.openRouterModelId,
            isToolUseEnabled: updatedThread.isToolUseEnabled
        )
    }
    
    // Automatically send collected tool values back to LLM
    @MainActor
    public func sendToolResponse(text: String, threadId requestedThreadId: UUID? = nil, visionImageBase64: String? = nil, forceDirectAnswer: Bool = false) async {
        let targetThreadId = requestedThreadId ?? activeThreadId
        guard let targetThreadId,
              let thread = threads.first(where: { $0.id == targetThreadId }) else { return }
        let threadId = thread.id
        recordLegacyToolResponse(text, threadId: threadId)
        
        // Keep multi-step runs moving, but do not let the model expand the task
        // with speculative verification, navigation, or other unrequested work.
        var payloadText = text
        if !payloadText.contains("SYSTEM DIRECTIVE FOR TOOL RESPONSE") {
            let originalGoal = controller(for: threadId).activeRun?.userGoal ?? ""
            payloadText += "\n\n[SYSTEM DIRECTIVE FOR TOOL RESPONSE: The immutable original user request is: \(originalGoal). Preserve its exact product names, chip generations, quantities, dates, and other constraints. Search results about older/different hardware are supporting evidence only and must never replace the requested hardware. If evidence for the exact configuration is unavailable, say so explicitly and label any extrapolation. Inspect the tool result above. Execute exactly one next action only when explicitly required; otherwise answer immediately. Do not add unrequested actions or narrate private reasoning.]"
        }
        if pendingHowToThreadIds.contains(threadId) {
            payloadText += """

            [REQUIRED HOW-TO CAPTURE: This task reached a verified result only after multiple failed attempts or a long tool sequence. Before the final answer, use Learning to preserve the final proven method. First call learning with action \"list\". Then update the matching entry by learningId, or append a new entry with learningKind \"how-to\" and a specific 2–6 word learningTopic. Reuse the same topic for related knowledge so it appears under one visible subheading in Skills → Learning. Include when it applies, preconditions, ordered successful steps, verification, and the failed approach/pitfall to avoid. Do not include credentials, raw logs, or private reasoning. Do not claim it is saved until the tool confirms success.]
            """
        }
        if forceDirectAnswer {
            payloadText += """

            [DIRECT FINAL ANSWER REQUIRED: Retrieval is complete. Do not call another tool and do not emit private reasoning, a plan, or <think> tags. Return only the complete user-facing answer. Use all supplied evidence, cover every item and exact quantity in the original request, and perform required calculations. Include only fields the user requested. Never add empty/unknown table columns, generic template fields, a Source Notes column, or unsolicited commentary. If citations are required, keep compact links outside the data table.]
            """
        }
        
        // 1. Add user message containing the tool response JSON (which will be suppressed in UI)
        var updatedThread = thread
        let userMessage = ChatMessage(role: .user, text: payloadText, attachedImageBase64: visionImageBase64)
        updatedThread.messages.append(userMessage)
        
        // 2. Add empty assistant message for streaming
        let assistantMessageId = UUID()
        var assistantMessage = ChatMessage(id: assistantMessageId, role: .assistant, text: "...")
        assistantMessage.generationStartTime = Date()
        updatedThread.messages.append(assistantMessage)
        
        if let index = self.threads.firstIndex(where: { $0.id == threadId }) {
            self.threads[index] = updatedThread
            saveThreads()
        }
        
        // 3. Trigger generation
        executeGeneration(
            threadId: threadId,
            assistantMessageId: assistantMessageId,
            promptText: payloadText,
            provider: updatedThread.provider,
            systemInstructions: updatedThread.systemInstructions,
            temperature: updatedThread.temperature,
            lmStudioModelId: updatedThread.lmStudioModelId,
            mlxModelId: updatedThread.mlxModelId,
            geminiModelId: updatedThread.geminiModelId,
            openRouterModelId: updatedThread.openRouterModelId,
            isToolUseEnabled: forceDirectAnswer ? false : updatedThread.isToolUseEnabled,
            forceDirectAnswer: forceDirectAnswer
        )
    }

    @MainActor
    private func continueAfterOutputLimit(threadId: UUID) async {
        guard !truncationContinuationThreadIds.contains(threadId) else { return }
        truncationContinuationThreadIds.insert(threadId)
        await diagnostics.record(category: "generation", message: "provider output limit; continuing once", threadID: threadId)
        await sendToolResponse(
            text: #"{ "tool_response": { "status": "The provider reached its output-token limit. Continue the immediately preceding answer from the exact stopping point. Do not repeat earlier sections. Finish every remaining item from the original request, then conclude normally." } }"#,
            threadId: threadId
        )
    }

    /// Registry setup is the sole place that binds app capabilities to their
    /// settings. The execution loop only deals in normalized names and calls.
    private func configureToolRegistry() {
        let enabled: (String) -> Bool = { [self] key in preferences.object(forKey: key) as? Bool ?? true }
        toolRegistry.register(RegisteredAgentTool(name: "dynamic_insights", description: "Render a native insight block.", isEnabled: enabled("enableDynamicInsights") && isExposedSkillEnabled(StarterSkillCatalog.dynamicInsightsID)))
        toolRegistry.register(RegisteredAgentTool(name: "internet_search", description: "Retrieve current web results.", isEnabled: enabled("enableInternetSearch") && isExposedSkillEnabled(StarterSkillCatalog.internetSearchID), requiredArguments: ["query"]))
        toolRegistry.register(RegisteredAgentTool(name: "advanced_memory", description: "Update durable knowledge graph memory.", isEnabled: isExposedSkillEnabled(StarterSkillCatalog.advancedMemoryID)))
        toolRegistry.register(RegisteredAgentTool(name: "learning", description: "Maintain verified reusable behavioral lessons.", isEnabled: isExposedSkillEnabled(StarterSkillCatalog.learningID), requiredArguments: ["action"]))
        toolRegistry.register(RegisteredAgentTool(name: "terminal_access", description: "Execute a validated file or terminal action.", isEnabled: enabled("enableFileSystem") && isExposedSkillEnabled(StarterSkillCatalog.filesystemID), requiredArguments: ["action"]))

        // Register tools discovered from active MCP servers
        for mcpTool in MCPServerManager.shared.allTools {
            toolRegistry.register(RegisteredAgentTool(
                name: mcpTool.qualifiedName,
                description: mcpTool.description.isEmpty ? "MCP tool '\(mcpTool.name)' from server '\(mcpTool.serverName)'" : mcpTool.description,
                isEnabled: true
            ))
            toolRegistry.register(RegisteredAgentTool(
                name: mcpTool.name,
                description: mcpTool.description.isEmpty ? "MCP tool '\(mcpTool.name)' from server '\(mcpTool.serverName)'" : mcpTool.description,
                isEnabled: true
            ))
        }
        toolRegistry.register(RegisteredAgentTool(
            name: "mcp_call",
            description: "Call an MCP tool with server, tool name, and arguments.",
            isEnabled: !MCPServerManager.shared.allTools.isEmpty,
            requiredArguments: ["tool"]
        ))
    }

    private func normalizedToolCall(from request: ToolRequest) -> AgentToolCall {
        let name: String
        switch request.type {
        case "internet_use": name = "internet_search"
        case "advanced_memory": name = "advanced_memory"
        case "learning": name = "learning"
        case "file_system": name = "terminal_access"
        case "apple_notes": name = "apple_notes"
        case "mcp": name = request.mcpTool ?? request.title
        default: name = "dynamic_insights"
        }
        var values: ToolArguments = ["title": .string(request.title)]
        if let query = request.query { values["query"] = .string(query) }
        if let action = request.action {
            let canonicalAction: String
            if request.type == "file_system" {
                canonicalAction = Self.canonicalFileSystemAction(action)
            } else {
                canonicalAction = action
            }
            values["action"] = .string(canonicalAction)
        }
        if let path = request.path { values["path"] = .string(path) }
        if let content = request.content { values["content"] = .string(content) }
        if let command = request.command { values["command"] = .string(command) }
        if let html = request.html { values["html"] = .string(html) }
        if let files = request.files {
            values["files"] = .array(files.map { .object(["path": .string($0.path), "content": .string($0.content)]) })
        }
        if let learningId = request.learningId { values["learningId"] = .string(learningId) }
        if let learningKind = request.learningKind { values["learningKind"] = .string(learningKind) }
        if let learningTopic = request.learningTopic { values["learningTopic"] = .string(learningTopic) }
        if let folder = request.folder { values["folder"] = .string(folder) }
        if let noteId = request.noteId { values["noteId"] = .string(noteId) }
        if let mcpServer = request.mcpServer { values["server"] = .string(mcpServer) }
        if let mcpTool = request.mcpTool { values["tool"] = .string(mcpTool) }
        if let mcpArgs = request.mcpArguments {
            for (k, v) in mcpArgs { values[k] = v }
        }
        return AgentToolCall(name: name, arguments: values)
    }

    /// Local models often borrow synonymous action names from other tool APIs.
    /// Canonicalize only unambiguous aliases so a harmless vocabulary mismatch
    /// never becomes a failed filesystem operation.
    nonisolated private static func canonicalFileSystemAction(_ rawAction: String) -> String {
        let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch action {
        case "create_directory", "make_directory", "mkdir", "new_folder", "make_folder":
            return "create_folder"
        case "write_file", "save_file", "update_file":
            return "create_file"
        case "read", "cat", "get_file", "read_text_file":
            return "read_file"
        case "ls", "list_directory", "list_files", "get_directory_contents":
            return "list"
        case "command", "terminal", "run_command", "shell", "shell_command", "exec":
            return "execute_command"
        default:
            return action
        }
    }

    nonisolated private static func sanitizedGeneratedFileContent(_ rawContent: String) -> String {
        var content = rawContent
        // Model chat-template control tokens are transport metadata, never
        // valid generated-file content. Remove any that leak at the beginning.
        let leadingToken = #"(?is)^\s*<\|(?:channel|assistant|analysis|final)(?:\|)?>\s*"#
        while let range = content.range(of: leadingToken, options: .regularExpression) {
            content.removeSubrange(range)
        }
        return content
    }

    private func sendAgentToolResult(_ result: AgentToolResult, threadId: UUID) {
        let payload = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        Task { await self.sendToolResponse(text: "{\"tool_response\":\(payload)}", threadId: threadId) }
    }

    /// Existing tool implementations already emit JSON into the conversation.
    /// Normalize that transport at the boundary so the run ledger records the
    /// result only after the operation (and its existing verification) returns.
    private func recordLegacyToolResponse(_ text: String, threadId: UUID) {
        let controller = controller(for: threadId)
        guard let run = controller.activeRun, let call = run.pendingToolCall else { return }
        let response = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        let payload = response?["tool_response"] as? [String: Any]
        let success: Bool
        if let reportedSuccess = payload?["success"] as? Bool {
            success = reportedSuccess
        } else if let status = payload?["status"] as? String {
            success = !status.hasPrefix("Error:")
        } else {
            success = true
        }
        let result = AgentToolResult(
            callID: call.id,
            toolName: call.name,
            success: success,
            payload: ["transport": .string("legacy_tool_response")],
            error: success ? nil : AgentToolError(code: "TOOL_EXECUTION_FAILED", message: payload?["status"] as? String ?? "The tool returned an error response.", retryable: true)
        )
        controller.record(result)
        finishUltraToolTask(callID: call.id, success: success, retryable: result.error?.retryable ?? false, threadId: threadId)
        if success,
           call.name != "learning",
           let updatedRun = controller.activeRun {
            let elapsed = Date().timeIntervalSince(updatedRun.startedAt)
            let recoveredAfterFailures = updatedRun.failedToolCalls.count >= 2 && !updatedRun.completedToolCalls.isEmpty
            let longVerifiedWorkflow = updatedRun.stepCount >= 6 && elapsed >= 60 && !updatedRun.completedToolCalls.isEmpty
            if recoveredAfterFailures || longVerifiedWorkflow {
                pendingHowToThreadIds.insert(threadId)
            }
        }
        Task { await learningStore.record(toolName: call.name, succeeded: success, duration: Date().timeIntervalSince(run.startedAt)) }
    }

    private func boundedToolOutput(_ output: String, maximumCharacters: Int = 12_000, maximumLines: Int = 300) -> String {
        let lines = output.components(separatedBy: .newlines)
        if output.count <= maximumCharacters && lines.count <= maximumLines { return output }
        let headLines = max(1, maximumLines * 2 / 3)
        let tailLines = max(0, maximumLines - headLines)
        let retainedLines = Array(lines.prefix(headLines)) + Array(lines.suffix(tailLines))
        let retained = String(retainedLines.joined(separator: "\n").prefix(maximumCharacters))
        return "\(retained)\n\n[Output truncated: \(lines.count) lines / \(output.count) characters; first \(headLines) and last \(tailLines) lines retained.]"
    }

    /// Computes the effective text to send to the model, including structured attached file contents.
    public static func effectiveMessageText(for message: ChatMessage) -> String {
        var base = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let files = message.attachedFiles, !files.isEmpty {
            var fileDocs = ""
            for file in files {
                if let content = file.textContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let typeLabel = file.fileExtension.uppercased()
                    let pageLabel = file.pageCount.map { "\($0) pages, " } ?? ""
                    let sizeLabel = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                    fileDocs += "\n\n[ATTACHED FILE: \(file.name) (\(typeLabel), \(pageLabel)\(sizeLabel))]\n```\(file.fileExtension.lowercased())\n\(content)\n```"
                }
            }
            if !fileDocs.isEmpty {
                if base.isEmpty {
                    base = "Please analyze the attached file(s) and provide a comprehensive response." + fileDocs
                } else {
                    base = base + fileDocs
                }
            }
        }
        return base
    }

    /// Keep the high-value recent conversation while bounding prompt-prefill
    /// cost and memory. Full transcripts remain stored on disk and visible in
    /// the UI; only the model-facing copy is compacted.
    private static func optimizedHistory(_ messages: [ChatMessage], maximumCharacters: Int) -> [ChatMessage] {
        let compacted = messages.map { message in
            // Search evidence is already bounded per source. Keep the whole
            // structured response whenever practical; the former 4k cutoff
            // silently discarded middle sources before the model saw them.
            guard message.isToolResponse, message.text.count > 16_000 else { return message }
            let prefix = String(message.text.prefix(11_000))
            let suffix = String(message.text.suffix(3_500))
            return ChatMessage(
                id: message.id,
                role: message.role,
                text: "\(prefix)\n\n[Tool output compacted: \(message.text.count) characters]\n\n\(suffix)",
                timestamp: message.timestamp,
                attachedImageBase64: message.attachedImageBase64,
                attachmentID: message.attachmentID,
                attachedFiles: message.attachedFiles
            )
        }

        var selected: [ChatMessage] = []
        var usedCharacters = 0
        for message in compacted.reversed() {
            let cost = message.text.count + 24
            if selected.isEmpty && cost > maximumCharacters {
                let headCount = max(1, maximumCharacters * 3 / 4)
                let tailCount = max(0, maximumCharacters - headCount - 80)
                let shortened = "\(message.text.prefix(headCount))\n\n[Message compacted to fit model context]\n\n\(message.text.suffix(tailCount))"
                selected.append(ChatMessage(
                    id: message.id,
                    role: message.role,
                    text: shortened,
                    timestamp: message.timestamp,
                    attachedImageBase64: message.attachedImageBase64,
                    attachmentID: message.attachmentID,
                    attachedFiles: message.attachedFiles
                ))
                break
            }
            if !selected.isEmpty && usedCharacters + cost > maximumCharacters { break }
            selected.append(message)
            usedCharacters += cost
            if selected.count >= 48 { break }
        }
        return selected.reversed()
    }

    /// Recovery turns need the complete latest tool evidence, not earlier
    /// private thought text. Use a compact evidence-first history and a larger
    /// minimum budget because the normal budget assumes the full tool-enabled
    /// system prompt, which direct recovery intentionally does not send.
    private func generationHistory(
        for thread: ChatThread,
        reservedOutputTokens: Int,
        forceDirectAnswer: Bool
    ) -> [ChatMessage] {
        var candidates = Array(thread.messages.dropLast())
        if forceDirectAnswer {
            candidates = candidates.filter { message in
                message.role == .user || !Self.assistantDisplayText(from: message.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        let normalBudget = historyCharacterBudget(for: thread, reservedOutputTokens: reservedOutputTokens)
        let containsSearchEvidence = candidates.contains { message in
            message.isToolResponse && message.text.contains("\"search_results\"")
        }
        let evidenceBudget = containsSearchEvidence ? max(12_000, normalBudget) : normalBudget
        let optimized = Self.optimizedHistory(
            candidates,
            maximumCharacters: forceDirectAnswer ? max(14_000, evidenceBudget) : evidenceBudget
        )
        // Qwen 3.5's LM Studio template rejects a compacted conversation when
        // the first non-system entry is an orphaned assistant message, even if
        // a valid user query appears later ("No user query found"). Start the
        // retained history at a genuine user turn so every provider receives
        // a structurally complete conversation boundary. Tool-result messages
        // alone do not establish that boundary.
        if let firstUserIndex = optimized.firstIndex(where: {
            $0.role == .user && !$0.isToolResponse
        }) {
            return Array(optimized[firstUserIndex...])
        }
        // If a very small context budget retained only the latest tool result,
        // explicitly restore its originating user query before that result.
        if let anchor = candidates.last(where: { $0.role == .user && !$0.isToolResponse }) {
            return [anchor] + optimized
        }
        return optimized
    }

    @MainActor
    private func finalizeDirectAnswerRecovery(threadId: UUID, messageId: UUID) {
        guard let thread = threads.first(where: { $0.id == threadId }),
              let message = thread.messages.first(where: { $0.id == messageId }) else { return }
        let originalRequest = controller(for: threadId).activeRun?.userGoal ?? ""
        let cleanedMessage = Self.sanitizedAnswerPresentation(message.text, request: originalRequest)
        if cleanedMessage != message.text {
            updateAssistantMessage(threadId: threadId, messageId: messageId, text: cleanedMessage, saveToDisk: true)
        }
        let visible = Self.assistantDisplayText(from: cleanedMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if visible.isEmpty {
            if let promoted = Self.promotedAnswerFromCompletedReasoning(message.text) {
                let reasoning = message.parsedReasoning.reasoningText?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rendered = reasoning.isEmpty
                    ? promoted
                    : "<think>\(reasoning)</think>\n\n\(promoted)"
                updateAssistantMessage(
                    threadId: threadId,
                    messageId: messageId,
                    text: rendered,
                    saveToDisk: true
                )
                controller(for: threadId).complete()
                Task { await diagnostics.record(category: "generation", message: "promoted labeled result from reasoning-only completion", threadID: threadId) }
                return
            }
            updateAssistantMessage(
                threadId: threadId,
                messageId: messageId,
                text: "I found the sources, but the selected model produced neither a visible answer nor a safely identifiable result section. Please retry this message or switch the model; the completed queries and sources remain available in Activity.",
                saveToDisk: true
            )
            controller(for: threadId).fail()
            Task { await diagnostics.record(category: "generation", message: "direct answer recovery produced no visible text", threadID: threadId) }
        } else {
            controller(for: threadId).complete()
        }
    }

    /// Some local reasoning models put a finished result inside their private
    /// channel and never emit an answer channel. Promote only an unmistakably
    /// labeled result/summary section; never expose the preceding deliberation
    /// as the user's answer. The complete reasoning remains collapsible in the
    /// transcript when Effort is enabled.
    nonisolated private static func promotedAnswerFromCompletedReasoning(_ rawText: String) -> String? {
        guard let reasoning = ChatMessage.extractReasoning(from: rawText).reasoningText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !reasoning.isEmpty else { return nil }

        let markers = [
            "**Final answer:**", "## Final answer", "Final answer:",
            "**Totals:**", "## Totals", "Totals:",
            "**Total:**", "## Total", "Total:",
            "**Summary:**", "## Summary", "Summary:"
        ]
        guard let markerRange = markers.compactMap({ marker in
            reasoning.range(of: marker, options: [.caseInsensitive, .backwards])
        }).max(by: { $0.lowerBound < $1.lowerBound }) else { return nil }

        var answer = String(reasoning[markerRange.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingDeliberationPatterns = [
            #"(?is)\n\s*(?:let(?:'|’)s|let me)\s+(?:double[- ]check|verify|recheck|calculate|think).*$"#,
            #"(?is)\n\s*(?:i\s+(?:need|should|will)\s+to|wait[,.:]).*$"#,
            #"(?is)\n\s*(?:next[,.:]|now\s+i\s+(?:need|should|will)).*$"#
        ]
        for pattern in trailingDeliberationPatterns {
            answer = answer.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        // A result section must contain concrete content, not merely a heading
        // the model wrote before stopping.
        let hasNumber = answer.range(of: #"\d"#, options: .regularExpression) != nil
        let words = answer.split(whereSeparator: { $0.isWhitespace }).count
        guard answer.count >= 24, words >= 4, hasNumber else { return nil }
        return answer
    }

    /// Keep model-generated tables aligned with the user's requested fields.
    /// Small models frequently copy broad templates that contain irrelevant or
    /// entirely empty columns. Removing those columns deterministically is
    /// safer than asking the model to rewrite otherwise correct calculations.
    nonisolated private static func sanitizedAnswerPresentation(_ rawText: String, request: String) -> String {
        let parsed = ChatMessage.extractReasoning(from: rawText)
        var main = parsed.mainText
        let requestLower = request.lowercased()
        let asksForSources = ["source", "citation", "evidence", "reference"].contains { requestLower.contains($0) }

        func cells(in line: String) -> [String] {
            var parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.first?.isEmpty == true { parts.removeFirst() }
            if parts.last?.isEmpty == true { parts.removeLast() }
            return parts
        }
        func isSeparator(_ value: String) -> Bool {
            value.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
        func isPlaceholder(_ value: String) -> Bool {
            let normalized = value
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return ["", "-", "—", "–", "n/a", "na", "none", "unknown", "not available"].contains(normalized)
        }
        func normalizedHeader(_ value: String) -> String {
            value.lowercased()
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lines = main.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0
        var removedHeaders = Set<String>()
        while index < lines.count {
            guard lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") else {
                output.append(lines[index]); index += 1; continue
            }
            let start = index
            while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                index += 1
            }
            let block = Array(lines[start..<index])
            guard block.count >= 2 else { output.append(contentsOf: block); continue }
            let header = cells(in: block[0])
            let separator = cells(in: block[1])
            guard !header.isEmpty, separator.count == header.count, separator.allSatisfy(isSeparator) else {
                output.append(contentsOf: block); continue
            }
            let rows = block.dropFirst(2).map(cells)
            var retainedIndices: [Int] = []
            for column in header.indices {
                let name = normalizedHeader(header[column])
                let allEmpty = rows.allSatisfy { row in column >= row.count || isPlaceholder(row[column]) }
                let isSourceNotes = name.contains("source") || name.contains("citation") || name == "notes" || name.contains("source notes")
                // Match semantic header words instead of exact normalized
                // strings. Headers such as "Calories (kcal)", "Protein (g)",
                // and "Total Fat" otherwise get removed at finalization even
                // though their cells contain valid values.
                // Do not infer table orientation from header names. Models can
                // validly put nutrients in rows and foods in columns; removing
                // "non-macro" headers in that layout deleted the whole table
                // after streaming completed. Only discard objectively empty
                // columns and unrequested source-note columns.
                if allEmpty || (isSourceNotes && !asksForSources) {
                    removedHeaders.insert(name)
                } else {
                    retainedIndices.append(column)
                }
            }

            // Never replace a valid streamed table with an empty block during
            // completion cleanup. If every column was filtered, preserve the
            // original Markdown exactly as the user already saw it.
            guard !retainedIndices.isEmpty else {
                output.append(contentsOf: block)
                continue
            }
            func renderedRow(_ row: [String]) -> String {
                "| " + retainedIndices.map { $0 < row.count ? row[$0] : "" }.joined(separator: " | ") + " |"
            }
            output.append(renderedRow(header))
            output.append("| " + retainedIndices.map { _ in "---" }.joined(separator: " | ") + " |")
            output.append(contentsOf: rows.map(renderedRow))
        }

        if !removedHeaders.isEmpty {
            lines = output.filter { line in
                let lower = line.lowercased()
                let isOmissionNote = lower.trimmingCharacters(in: .whitespaces).hasPrefix("*note:") ||
                    lower.trimmingCharacters(in: .whitespaces).hasPrefix("note:")
                guard isOmissionNote else { return true }
                return !removedHeaders.contains { header in
                    !header.isEmpty && lower.contains(header) &&
                    ["not listed", "not always listed", "not available", "not provided", "empty", "missing"].contains { lower.contains($0) }
                }
            }
        } else {
            lines = output
        }
        main = lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let reasoning = parsed.reasoningText, !reasoning.isEmpty else { return main }
        return "<think>\(reasoning)</think>\n\n\(main)"
    }
    
    // Execute streaming generation from Provider
    // Cache the active generation task to allow canceling it
    private var titleGenerationThreadIds: Set<UUID> = []
    // A local model can occasionally describe a next step instead of making
    // the required call. Keep a single corrective turn per unfinished action
    // so the conversation reaches a result without creating a retry loop.
    private var toolNudgedThreadIds: Set<UUID> = []
    // Separate from generic tool nudges: one correction is allowed when a
    // model silently changes an exact hardware constraint such as M5 to M1.
    private var constraintCorrectionThreadIds: Set<UUID> = []
    // At most one automatic continuation is allowed per user turn when a
    // provider explicitly reports an output-token limit.
    private var truncationContinuationThreadIds: Set<UUID> = []
    // A reasoning model can finish a post-tool turn inside an unterminated
    // private thought block. Retry once without provider reasoning; if that
    // still fails, surface an explicit recoverable error instead of an empty
    // chat transcript.
    private var finalAnswerRecoveryThreadIds: Set<UUID> = []
    // Set after a long or failure-heavy tool sequence finally succeeds. The
    // model must capture the proven method in Learning before it finalizes.
    private var pendingHowToThreadIds: Set<UUID> = []
    
    // Stop response generation (kill chat stream)
    @MainActor
    public func stopGeneration(threadId: UUID? = nil) {
        guard let targetThreadId = threadId ?? activeThreadId else { return }
        Task { await diagnostics.record(category: "generation", message: "cancelled", threadID: targetThreadId) }
        self.activeGenerationTasks[targetThreadId]?.cancel()
        self.activeGenerationTasks[targetThreadId] = nil
        self.activeGenerationIDs[targetThreadId] = nil
        self.controller(for: targetThreadId).cancel()
        self.mandatoryWebSearchThreadIds.remove(targetThreadId)
        self.toolRequestManager.finishProcessing(threadId: targetThreadId)
        refreshGenerationState()
        
        // Clean up trailing "..." loading indicator if generation was cancelled early
        if let threadIndex = self.threads.firstIndex(where: { $0.id == targetThreadId }),
           let lastMsg = self.threads[threadIndex].messages.last,
           lastMsg.role == .assistant,
           lastMsg.text == "..." {
            self.threads[threadIndex].messages.removeLast()
            saveThreads()
        }
    }
    
    // Execute streaming generation from Provider
    @MainActor
    private func executeGeneration(
        threadId: UUID,
        assistantMessageId: UUID,
        promptText: String,
        provider: Provider,
        systemInstructions: String,
        temperature: Double,
        lmStudioModelId: String?,
        mlxModelId: String? = nil,
        geminiModelId: String?,
        openRouterModelId: String?,
        isToolUseEnabled: Bool,
        forceDirectAnswer: Bool = false
    ) {
        self.errorMessage = nil
        let configuredOpenAIBaseURL = self.openAIBaseURL
        // Freeze mutable preferences at the run boundary. Provider request
        // closures then operate on immutable, Sendable values for the entire
        // generation instead of consulting UI-owned state mid-flight.
        let providerReasoningEnabled = !forceDirectAnswer && reasoningIsEnabled(for: provider)
        let providerReasoningEffort = reasoningEffortValue()
        let directAnswerSystemInstruction = forceDirectAnswer ? """

        [DIRECT FINAL ANSWER RECOVERY]
        Tool retrieval already finished. Respond with only the complete visible answer. Do not output private reasoning, <think> tags, a plan, or a tool call. Cover the original request fully, calculate from the evidence where needed, and mention assumptions or evidence gaps briefly.
        Include only requested fields. Omit every empty or unavailable field instead of displaying a dash. Never add a Source Notes column or generic template columns. Put any necessary citations outside the table.
        """ : ""
        let generationIntent = Self.requestIntent(for: promptText)
        let requestedMaxTokens: Int = {
            if forceDirectAnswer { return 2_048 }
            switch configuredEffortLevel() {
            case "Low": return generationIntent.isComplex ? 3_072 : 2_048
            case "High": return generationIntent.isComplex ? 10_240 : 6_144
            case "Advanced": return generationIntent.isComplex ? 16_384 : 8_192
            default: return generationIntent.isComplex ? 6_144 : 4_096
            }
        }()
        // Local models share one finite context window between history,
        // reasoning, and output. Cloud providers have much larger windows.
        let adaptiveMaxTokens: Int = {
            guard provider == .lmStudio || provider == .mlx,
                  let thread = self.threads.first(where: { $0.id == threadId }) else {
                return requestedMaxTokens
            }
            let safeLocalOutput = max(2_048, Int(Double(contextTokenCapacity(for: thread)) * 0.42))
            return min(requestedMaxTokens, safeLocalOutput)
        }()
        
        let generationID = UUID()
        self.activeGenerationIDs[threadId] = generationID
        Task { await diagnostics.record(category: "generation", message: "started provider=\(provider.rawValue)", threadID: threadId) }
        let task = Task {
            if provider == .gemini {
                // --- GEMINI ONLINE API GENERATION ---
                let apiKey = self.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let model = geminiModelId ?? "gemini-2.5-flash"
                
                var contentsArray: [[String: Any]] = []
                
                var threadMessages: [ChatMessage] = []
                if let idx = self.threads.firstIndex(where: { $0.id == threadId }) {
                    let sourceThread = self.threads[idx]
                    threadMessages = self.generationHistory(
                        for: sourceThread,
                        reservedOutputTokens: adaptiveMaxTokens,
                        forceDirectAnswer: forceDirectAnswer
                    )
                }
                
                for msg in threadMessages {
                    let roleStr = msg.role == .user ? "user" : "model"
                    let msgText = msg.role == .user
                        ? Self.effectiveMessageText(for: msg)
                        : msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let textToSend = msgText.isEmpty ? (msg.attachedImageBase64 != nil ? "Describe this image in detail and answer any questions." : "Hello") : msgText
                    var parts: [[String: Any]] = [["text": textToSend]]
                    
                    if let imageBase64 = msg.attachedImageBase64 {
                        let (mimeType, cleanBase64) = extractMimeTypeAndBase64(from: imageBase64)
                        if !cleanBase64.isEmpty {
                            parts.append([
                                "inlineData": [
                                    "mimeType": mimeType,
                                    "data": cleanBase64
                                ]
                            ])
                        }
                    }
                    
                    // Gemini API requires strictly alternating user/model roles.
                    // Merge consecutive same-role messages into a single entry.
                    if let lastEntry = contentsArray.last,
                       let lastRole = lastEntry["role"] as? String,
                       lastRole == roleStr,
                       let lastParts = lastEntry["parts"] as? [[String: Any]] {
                        var mergedParts = lastParts
                        mergedParts.append(contentsOf: parts)
                        contentsArray[contentsArray.count - 1] = [
                            "role": roleStr,
                            "parts": mergedParts
                        ]
                    } else {
                        contentsArray.append([
                            "role": roleStr,
                            "parts": parts
                        ])
                    }
                }
                
                let combinedInstructions = self.getCombinedInstructions(
                    isToolUseEnabled: isToolUseEnabled,
                    systemInstructions: systemInstructions,
                    memoryNodes: self.globalMemoryNodes,
                    memoryEdges: self.globalMemoryEdges,
                    threadId: threadId,
                    requestText: promptText
                ) + directAnswerSystemInstruction
                var payload: [String: Any] = [
                    "contents": contentsArray,
                    "generationConfig": [
                            "temperature": forceDirectAnswer ? min(temperature, 0.3) : temperature,
                        "maxOutputTokens": adaptiveMaxTokens
                    ]
                ]

                // Use Gemini's native reasoning control whenever the selected
                // model supports it. A zero budget disables thinking on Gemini
                // 2.5 Flash-family models; other models still receive the
                // explicit system instruction assembled above.
                let effortLevel = configuredEffortLevel()
                let normalizedModel = model.lowercased()
                if normalizedModel.contains("gemini-2.5") && normalizedModel.contains("flash") {
                    let budget: Int
                    switch effortLevel {
                    case "Low": budget = 0
                    case "Medium": budget = 1024
                    case "High": budget = 4096
                    default: budget = -1
                    }
                    payload["generationConfig"] = [
                        "temperature": forceDirectAnswer ? min(temperature, 0.3) : temperature,
                        "maxOutputTokens": adaptiveMaxTokens,
                        "thinkingConfig": [
                            "thinkingBudget": budget,
                            "includeThoughts": budget != 0
                        ]
                    ]
                } else if normalizedModel.contains("gemini-3") {
                    let thinkingLevel: String
                    switch effortLevel {
                    case "Low": thinkingLevel = "minimal"
                    case "Medium": thinkingLevel = "low"
                    case "High": thinkingLevel = "medium"
                    default: thinkingLevel = "high"
                    }
                    payload["generationConfig"] = [
                        "temperature": forceDirectAnswer ? min(temperature, 0.3) : temperature,
                        "maxOutputTokens": adaptiveMaxTokens,
                        "thinkingConfig": [
                            "thinkingLevel": thinkingLevel,
                            "includeThoughts": effortLevel != "Low"
                        ]
                    ]
                }
                
                if !combinedInstructions.isEmpty {
                    payload["systemInstruction"] = [
                        "parts": [["text": combinedInstructions]]
                    ]
                }
                
                do {
                    guard !apiKey.isEmpty else {
                        throw NSError(
                            domain: "GeminiError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Gemini API Key is empty. Click the 'Configure' slider icon at the top right of this chat to enter your API key."]
                        )
                    }
                    
                    guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)") else {
                        throw URLError(.badURL)
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, response) = try await networkSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    
                    if httpResponse.statusCode != 200 {
                        var bodyText = ""
                        for try await line in bytes.lines {
                            bodyText += line + "\n"
                        }
                        
                        // Retry once with backoff for transient errors (429, 503, 504)
                        let retryableCodes: Set<Int> = [429, 503, 504]
                        if retryableCodes.contains(httpResponse.statusCode) {
                            let backoff: UInt64 = httpResponse.statusCode == 429 ? 2_000_000_000 : 1_000_000_000
                            try await Task.sleep(nanoseconds: backoff)
                            if !Task.isCancelled {
                                let (retryBytes, retryResp) = try await networkSession.bytes(for: request)
                                if let retryHTTP = retryResp as? HTTPURLResponse, retryHTTP.statusCode == 200 {
                                    // Retry succeeded — stream from the retry response
                                    var responseText = ""
                                    var isFirstChunk = true
                                    
                                    let hitOutputLimit = try await self.parseAndStreamGeminiSSE(bytes: retryBytes) { chunkText in
                                        if isFirstChunk {
                                            responseText = ""
                                            isFirstChunk = false
                                        }
                                        responseText += chunkText
                                        self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: responseText, saveToDisk: false)
                                    }
                                    
                                    if !Task.isCancelled {
                                        self.saveThreads()
                                        if isToolUseEnabled && self.isPrePromptEnabled("tool_schemas") {
                                            self.checkForToolRequest(threadId: threadId, messageId: assistantMessageId)
                                        } else {
                                            self.controller(for: threadId).complete()
                                        }
                                    }
                                    return
                                }
                            }
                        }
                        
                        var errorDetail = ""
                        if let data = bodyText.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorObj = json["error"] as? [String: Any],
                           let message = errorObj["message"] as? String {
                            errorDetail = " Details: \(message)"
                        } else if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            errorDetail = " Details: \(bodyText)"
                        }
                        
                        let isRetryable = httpResponse.statusCode == 429 || httpResponse.statusCode == 503
                        let friendlyPrefix = isRetryable ? "The Gemini API is temporarily overloaded (HTTP \(httpResponse.statusCode)). Please try again in a moment." : "Gemini API returned status code \(httpResponse.statusCode)."
                        throw NSError(
                            domain: "GeminiError",
                            code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "\(friendlyPrefix)\(errorDetail)"]
                        )
                    }
                    
                    var responseText = ""
                    var isFirstChunk = true
                    
                    let hitOutputLimit = try await self.parseAndStreamGeminiSSE(bytes: bytes) { chunkText in
                        if isFirstChunk {
                            responseText = ""
                            isFirstChunk = false
                        }
                        responseText += chunkText
                        self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: responseText, saveToDisk: false)
                    }
                    
                    if Task.isCancelled { return }
                    
                    if isFirstChunk {
                        self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: "Received empty response from Gemini API.", saveToDisk: true)
                        self.controller(for: threadId).fail()
                    } else {
                        self.saveThreads()
                        if forceDirectAnswer {
                            self.finalizeDirectAnswerRecovery(threadId: threadId, messageId: assistantMessageId)
                        } else if isToolUseEnabled && self.isPrePromptEnabled("tool_schemas") {
                            self.checkForToolRequest(threadId: threadId, messageId: assistantMessageId)
                        } else {
                            self.controller(for: threadId).complete()
                        }
                        let isExecutingTool = self.controller(for: threadId).activeRun?.state == .executingTool
                        if hitOutputLimit && !forceDirectAnswer && !isExecutingTool && self.activeGenerationIDs[threadId] == generationID {
                            await self.continueAfterOutputLimit(threadId: threadId)
                        }
                    }
                    self.toolRequestManager.finishProcessing(threadId: threadId)
                } catch {
                    print("Error streaming from Gemini: \(error)")
                    self.controller(for: threadId).fail()
                    self.toolRequestManager.finishProcessing(threadId: threadId)
                    if !Task.isCancelled {
                        DispatchQueue.main.async { self.errorMessage = "Gemini error: \(error.localizedDescription)" }
                        self.updateAssistantMessage(
                            threadId: threadId,
                            messageId: assistantMessageId,
                            text: "Failed to query Gemini. Details: \(error.localizedDescription)\n\nPlease check your internet connection and Gemini API Key configuration."
                        )
                    }
                }
            } else if provider == .mlx {
                // --- APPLE MLX DIRECT IN-PROCESS METAL GENERATION ---
                let localModel = self.mlxScanner.models.first(where: { $0.id == mlxModelId || $0.path == mlxModelId || $0.name == mlxModelId }) ?? self.mlxScanner.models.first
                
                var threadMessages: [ChatMessage] = []
                if let idx = self.threads.firstIndex(where: { $0.id == threadId }) {
                    let sourceThread = self.threads[idx]
                    threadMessages = self.generationHistory(
                        for: sourceThread,
                        reservedOutputTokens: adaptiveMaxTokens,
                        forceDirectAnswer: forceDirectAnswer
                    )
                }
                
                if let model = localModel, model.isMLXNative {
                    do {
                        self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: "")
                        var accumulated = ""
                        
                        let _ = try await InProcessMLXEngine.shared.generateStream(
                            prompt: promptText,
                            messages: threadMessages,
                            modelPath: model.path,
                            modelDisplayName: model.displayName,
                            maxTokens: adaptiveMaxTokens,
                            temperature: Float(temperature)
                        ) { chunk in
                            accumulated += chunk
                            self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: accumulated)
                        }
                        
                        self.saveThreads()
                        if forceDirectAnswer {
                            self.finalizeDirectAnswerRecovery(threadId: threadId, messageId: assistantMessageId)
                        } else if isToolUseEnabled && self.isPrePromptEnabled("tool_schemas") {
                            self.checkForToolRequest(threadId: threadId, messageId: assistantMessageId)
                        } else {
                            self.controller(for: threadId).complete()
                        }
                        self.toolRequestManager.finishProcessing(threadId: threadId)
                        return
                    } catch {
                        print("Direct MLX in-process inference failed, trying fallback server: \(error)")
                    }
                }
                
                // Fallback to local server if direct inference could not load model or model is non-native
                let baseURL = self.mlxBaseURL
                let modelId = mlxModelId ?? self.mlxModelId ?? self.mlxScanner.models.first?.id ?? "default"
            } else if provider == .lmStudio {
                // --- LM STUDIO LOCAL SERVER GENERATION ---
                let baseURL = self.lmStudioBaseURL
                let modelId = lmStudioModelId ?? self.lmStudioAvailableModels.first ?? "default"
                
                var threadMessages: [ChatMessage] = []
                if let idx = self.threads.firstIndex(where: { $0.id == threadId }) {
                    let sourceThread = self.threads[idx]
                    threadMessages = self.generationHistory(
                        for: sourceThread,
                        reservedOutputTokens: adaptiveMaxTokens,
                        forceDirectAnswer: forceDirectAnswer
                    )
                }
                
                let combinedInstructions = self.getCombinedInstructions(
                    isToolUseEnabled: isToolUseEnabled,
                    systemInstructions: systemInstructions,
                    memoryNodes: self.globalMemoryNodes,
                    memoryEdges: self.globalMemoryEdges,
                    threadId: threadId,
                    requestText: promptText
                ) + directAnswerSystemInstruction
                let localToolProtocol = self.localModelToolProtocol(isToolUseEnabled: isToolUseEnabled)
                
                func createLMStudioMessages(includeImages: Bool, imageAnalysis: String? = nil) -> [[String: Any]] {
                    var msgs: [[String: Any]] = []
                    let localInstructions = combinedInstructions + localToolProtocol
                    if !localInstructions.isEmpty {
                        msgs.append(["role": "system", "content": localInstructions])
                    }
                    
                    let lastUserIndex = threadMessages.lastIndex(where: { $0.role == .user }) ?? -1
                    for (index, msg) in threadMessages.enumerated() {
                        let roleStr = msg.role == .user ? "user" : "assistant"
                        // Do not send previous private reasoning back to the model.
                        let msgText = msg.role == .assistant
                            ? Self.assistantDisplayText(from: msg.text).trimmingCharacters(in: .whitespacesAndNewlines)
                            : Self.effectiveMessageText(for: msg)
                        
                        // Keep assistant tool requests in history so local models retain turn context and know which tool call produced the incoming response.
                        
                        var textToSend = msgText.isEmpty ? (msg.attachedImageBase64 != nil ? "Describe this image in detail and answer any questions." : "") : msgText
                        if index == lastUserIndex,
                           msg.role == .user,
                           msg.attachedImageBase64 != nil,
                           let imageAnalysis,
                           !imageAnalysis.isEmpty {
                            textToSend += "\n\n[IMAGE ANALYSIS FALLBACK: The selected local model rejected direct image input. A vision-capable model analyzed the attached image as follows:\n\(imageAnalysis)\nUse this description without inventing visual details.]"
                        }
                        if textToSend.isEmpty || textToSend == "..." { continue }
                        
                        if includeImages, let imageBase64 = msg.attachedImageBase64, !imageBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let (mimeType, cleanBase64) = self.extractMimeTypeAndBase64(from: imageBase64)
                            if !cleanBase64.isEmpty {
                                let dataUrl = "data:\(mimeType);base64,\(cleanBase64)"
                                let content: [[String: Any]] = [
                                    ["type": "text", "text": textToSend],
                                    ["type": "image_url", "image_url": ["url": dataUrl]]
                                ]
                                msgs.append(["role": roleStr, "content": content])
                            } else {
                                msgs.append(["role": roleStr, "content": textToSend])
                            }
                        } else {
                            // Merge consecutive same-role messages for strict user/assistant role alternation
                            if let lastRole = msgs.last?["role"] as? String, lastRole == roleStr, lastRole != "system" {
                                if let lastContent = msgs.last?["content"] as? String {
                                    msgs[msgs.count - 1]["content"] = lastContent + "\n\n" + textToSend
                                } else {
                                    msgs.append(["role": roleStr, "content": textToSend])
                                }
                            } else {
                                msgs.append(["role": roleStr, "content": textToSend])
                            }
                        }
                    }
                    return msgs
                }
                
                func performLMStudioRequest(includeImages: Bool, imageAnalysis: String? = nil) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
                    guard let url = URL(string: "\(baseURL)/chat/completions") else {
                        throw URLError(.badURL)
                    }
                    
                    var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 300)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    var payload: [String: Any] = [
                        "model": modelId,
                        "messages": createLMStudioMessages(includeImages: includeImages, imageAnalysis: imageAnalysis),
                        "temperature": forceDirectAnswer ? min(temperature, 0.3) : temperature,
                        "max_tokens": adaptiveMaxTokens,
                        "stream": true
                    ]
                    // LM Studio reasoning-capable models may otherwise use
                    // their model default when the field is omitted. Send an
                    // explicit off value so the composer Think pill is a real
                    // request-level control; Effort supplies the intensity
                    // whenever thinking is enabled.
                    payload["reasoning_effort"] = providerReasoningEnabled
                        ? providerReasoningEffort
                        : "none"
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, response) = try await networkSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    return (bytes, httpResponse)
                }
                
                do {
                    var includeImages = threadMessages.contains(where: {
                        if let img = $0.attachedImageBase64 {
                            return !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        return false
                    })
                    
                    var (bytes, httpResponse): (URLSession.AsyncBytes, HTTPURLResponse)
                    
                    do {
                        let res = try await performLMStudioRequest(includeImages: includeImages)
                        bytes = res.0
                        httpResponse = res.1
                    } catch {
                        if includeImages {
                            print("LM Studio vision request failed/timed out, preparing a text-grounded fallback...")
                            let lastFrame = threadMessages.last(where: { $0.role == .user && $0.attachedImageBase64 != nil })?.attachedImageBase64
                            let analysis: String?
                            if let lastFrame {
                                analysis = await self.preAnalyzeImageWithVision(imageBase64: lastFrame)
                            } else {
                                analysis = nil
                            }
                            includeImages = false
                            let res = try await performLMStudioRequest(includeImages: false, imageAnalysis: analysis)
                            bytes = res.0
                            httpResponse = res.1
                        } else {
                            throw error
                        }
                    }

                    if httpResponse.statusCode != 200 && includeImages {
                        // LM Studio commonly reports unsupported multimodal
                        // input as an HTTP error rather than a transport error.
                        // Consume the failed response before issuing one
                        // capability fallback request.
                        for try await _ in bytes.lines { }
                        let lastFrame = threadMessages.last(where: { $0.role == .user && $0.attachedImageBase64 != nil })?.attachedImageBase64
                        let analysis: String?
                        if let lastFrame {
                            analysis = await self.preAnalyzeImageWithVision(imageBase64: lastFrame)
                        } else {
                            analysis = nil
                        }
                        includeImages = false
                        let fallback = try await performLMStudioRequest(includeImages: false, imageAnalysis: analysis)
                        bytes = fallback.0
                        httpResponse = fallback.1
                    }
                    
                    if httpResponse.statusCode != 200 {
                        throw NSError(
                            domain: "LMStudioError",
                            code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"]
                        )
                    }
                    
                    var responseText = ""
                    var isFirstChunk = true
                    
                    let hitOutputLimit = try await self.parseAndStreamSSE(bytes: bytes) { chunkText in
                        if isFirstChunk {
                            responseText = ""
                            isFirstChunk = false
                        }
                        responseText += chunkText
                        self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: responseText, saveToDisk: false)
                    }
                    
                    if Task.isCancelled { return }
                    
                    if isFirstChunk {
                        self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: "Received empty response from LM Studio.", saveToDisk: true)
                        self.controller(for: threadId).fail()
                    } else {
                        self.saveThreads()
                        if forceDirectAnswer {
                            self.finalizeDirectAnswerRecovery(threadId: threadId, messageId: assistantMessageId)
                        } else if isToolUseEnabled && self.isPrePromptEnabled("tool_schemas") {
                            self.checkForToolRequest(threadId: threadId, messageId: assistantMessageId)
                        } else {
                            self.controller(for: threadId).complete()
                        }
                        let isExecutingTool = self.controller(for: threadId).activeRun?.state == .executingTool
                        if hitOutputLimit && !forceDirectAnswer && !isExecutingTool && self.activeGenerationIDs[threadId] == generationID {
                            await self.continueAfterOutputLimit(threadId: threadId)
                        }
                    }
                    self.toolRequestManager.finishProcessing(threadId: threadId)
                } catch {
                    let isMLX = provider == .mlx
                    let providerLabel = isMLX ? "Apple MLX" : "LM Studio"
                    print("Error streaming from \(providerLabel): \(error)")
                    self.controller(for: threadId).fail()
                    self.toolRequestManager.finishProcessing(threadId: threadId)
                    if !Task.isCancelled {
                        var errorMsg = error.localizedDescription
                        if errorMsg.contains("timed out") || errorMsg.contains("time out") {
                            errorMsg = "The request to \(providerLabel) timed out. This usually happens if the model doesn't support vision/images, or if local inference is taking a long time.\n\nTips:\n- Ensure the model is loaded properly.\n- Or switch to Gemini, OpenRouter, or OpenAI."
                        }
                        DispatchQueue.main.async { self.errorMessage = "\(providerLabel) error: \(errorMsg)" }
                        let helpText = isMLX
                            ? "Please check that your Apple MLX server (mlx_lm.server) is running at \(baseURL)."
                            : "Please check that your LM Studio Local Server is running at \(baseURL) and has an active model loaded."
                        self.updateAssistantMessage(
                            threadId: threadId,
                            messageId: assistantMessageId,
                            text: "Failed to query \(providerLabel).\n\n\(errorMsg)\n\n\(helpText)"
                        )
                    }
                }
            } else if provider == .openRouter {
                // --- OPENROUTER API GENERATION ---
                let apiKey = self.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let requestedModel = openRouterModelId ?? "google/gemini-2.0-flash-001"
                
                var threadMessages: [ChatMessage] = []
                if let idx = self.threads.firstIndex(where: { $0.id == threadId }) {
                    let sourceThread = self.threads[idx]
                    threadMessages = self.generationHistory(
                        for: sourceThread,
                        reservedOutputTokens: adaptiveMaxTokens,
                        forceDirectAnswer: forceDirectAnswer
                    )
                }
                
                let combinedInstructions = self.getCombinedInstructions(
                    isToolUseEnabled: isToolUseEnabled,
                    systemInstructions: systemInstructions,
                    memoryNodes: self.globalMemoryNodes,
                    memoryEdges: self.globalMemoryEdges,
                    threadId: threadId,
                    requestText: promptText
                ) + directAnswerSystemInstruction
                
                func createOpenAIMessages(includeImages: Bool, imageAnalysis: String? = nil) -> [[String: Any]] {
                    var msgs: [[String: Any]] = []
                    if !combinedInstructions.isEmpty {
                        msgs.append(["role": "system", "content": combinedInstructions])
                    }
                    
                    let lastUserIndex = threadMessages.lastIndex(where: { $0.role == .user }) ?? -1
                    
                    for (idx, msg) in threadMessages.enumerated() {
                        let roleStr = msg.role == .user ? "user" : "assistant"
                        let msgText = msg.role == .assistant
                            ? Self.assistantDisplayText(from: msg.text).trimmingCharacters(in: .whitespacesAndNewlines)
                            : Self.effectiveMessageText(for: msg)
                        var textToSend = msgText.isEmpty ? (msg.attachedImageBase64 != nil ? "Describe this image in detail and answer any questions." : "") : msgText
                        if textToSend.isEmpty || textToSend == "..." { continue }
                        
                        if idx == lastUserIndex, let analysis = imageAnalysis, msg.role == .user, msg.attachedImageBase64 != nil {
                            textToSend = "[Attached Image Description: \(analysis)]\n\nUser Message: \(textToSend)"
                        }
                        
                        if includeImages, idx == lastUserIndex, let imageBase64 = msg.attachedImageBase64, !imageBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let (mimeType, cleanBase64) = self.extractMimeTypeAndBase64(from: imageBase64)
                            if !cleanBase64.isEmpty {
                                let dataUrl = "data:\(mimeType);base64,\(cleanBase64)"
                                let content: [[String: Any]] = [
                                    ["type": "text", "text": textToSend],
                                    ["type": "image_url", "image_url": ["url": dataUrl]]
                                ]
                                msgs.append(["role": roleStr, "content": content])
                            } else {
                                msgs.append(["role": roleStr, "content": textToSend])
                            }
                        } else {
                            msgs.append(["role": roleStr, "content": textToSend])
                        }
                    }
                    return msgs
                }
                
                func performOpenRouterRequest(modelToUse: String, includeImages: Bool, imageAnalysis: String? = nil, maxTokens: Int? = nil) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
                    guard !apiKey.isEmpty else {
                        throw NSError(
                            domain: "OpenRouterError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "OpenRouter API Key is empty. Click the 'Configure' slider icon at the top right of this chat to enter your API key."]
                        )
                    }
                    
                    guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
                        throw URLError(.badURL)
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("http://appleint.app", forHTTPHeaderField: "HTTP-Referer")
                    request.setValue("appleint", forHTTPHeaderField: "X-Title")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    var payload: [String: Any] = [
                        "model": modelToUse,
                        "messages": createOpenAIMessages(includeImages: includeImages, imageAnalysis: imageAnalysis),
                        "temperature": temperature,
                        "stream": true
                    ]
                    payload["max_tokens"] = maxTokens ?? adaptiveMaxTokens
                    if modelToUse.lowercased().contains("reasoning") ||
                       modelToUse.lowercased().contains("deepseek-r1") ||
                       modelToUse.lowercased().contains("qwen") {
                        payload["reasoning"] = ["effort": providerReasoningEffort]
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, response) = try await networkSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    return (bytes, httpResponse)
                }
                
                do {
                    var modelToUse = requestedModel
                    let currentMessageHasImage: Bool = {
                        if let lastUserMsg = threadMessages.last(where: { $0.role == .user }),
                           let img = lastUserMsg.attachedImageBase64 {
                            return !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        return false
                    }()
                    let includeImages = currentMessageHasImage
                    
                    var (bytes, httpResponse) = try await performOpenRouterRequest(modelToUse: modelToUse, includeImages: includeImages)
                    
                    // Handle failures with automatic fallback retries
                    if httpResponse.statusCode != 200 {
                        var bodyText = ""
                        for try await line in bytes.lines {
                            bodyText += line + "\n"
                        }
                        
                        let lowerBody = bodyText.lowercased()
                        let isVisionError = lowerBody.contains("image input") || lowerBody.contains("vision") || lowerBody.contains("image") || lowerBody.contains("no endpoints found")
                        let is404 = httpResponse.statusCode == 404
                        let is402 = httpResponse.statusCode == 402
                        
                        var retriedSuccess = false
                        
                        // Retry 1: Selected model lacks vision support. Pre-analyze image with Gemini vision, pass image description to selected model!
                        if (isVisionError || is404 || httpResponse.statusCode == 400) && includeImages {
                            if let lastImageMsg = threadMessages.last(where: { $0.attachedImageBase64 != nil }),
                               let imgBase64 = lastImageMsg.attachedImageBase64 {
                                print("Selected model \(modelToUse) lacks vision support. Running Gemini vision pre-analysis pass...")
                                if let analysis = await preAnalyzeImageWithVision(imageBase64: imgBase64) {
                                    print("Gemini vision analysis obtained. Retrying with selected model \(modelToUse)...")
                                    let (retryBytes, retryResponse) = try await performOpenRouterRequest(
                                        modelToUse: modelToUse,
                                        includeImages: false,
                                        imageAnalysis: analysis
                                    )
                                    if retryResponse.statusCode == 200 {
                                        bytes = retryBytes
                                        httpResponse = retryResponse
                                        retriedSuccess = true
                                    } else {
                                        var bodyText2 = ""
                                        for try await line in retryBytes.lines {
                                            bodyText2 += line + "\n"
                                        }
                                        bodyText = bodyText2
                                    }
                                }
                            }
                            
                            // Retry 1b: If pre-analysis failed, fallback to free Gemini vision model directly
                            if !retriedSuccess {
                                let fallbackVisionModels = ["google/gemini-2.0-flash-exp:free", "google/gemini-2.0-flash-001", "google/gemma-4-26b-a4b-it:free"]
                                for fallbackModel in fallbackVisionModels {
                                    if fallbackModel == modelToUse { continue }
                                    print("Retrying vision request with fallback vision model: \(fallbackModel)")
                                    let (retryBytes, retryResponse) = try await performOpenRouterRequest(modelToUse: fallbackModel, includeImages: true)
                                    if retryResponse.statusCode == 200 {
                                        bytes = retryBytes
                                        httpResponse = retryResponse
                                        retriedSuccess = true
                                        break
                                    } else {
                                        var bodyText3 = ""
                                        for try await line in retryBytes.lines {
                                            bodyText3 += line + "\n"
                                        }
                                        bodyText = bodyText3
                                    }
                                }
                            }
                        }
                        
                        // Retry 2: If non-image request returned 404, retry with default model
                        if !retriedSuccess && is404 && modelToUse != "google/gemini-2.0-flash-001" {
                            modelToUse = "google/gemini-2.0-flash-001"
                            let (retryBytes, retryResponse) = try await performOpenRouterRequest(modelToUse: modelToUse, includeImages: includeImages)
                            if retryResponse.statusCode == 200 {
                                bytes = retryBytes
                                httpResponse = retryResponse
                                retriedSuccess = true
                            } else {
                                var bodyText3 = ""
                                for try await line in retryBytes.lines {
                                    bodyText3 += line + "\n"
                                }
                                bodyText = bodyText3
                            }
                        }
                        
                        // Retry 3: ResourceExhausted, Timeout, Rate Limit, 503, 504, 429
                        let isRateLimit = lowerBody.contains("resourceexhausted") || lowerBody.contains("request limit") || lowerBody.contains("rate limit") || lowerBody.contains("overloaded") || lowerBody.contains("timed out") || lowerBody.contains("timeout") || httpResponse.statusCode == 429 || httpResponse.statusCode == 503 || httpResponse.statusCode == 504
                        if !retriedSuccess && (isRateLimit || is404 || httpResponse.statusCode >= 500) {
                            let capacityFallbacks = ["google/gemini-2.0-flash-exp:free", "meta-llama/llama-3.3-70b-instruct:free", "google/gemini-2.0-flash-001"]
                            for fallbackModel in capacityFallbacks {
                                if fallbackModel == modelToUse { continue }
                                print("Selected model \(modelToUse) hit timeout/capacity limit. Trying fallback: \(fallbackModel)...")
                                if let (retryBytes, retryResponse) = try? await performOpenRouterRequest(modelToUse: fallbackModel, includeImages: includeImages), retryResponse.statusCode == 200 {
                                    bytes = retryBytes
                                    httpResponse = retryResponse
                                    retriedSuccess = true
                                    modelToUse = fallbackModel
                                    break
                                }
                            }
                        }
                        
                        if !retriedSuccess && httpResponse.statusCode != 200 {
                            var errorDetail = ""
                            if let data = bodyText.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let errorObj = json["error"] as? [String: Any],
                               let message = errorObj["message"] as? String {
                                errorDetail = message
                            } else if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                errorDetail = bodyText
                            }
                            
                            if is402 {
                                throw NSError(
                                    domain: "OpenRouterError",
                                    code: 402,
                                    userInfo: [NSLocalizedDescriptionKey: "OpenRouter account credit limit reached for paid model \(modelToUse).\n\n\(errorDetail)\n\nTips:\n- Switch to a FREE model in the top model picker (marked with 🟢 [FREE], such as google/gemini-2.0-flash-exp:free or meta-llama/llama-3.3-70b-instruct:free).\n- Or add credits at https://openrouter.ai/settings/credits"]
                                )
                            } else {
                                let isTimeout = errorDetail.lowercased().contains("timed out") || errorDetail.lowercased().contains("timeout")
                                let friendlyMsg = isTimeout ? "The selected AI model provider timed out. Please try sending your message again or switch to Gemini 2.0 Flash in the top model picker." : (errorDetail.contains("ResourceExhausted") ? "Nvidia / OpenRouter servers are currently experiencing high traffic (Resource Limit Reached). Please select another model in the top model picker." : "OpenRouter API returned status code \(httpResponse.statusCode). Details: \(errorDetail)")
                                throw NSError(
                                    domain: "OpenRouterError",
                                    code: httpResponse.statusCode,
                                    userInfo: [NSLocalizedDescriptionKey: friendlyMsg]
                                )
                            }
                        }
                    }
                    
                    var responseText = ""
                    var isFirstChunk = true
                    var hitOutputLimit = false
                    
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmedLine.hasPrefix("data:") else { continue }
                        let dataStr = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        if dataStr == "[DONE]" { break }
                        guard let data = dataStr.data(using: .utf8) else { continue }
                        
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let errorObj = json["error"] as? [String: Any],
                               let message = errorObj["message"] as? String {
                                
                                let lowerMsg = message.lowercased()
                                let isCapExhausted = lowerMsg.contains("resourceexhausted") || lowerMsg.contains("request limit") || lowerMsg.contains("rate limit") || lowerMsg.contains("overloaded") || lowerMsg.contains("timed out") || lowerMsg.contains("timeout")
                                
                                if isCapExhausted && isFirstChunk {
                                    print("In-stream timeout or capacity limit hit for \(modelToUse). Attempting fallback...")
                                    let capacityFallbacks = ["google/gemini-2.0-flash-exp:free", "meta-llama/llama-3.3-70b-instruct:free", "google/gemini-2.0-flash-001"]
                                    var streamFallbackSuccess = false
                                    for fallbackModel in capacityFallbacks {
                                        if fallbackModel == modelToUse { continue }
                                        if let (fallbackBytes, fallbackResponse) = try? await performOpenRouterRequest(modelToUse: fallbackModel, includeImages: includeImages), fallbackResponse.statusCode == 200 {
                                            var fbResponseText = ""
                                            var fbFirstChunk = true
                                            for try await fbLine in fallbackBytes.lines {
                                                if Task.isCancelled { break }
                                                let fbTrimmed = fbLine.trimmingCharacters(in: .whitespacesAndNewlines)
                                                guard fbTrimmed.hasPrefix("data:") else { continue }
                                                let fbDataStr = fbTrimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                                                if fbDataStr == "[DONE]" { break }
                                                guard let fbData = fbDataStr.data(using: .utf8) else { continue }
                                                if let fbJson = try? JSONSerialization.jsonObject(with: fbData) as? [String: Any],
                                                   let fbChoices = fbJson["choices"] as? [[String: Any]],
                                                   let fbFirst = fbChoices.first,
                                                   let fbDelta = fbFirst["delta"] as? [String: Any],
                                                   let fbContent = fbDelta["content"] as? String {
                                                    if fbFirstChunk {
                                                        fbResponseText = ""
                                                        fbFirstChunk = false
                                                    }
                                                    fbResponseText += fbContent
                                                    self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: fbResponseText)
                                                }
                                            }
                                            if !fbFirstChunk {
                                                streamFallbackSuccess = true
                                                responseText = fbResponseText
                                                isFirstChunk = false
                                                break
                                            }
                                        }
                                    }
                                    if streamFallbackSuccess { break }
                                }
                                
                                let isTimeout = lowerMsg.contains("timed out") || lowerMsg.contains("timeout")
                                let friendlyMsg = isTimeout ? "The selected AI model provider timed out. Please try sending your message again or switch to Gemini 2.0 Flash in the top model picker." : (message.contains("ResourceExhausted") ? "Nvidia / OpenRouter servers are currently experiencing high traffic (Resource Limit Reached). Please select another free model like Gemini 2.0 Flash or Llama 3.3 in the top model picker." : "OpenRouter Stream Error: \(message)")
                                responseText = friendlyMsg
                                self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: responseText)
                                isFirstChunk = false
                                break
                            }
                            
                            if let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first {
                                if let reason = first["finish_reason"] as? String,
                                   ["length", "max_tokens"].contains(reason.lowercased()) {
                                    hitOutputLimit = true
                                }
                                guard let delta = first["delta"] as? [String: Any],
                                      let content = delta["content"] as? String else { continue }
                                
                                if isFirstChunk {
                                    responseText = ""
                                    isFirstChunk = false
                                }
                                responseText += content
                                
                                self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: responseText)
                            }
                        }
                    }
                    
                    if Task.isCancelled { return }
                    
                    if isFirstChunk {
                        self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: "Received empty response from OpenRouter.", saveToDisk: true)
                        self.controller(for: threadId).fail()
                    } else {
                        self.saveThreads()
                        if forceDirectAnswer {
                            self.finalizeDirectAnswerRecovery(threadId: threadId, messageId: assistantMessageId)
                        } else if isToolUseEnabled && self.isPrePromptEnabled("tool_schemas") {
                            self.checkForToolRequest(threadId: threadId, messageId: assistantMessageId)
                        } else {
                            self.controller(for: threadId).complete()
                        }
                        let isExecutingTool = self.controller(for: threadId).activeRun?.state == .executingTool
                        if hitOutputLimit && !forceDirectAnswer && !isExecutingTool && self.activeGenerationIDs[threadId] == generationID {
                            await self.continueAfterOutputLimit(threadId: threadId)
                        }
                    }
                    self.toolRequestManager.finishProcessing(threadId: threadId)
                } catch {
                    print("Error streaming from OpenRouter: \(error)")
                    self.controller(for: threadId).fail()
                    self.toolRequestManager.finishProcessing(threadId: threadId)
                    if !Task.isCancelled {
                        DispatchQueue.main.async { self.errorMessage = "OpenRouter error: \(error.localizedDescription)" }
                        self.updateAssistantMessage(
                            threadId: threadId,
                            messageId: assistantMessageId,
                            text: "Failed to query OpenRouter. Details: \(error.localizedDescription)\n\nPlease check your internet connection and OpenRouter API Key configuration."
                        )
                    }
                }
            } else if provider == .openAI {
                // --- OPENAI API GENERATION ---
                let apiKey = self.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let requestedModel = openAIModelId
                
                var threadMessages: [ChatMessage] = []
                if let idx = self.threads.firstIndex(where: { $0.id == threadId }) {
                    let sourceThread = self.threads[idx]
                    threadMessages = self.generationHistory(
                        for: sourceThread,
                        reservedOutputTokens: adaptiveMaxTokens,
                        forceDirectAnswer: forceDirectAnswer
                    )
                }
                
                let combinedInstructions = self.getCombinedInstructions(
                    isToolUseEnabled: isToolUseEnabled,
                    systemInstructions: systemInstructions,
                    memoryNodes: self.globalMemoryNodes,
                    memoryEdges: self.globalMemoryEdges,
                    threadId: threadId,
                    requestText: promptText
                ) + directAnswerSystemInstruction
                
                func createOpenAIMessages(includeImages: Bool, imageAnalysis: String? = nil) -> [[String: Any]] {
                    var msgs: [[String: Any]] = []
                    if !combinedInstructions.isEmpty {
                        msgs.append(["role": "system", "content": combinedInstructions])
                    }
                    
                    let lastUserIndex = threadMessages.lastIndex(where: { $0.role == .user }) ?? -1
                    for (index, msg) in threadMessages.enumerated() {
                        let roleStr = msg.role == .user ? "user" : "assistant"
                        let msgText = msg.role == .user
                            ? Self.effectiveMessageText(for: msg)
                            : msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        var textToSend = msgText.isEmpty ? (msg.attachedImageBase64 != nil ? "Describe this image in detail and answer any questions." : "Hello") : msgText
                        if index == lastUserIndex,
                           msg.role == .user,
                           msg.attachedImageBase64 != nil,
                           let imageAnalysis,
                           !imageAnalysis.isEmpty {
                            textToSend += "\n\n[IMAGE ANALYSIS FALLBACK: Direct image input was rejected. A vision-capable model analyzed the attached image as follows:\n\(imageAnalysis)\nUse this description without inventing visual details.]"
                        }
                        
                        if includeImages, let imageBase64 = msg.attachedImageBase64, !imageBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let (mimeType, cleanBase64) = self.extractMimeTypeAndBase64(from: imageBase64)
                            if !cleanBase64.isEmpty {
                                let dataUrl = "data:\(mimeType);base64,\(cleanBase64)"
                                let content: [[String: Any]] = [
                                    ["type": "text", "text": textToSend],
                                    ["type": "image_url", "image_url": ["url": dataUrl]]
                                ]
                                msgs.append(["role": roleStr, "content": content])
                            } else {
                                msgs.append(["role": roleStr, "content": textToSend])
                            }
                        } else {
                            msgs.append(["role": roleStr, "content": textToSend])
                        }
                    }
                    return msgs
                }
                
                func performOpenAIRequest(modelToUse: String, includeImages: Bool, imageAnalysis: String? = nil) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
                    guard !apiKey.isEmpty else {
                        throw NSError(
                            domain: "OpenAIError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "OpenAI API Key is empty. Click App Settings to enter your OpenAI API key."]
                        )
                    }
                    
                    var cleanBase = configuredOpenAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanBase.hasSuffix("/") {
                        cleanBase = String(cleanBase.dropLast())
                    }
                    if cleanBase.isEmpty {
                        cleanBase = "https://api.openai.com/v1"
                    }
                    
                    guard let url = URL(string: "\(cleanBase)/chat/completions") else {
                        throw URLError(.badURL)
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    var payload: [String: Any] = [
                        "model": modelToUse,
                        "messages": createOpenAIMessages(includeImages: includeImages, imageAnalysis: imageAnalysis),
                        "stream": true
                    ]
                    if cleanBase.lowercased().contains("openrouter") {
                        payload["include_reasoning"] = true
                    }
                    if !modelToUse.hasPrefix("o1") && !modelToUse.hasPrefix("o3") {
                        payload["temperature"] = temperature
                    }
                    payload["max_tokens"] = adaptiveMaxTokens
                    let lowerModel = modelToUse.lowercased()
                    if lowerModel.hasPrefix("o1") || lowerModel.hasPrefix("o3") ||
                       lowerModel.hasPrefix("o4") || lowerModel.hasPrefix("gpt-5") {
                        payload["reasoning_effort"] = providerReasoningEffort
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, response) = try await networkSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    return (bytes, httpResponse)
                }
                
                do {
                    let modelToUse = requestedModel
                    let includeImages = threadMessages.contains(where: {
                        if let img = $0.attachedImageBase64 {
                            return !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        return false
                    })
                    
                    var (bytes, httpResponse) = try await performOpenAIRequest(modelToUse: modelToUse, includeImages: includeImages)
                    
                    if httpResponse.statusCode != 200 {
                        var bodyText = ""
                        for try await line in bytes.lines {
                            bodyText += line + "\n"
                        }
                        
                        let lowerBody = bodyText.lowercased()
                        let isVisionError = lowerBody.contains("image") || lowerBody.contains("vision") || lowerBody.contains("unsupported") || lowerBody.contains("invalid_request_error")
                        
                        if isVisionError && includeImages {
                            // Retry with vision model (gpt-4o) with images intact
                            let fallbackModel = "gpt-4o"
                            if modelToUse != fallbackModel {
                                print("Retrying OpenAI vision request with fallback model: \(fallbackModel)")
                                let (retryBytes, retryResponse) = try await performOpenAIRequest(modelToUse: fallbackModel, includeImages: true)
                                if retryResponse.statusCode == 200 {
                                    bytes = retryBytes
                                    httpResponse = retryResponse
                                } else {
                                    var bodyText2 = ""
                                    for try await line in retryBytes.lines {
                                        bodyText2 += line + "\n"
                                    }
                                    bodyText = bodyText2
                                }
                            }
                        }

                        if httpResponse.statusCode != 200 && includeImages,
                           let lastImage = threadMessages.last(where: { $0.role == .user && $0.attachedImageBase64 != nil })?.attachedImageBase64 {
                            let analysis = await self.preAnalyzeImageWithVision(imageBase64: lastImage)
                            if let analysis {
                                let textFallback = try await performOpenAIRequest(
                                    modelToUse: modelToUse,
                                    includeImages: false,
                                    imageAnalysis: analysis
                                )
                                if textFallback.1.statusCode == 200 {
                                    bytes = textFallback.0
                                    httpResponse = textFallback.1
                                }
                            }
                        }
                        
                        if httpResponse.statusCode != 200 {
                            if let data = bodyText.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let err = json["error"] as? [String: Any],
                               let msg = err["message"] as? String {
                                throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
                            } else {
                                throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI returned status code \(httpResponse.statusCode)"])
                            }
                        }
                    }
                    
                    var responseText = ""
                    var isFirstChunk = true
                    var hitOutputLimit = false
                    
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmedLine.hasPrefix("data:") else { continue }
                        let dataStr = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        if dataStr == "[DONE]" { break }
                        guard let data = dataStr.data(using: .utf8) else { continue }
                        
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let errorObj = json["error"] as? [String: Any],
                               let message = errorObj["message"] as? String {
                                responseText = "OpenAI Stream Error: \(message)"
                                self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: responseText)
                                isFirstChunk = false
                                break
                            }
                            
                            if let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first {
                                if let reason = first["finish_reason"] as? String,
                                   ["length", "max_tokens"].contains(reason.lowercased()) {
                                    hitOutputLimit = true
                                }
                                guard let delta = first["delta"] as? [String: Any] else { continue }
                                
                                var chunkText = ""
                                if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
                                    chunkText += "<think>\n\(reasoning)\n</think>\n"
                                }
                                if let content = delta["content"] as? String, !content.isEmpty {
                                    chunkText += content
                                }
                                
                                if chunkText.isEmpty { continue }
                                
                                if isFirstChunk {
                                    responseText = ""
                                    isFirstChunk = false
                                }
                                responseText += chunkText
                                
                                self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: responseText)
                            }
                        }
                    }
                    
                    if Task.isCancelled { return }
                    
                    if isFirstChunk {
                        self.updateAssistantMessage(threadId: threadId, messageId: assistantMessageId, text: "Received empty response from OpenAI.", saveToDisk: true)
                        self.controller(for: threadId).fail()
                    } else {
                        self.saveThreads()
                        if forceDirectAnswer {
                            self.finalizeDirectAnswerRecovery(threadId: threadId, messageId: assistantMessageId)
                        } else if isToolUseEnabled && self.isPrePromptEnabled("tool_schemas") {
                            self.checkForToolRequest(threadId: threadId, messageId: assistantMessageId)
                        } else {
                            self.controller(for: threadId).complete()
                        }
                        let isExecutingTool = self.controller(for: threadId).activeRun?.state == .executingTool
                        if hitOutputLimit && !forceDirectAnswer && !isExecutingTool && self.activeGenerationIDs[threadId] == generationID {
                            await self.continueAfterOutputLimit(threadId: threadId)
                        }
                    }
                    self.toolRequestManager.finishProcessing(threadId: threadId)
                } catch {
                    print("Error streaming from OpenAI: \(error)")
                    self.controller(for: threadId).fail()
                    self.toolRequestManager.finishProcessing(threadId: threadId)
                    if !Task.isCancelled {
                        var userFriendlyMsg = error.localizedDescription
                        if userFriendlyMsg.contains("exceeded your current quota") || userFriendlyMsg.contains("insufficient_quota") {
                            userFriendlyMsg = "OpenAI API Quota Exceeded: Your OpenAI platform key has run out of billing quota.\n\nSolutions:\n1. Add API billing credits at platform.openai.com/account/billing\n2. Switch to OpenRouter for another hosted model\n3. Or use Gemini or a local LM Studio model."
                        }
                        DispatchQueue.main.async { self.errorMessage = "OpenAI error: \(userFriendlyMsg)" }
                        self.updateAssistantMessage(
                            threadId: threadId,
                            messageId: assistantMessageId,
                            text: "Failed to query OpenAI API.\n\n\(userFriendlyMsg)"
                        )
                    }
                }
            }
            
            // A cancelled stream can complete after a replacement begins.
            // Only the current stream may clear this thread's UI state.
            guard self.activeGenerationIDs[threadId] == generationID else { return }
            self.activeGenerationTasks[threadId] = nil
            self.activeGenerationIDs[threadId] = nil
            self.refreshGenerationState()
            await self.diagnostics.record(category: "generation", message: "finished", threadID: threadId)
        }
        self.activeGenerationTasks[threadId] = task
    }
    
    // Check if assistant message text contains a ToolRequest payload
    @MainActor
    private func checkForToolRequest(threadId: UUID, messageId: UUID) {
        guard let threadIndex = self.threads.firstIndex(where: { $0.id == threadId }),
              let msgIndex = self.threads[threadIndex].messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        let runController = controller(for: threadId)
        
        let messages = self.threads[threadIndex].messages
        var messageText = messages[msgIndex].text
        let presentationRequest = runController.activeRun?.userGoal ?? ""
        let sanitizedPresentation = Self.sanitizedAnswerPresentation(messageText, request: presentationRequest)
        if sanitizedPresentation != messageText,
           ToolRequestParser.parse(text: messageText) == nil {
            messageText = sanitizedPresentation
            self.threads[threadIndex].messages[msgIndex].text = sanitizedPresentation
            self.saveThreads()
        }
        
        // Parse both standard JSON and native local-model tool-call formats.
        // Gemma emits `<|tool_call|>call:tool_6:{...}` for terminal work.
        if var toolRequest = ToolRequestParser.parse(text: messageText) {
            // Small/local models occasionally select web search correctly but
            // omit its required `query`. Recover from that malformed call using
            // the current turn's user request instead of ending the agent loop
            // after a validation error.
            if toolRequest.type == "internet_use",
               (toolRequest.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let currentUserRequest = messages[..<msgIndex].reversed().first(where: {
                   $0.role == .user &&
                   !$0.isToolResponse &&
                   !$0.text.hasPrefix("[System:") &&
                   !$0.text.hasPrefix("[SYSTEM:")
               })?.text.trimmingCharacters(in: .whitespacesAndNewlines),
               !currentUserRequest.isEmpty {
                toolRequest.query = contextualizedSearchRequest(
                    for: threadId,
                    currentRequest: currentUserRequest
                )
            }

            // Settings can change while the app is open; refresh definitions
            // before every dispatch so disabled tools are never executed.
            configureToolRegistry()
            let call = normalizedToolCall(from: toolRequest)
            if let error = runController.prepare(call) {
                sendAgentToolResult(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error), threadId: threadId)
                return
            }
            beginUltraToolTask(call, threadId: threadId)
            guard let registeredTool = toolRegistry.tool(named: call.name), registeredTool.definition.isEnabled else {
                let error = AgentToolError(code: "TOOL_DISABLED", message: "The requested tool is currently disabled.", retryable: false)
                runController.record(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error))
                sendAgentToolResult(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error), threadId: threadId)
                return
            }
            do { try registeredTool.validate(call) } catch let error as AgentToolError {
                runController.record(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error))
                sendAgentToolResult(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error), threadId: threadId)
                return
            } catch { return }
            // A genuine tool call means the previous corrective nudge did its
            // job. Reset it so a later, unrelated request can be recovered too.
            self.toolNudgedThreadIds.remove(threadId)
            if toolRequest.type == "internet_use" {
                self.performInternetSearch(toolRequest: toolRequest, threadId: threadId)
                return
            }
            if toolRequest.type == "advanced_memory" {
                self.performAdvancedMemoryUpdate(toolRequest: toolRequest, threadId: threadId)
                return
            }
            if toolRequest.type == "learning" {
                self.performLearningAction(toolRequest: toolRequest, threadId: threadId)
                return
            }
            if toolRequest.type == "file_system" {
                Task { await self.performFileSystemAction(toolRequest: toolRequest, threadId: threadId) }
                return
            }
            if toolRequest.type == "apple_notes" {
                self.performAppleNotesAction(toolRequest: toolRequest, threadId: threadId)
                return
            }
            if toolRequest.type == "mcp" {
                Task { await self.performMCPAction(toolRequest: toolRequest, threadId: threadId) }
                return
            }
            guard !toolRequest.fields.isEmpty,
                  toolRequest.fields.allSatisfy({ $0.type == .insight }) else {
                let error = AgentToolError(code: "TOOL_RETIRED", message: "This interactive input tool is no longer available.", retryable: false)
                runController.record(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error))
                sendAgentToolResult(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error), threadId: threadId)
                return
            }
            
            if let active = self.toolRequestManager.activeRequest,
               self.toolRequestManager.activeRequestThreadId == threadId,
               active.title == toolRequest.title,
               active.fields.map({ $0.id }) == toolRequest.fields.map({ $0.id }) {
                return
            }
            
            let requiresPopup = toolRequest.fields.contains(where: { $0.type != .slider && $0.type != .insight })
            if requiresPopup {
                if let owner = self.toolRequestManager.activeRequestThreadId, owner != threadId {
                    let error = AgentToolError(
                        code: "INTERACTIVE_TOOL_BUSY",
                        message: "Another chat is waiting for user input. Complete or cancel that input card before opening a new one.",
                        retryable: false
                    )
                    runController.record(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error))
                    sendAgentToolResult(AgentToolResult(callID: call.id, toolName: call.name, success: false, error: error), threadId: threadId)
                    return
                }
                runController.record(AgentToolResult(callID: call.id, toolName: call.name, success: true), awaitingUser: true)
                self.toolRequestManager.loadRequest(toolRequest, threadId: threadId)
            } else {
                runController.record(AgentToolResult(callID: call.id, toolName: call.name, success: true))
            }
            return
        }
        
        // Never infer a tool action from ordinary assistant prose. For example,
        // “I can open Terminal” describes a capability; it is not permission to
        // launch Terminal. Assistant-initiated actions must use a strict tool
        // JSON object.
        //
        // Some local models nevertheless produce “I'll check …” after a tool
        // result and end the response. Ask once for the actual next tool call
        // rather than leaving the user without either a conclusion or action.
        let lowerText = messageText.lowercased()
        if runController.activeRun?.state == .verifying,
           runController.requestContinuationNudge() {
            Task { [weak self] in
                await self?.sendToolResponse(
                    text: #"{ "tool_response": { "status": "The previous tool call was invalid. Correct its arguments and execute the required tool now; do not merely describe the correction." } }"#,
                    threadId: threadId
                )
            }
            return
        }

        // A syntactically broken or partially wrapped tool call must not be
        // accepted as the final answer. Recover once when the output contains
        // strong structural evidence of an attempted call and the original
        // request actually belongs to a tool. We intentionally do not infer an
        // action from plain prose; the model must return a validated call on
        // the recovery turn.
        let attemptedToolSyntax = lowerText.contains("<tool_call") ||
            lowerText.contains("<|tool_call") ||
            lowerText.range(of: #"(?is)^\s*(?:internet_use|web_search)\s*\("#, options: .regularExpression) != nil ||
            lowerText.range(of: #"(?is)[{]\s*[\"']?(?:type|tool|tool_name|action|query)[\"']?\s*:"#, options: .regularExpression) != nil
        if attemptedToolSyntax,
           let activeRun = runController.activeRun {
            let intent = Self.requestIntent(for: activeRun.userGoal)
            let toolOwnedRequest = intent.needsFileSystem || intent.needsSearch || intent.needsVisualization
            if toolOwnedRequest,
               !self.toolNudgedThreadIds.contains(threadId),
               runController.requestContinuationNudge() {
                self.toolNudgedThreadIds.insert(threadId)
                Task { [weak self] in
                    await self?.sendToolResponse(
                        text: #"{ "tool_response": { "success": false, "error_code": "malformed_tool_call", "retryable": true, "status": "Your previous response attempted a tool call but its envelope or fields were invalid. Emit exactly one complete valid tool call for the next required action now. Use the latest returned stable refs and original user constraints. Do not include prose, Markdown fences, or a plan." } }"#,
                        threadId: threadId
                    )
                }
                return
            }
        }

        // Some reasoning-oriented local models finish a successful tool chain
        // with only a private `thought` block. The UI correctly hides that
        // content, but without a recovery turn the user is left with no answer.
        // Ask once for either the next explicitly requested action or the
        // conclusion. A successful action does not necessarily mean a
        // multi-step request is finished (for example, type then press Enter).
        let parsedReasoning = ChatMessage.extractReasoning(from: messageText)
        let visibleAnswer = parsedReasoning.mainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveReasoning = parsedReasoning.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSubstantiveAnswer = !visibleAnswer.isEmpty || effectiveReasoning.count >= 20
        if !hasSubstantiveAnswer,
           let activeRun = runController.activeRun,
           activeRun.completedToolCalls.isEmpty,
           !self.toolNudgedThreadIds.contains(threadId) {
            // The first response contained only hidden reasoning, so no action
            // was dispatched and nothing was shown to the user. Recover once;
            // a real tool call clears this guard in the parser above.
            self.toolNudgedThreadIds.insert(threadId)
            Task { [weak self] in
                await self?.sendToolResponse(
                    text: #"{ "tool_response": { "status": "Your previous response contained only private reasoning and performed no action. If the original user request requires a tool, emit exactly one valid tool JSON call for its first required action now. Otherwise return the concise user-facing answer now. Do not describe a plan." } }"#,
                    threadId: threadId
                )
            }
            return
        }
        if !hasSubstantiveAnswer,
           let activeRun = runController.activeRun,
           !activeRun.completedToolCalls.isEmpty,
           runController.requestContinuationNudge() {
            if activeRun.completedToolCalls.contains(where: { $0.call.name == "internet_search" }) {
                if self.finalAnswerRecoveryThreadIds.insert(threadId).inserted {
                    Task { [weak self] in
                        await self?.sendToolResponse(
                            text: #"{ "tool_response": { "status": "Search retrieval completed, but the previous model response ended inside private reasoning. Produce the complete visible answer now from the existing evidence." } }"#,
                            threadId: threadId,
                            forceDirectAnswer: true
                        )
                    }
                } else {
                    self.updateAssistantMessage(
                        threadId: threadId,
                        messageId: messageId,
                        text: "I found the sources, but the selected model ended without producing a visible answer. Please retry this message or switch the model; the completed queries and sources remain available in Activity.",
                        saveToDisk: true
                    )
                    runController.fail()
                }
                return
            }
            Task { [weak self] in
                await self?.sendToolResponse(
                    text: #"{ "tool_response": { "status": "The previous tool action completed successfully, but your response contained only private reasoning. Re-read the original user request and latest tool result. If an explicitly requested action remains, emit exactly one valid tool JSON call for that next action now. Otherwise return the concise user-facing final answer now. Do not describe a plan or repeat a completed action." } }"#,
                    threadId: threadId
                )
            }
            return
        }

        if self.finalAnswerRecoveryThreadIds.contains(threadId),
           let activeRun = runController.activeRun,
           activeRun.completedToolCalls.contains(where: { $0.call.name == "internet_search" }) {
            finalizeDirectAnswerRecovery(threadId: threadId, messageId: messageId)
            return
        }

        let promisedAction = [
            "i'll check", "i will check", "let me check", "i'll verify",
            "i will verify", "let me verify", "i'll look", "i will look",
            "i'll press", "i will press", "let me press", "i'll click",
            "i will click", "let me click", "i'll type", "i will type",
            "i'll navigate", "i will navigate"
        ].contains { lowerText.contains($0) }
        if promisedAction && !self.toolNudgedThreadIds.contains(threadId) && runController.requestContinuationNudge() {
            self.toolNudgedThreadIds.insert(threadId)
            Task { [weak self] in
                await self?.sendToolResponse(
                    text: #"{ "tool_response": { "status": "Execute the next explicitly required tool action now. Do not describe a future action or ask the user to wait. When no requested action remains, provide the final conclusion." } }"#,
                    threadId: threadId
                )
            }
            return
        }

        // Do not accept a memory-only answer for a request whose answer
        // depends on live rankings, recommendations, links, or compatibility.
        // Models may ignore the tool prompt, so enforce the first search in
        // the controller and then let the model synthesize the real results.
        if let activeRun = runController.activeRun {
            let contextualGoal = contextualizedSearchRequest(
                for: threadId,
                currentRequest: activeRun.userGoal
            )
            let requiresSearch = shouldUseInternetSearch(
                for: contextualGoal,
                mandatoryForCurrentTurn: mandatoryWebSearchThreadIds.contains(threadId)
            )
            let isMandatoryWebTurn = mandatoryWebSearchThreadIds.contains(threadId)
            if requiresSearch,
               (isMandatoryWebTurn || !Self.isSelfOrCapabilityQuery(activeRun.userGoal)),
               (isMandatoryWebTurn || !Self.isNonSearchConversationalOrCapability(activeRun.userGoal)),
               !activeRun.completedToolCalls.contains(where: { $0.call.name == "internet_search" }),
               self.threads[threadIndex].isToolUseEnabled,
               (preferences.object(forKey: "enableInternetSearch") as? Bool ?? true),
               self.isExposedSkillEnabled(StarterSkillCatalog.internetSearchID) {
                let cleanedSubject = Self.cleanedSearchSubject(contextualGoal)
                let query = isMandatoryWebTurn
                    ? (cleanedSubject.isEmpty ? contextualGoal : cleanedSubject)
                    : cleanedSubject
                if !query.isEmpty {
                    let forcedSearch = ToolRequest(
                        type: "internet_use",
                        title: "Searching the web",
                        description: "Fetching current sources…",
                        fields: [],
                        query: query
                    )
                    self.configureToolRegistry()
                    let call = self.normalizedToolCall(from: forcedSearch)
                    if runController.prepare(call) == nil,
                       let encoded = try? JSONEncoder().encode(forcedSearch),
                       let json = String(data: encoded, encoding: .utf8) {
                        self.threads[threadIndex].messages[msgIndex].text = json
                        self.saveThreads()
                        self.performInternetSearch(toolRequest: forcedSearch, threadId: threadId)
                        return
                    }
                }
            }
        }

        // Search results often emphasize older Apple Silicon generations. A
        // local model must not turn that evidence into a claim that the user
        // owns different hardware. Reject the draft once and request a clean,
        // explicitly qualified correction.
        if let activeRun = runController.activeRun,
           Self.hasAppleChipConstraintMismatch(request: activeRun.userGoal, answer: visibleAnswer),
           !self.constraintCorrectionThreadIds.contains(threadId) {
            self.constraintCorrectionThreadIds.insert(threadId)
            let anchors = Self.exactHardwareConstraints(in: activeRun.userGoal).joined(separator: ", ")
            Task { [weak self] in
                await self?.sendToolResponse(
                    text: #"{ "tool_response": { "status": "Rewrite the final answer: the draft changed an exact hardware constraint. Preserve these original constraints: \#(anchors). Do not describe the user's machine as an older chip. If sources only cover older chips, explicitly say the evidence is indirect and distinguish extrapolation from verified facts." } }"#,
                    threadId: threadId
                )
            }
            return
        }
        
        // 3. Automatic Refusal Bypass: If model outputs a canned refusal disclaimer, convert to Web Search
        let isRefusal = lowerText.contains("cannot fulfill this request") ||
                        lowerText.contains("prohibited from providing") ||
                        lowerText.contains("cannot provide information") ||
                        lowerText.contains("i am programmed to be") ||
                        lowerText.contains("i'm sorry, but i cannot")
        
        if isRefusal {
            let isSearchEnabled = preferences.object(forKey: "enableInternetSearch") as? Bool ?? true
            if isSearchEnabled,
               let userMsg = messages.last(where: { $0.role == .user && !$0.text.contains("tool_response") })?.text,
               !Self.isSelfOrCapabilityQuery(userMsg) {
                let contextualRequest = contextualizedSearchRequest(
                    for: threadId,
                    currentRequest: userMsg
                )
                guard shouldUseInternetSearch(
                    for: contextualRequest,
                    mandatoryForCurrentTurn: mandatoryWebSearchThreadIds.contains(threadId)
                ) else {
                    if finishUltraRun(threadId: threadId, hasVisibleAnswer: !visibleAnswer.isEmpty) {
                        runController.complete()
                    } else {
                        runController.fail()
                    }
                    return
                }
                let cleanPrompt = Self.cleanedSearchSubject(userMsg)
                if !cleanPrompt.isEmpty {
                    let sanitizedQuery = cleanPrompt.replacingOccurrences(of: "\"", with: "'")
                    let autoSearchJSON = """
                    {
                      "type": "internet_use",
                      "title": "Searching the web...",
                      "query": "\(sanitizedQuery)"
                    }
                    """
                    self.threads[threadIndex].messages[msgIndex].text = autoSearchJSON
                    self.saveThreads()
                    if let autoReq = ToolRequestParser.parseJSON(text: autoSearchJSON) {
                        self.performInternetSearch(toolRequest: autoReq, threadId: threadId)
                        return
                    }
                }
            }
        }

        // A provider completion without an action is the final answer. This is
        // deliberately controller-owned rather than inferred by any tool.
        if finishUltraRun(threadId: threadId, hasVisibleAnswer: !visibleAnswer.isEmpty) {
            runController.complete()
        } else {
            runController.fail()
        }

    }


    @MainActor
    private func performTaskAction(toolRequest: ToolRequest, threadId: UUID) {
        guard preferences.object(forKey: "enableTaskManagement") as? Bool ?? true else {
            Task { await self.sendToolResponse(text: #"{ "tool_response": { "status": "Error: Tasks Management is disabled in Tools & Modes." } }"#, threadId: threadId) }
            return
        }
        let action = toolRequest.action?.lowercased() ?? "create"
        var status = ""
        switch action {
        case "reorder":
            guard let id = toolRequest.taskId, let from = tasks.firstIndex(where: { $0.id == id }), let position = toolRequest.position else { status = "Task reorder failed: missing task ID or position."; break }
            let task = tasks.remove(at: from)
            tasks.insert(task, at: min(max(0, position), tasks.count))
            status = "Reordered task: \(task.title)"
        case "create_group":
            let group = toolRequest.groupName ?? toolRequest.title
            if !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !taskGroups.contains(group) {
                taskGroups.append(group)
            }
            status = "Created task group: \(group)"
        case "list":
            if tasks.isEmpty {
                status = "The Tasks page is currently empty."
            } else {
                status = tasks.map { task in
                    let state = task.isCompleted ? "completed" : "open"
                    let due = task.dueDate.map { ", due \($0)" } ?? ""
                    let details = task.details.isEmpty ? "" : " — \(task.details)"
                    return "[\(state)] \(task.title)\(details)\(due) (id: \(task.id.uuidString))"
                }.joined(separator: "\n")
            }
        case "create":
            let taskTitle = toolRequest.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !taskTitle.isEmpty else { return }
            addTask(title: taskTitle, details: toolRequest.description, dueDate: toolRequest.dueDate, groupName: toolRequest.groupName)
            status = "Created task: \(taskTitle)"
        case "complete", "update":
            guard let id = toolRequest.taskId, let index = tasks.firstIndex(where: { $0.id == id }) else {
                status = "Task update failed: the requested task was not found."
                break
            }
            if action == "complete" { tasks[index].isCompleted = true }
            if action == "update" {
                if !toolRequest.title.isEmpty { tasks[index].title = toolRequest.title }
                if !toolRequest.description.isEmpty { tasks[index].details = toolRequest.description }
            }
            if let dueDate = toolRequest.dueDate { tasks[index].dueDate = dueDate }
            if let groupName = toolRequest.groupName { tasks[index].groupName = groupName; if !taskGroups.contains(groupName) { taskGroups.append(groupName) } }
            status = "Updated task: \(tasks[index].title)"
        case "delete":
            guard let id = toolRequest.taskId else { status = "Task deletion failed: missing taskId."; break }
            deleteTask(id: id)
            status = "Deleted task."
        case "delete_completed":
            let completedCount = tasks.filter(\.isCompleted).count
            tasks.removeAll(where: \.isCompleted)
            status = completedCount == 0 ? "No completed tasks to delete." : "Deleted \(completedCount) completed task\(completedCount == 1 ? "" : "s")."
        case "delete_all":
            let taskCount = tasks.count
            tasks.removeAll()
            status = taskCount == 0 ? "There were no tasks to delete." : "Deleted all \(taskCount) tasks."
        default:
            status = "Task action failed: unsupported action \(action)."
        }
        let payload: [String: Any] = ["tool_response": ["status": status]]
        let response = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{ "tool_response": { "status": "Task action completed." } }"#
        Task { await self.sendToolResponse(text: response, threadId: threadId) }
    }
    
    public func getCombinedInstructions(isToolUseEnabled: Bool, systemInstructions: String, memoryNodes: [MemoryNode] = [], memoryEdges: [MemoryEdge] = [], threadId: UUID? = nil, requestText: String? = nil) -> String {
        let isIsolated = threadId.flatMap { id in threads.first(where: { $0.id == id })?.isolatesContext } ?? false
        let latestUserRequest = threads.first(where: { $0.id == threadId })?.messages.reversed().first(where: {
            $0.role == .user && !$0.isToolResponse
        })?.text ?? ""
        let effectiveRequest = (requestText?.contains("tool_response") == false ? requestText : nil) ?? latestUserRequest
        let requestIntent = Self.requestIntent(for: effectiveRequest)
        let exactConstraints = Self.exactHardwareConstraints(in: effectiveRequest)
        let constraintPrompt = exactConstraints.isEmpty ? "" : "[IMMUTABLE REQUEST CONSTRAINTS]\nPreserve these exact user-provided values throughout reasoning, searches, and the final answer: \(exactConstraints.joined(separator: ", ")). Never assume an unfamiliar or newer product name is a typo based on model memory. Search the exact name first and only call it a typo if current evidence explicitly proves that. Never replace it with values found in examples or search results. Evidence about a different generation must be labeled as indirect evidence, not treated as the user's configuration. Current calendar year: \(Calendar.current.component(.year, from: Date()))."
        let savedThreadSummary = threadId.flatMap { id in threads.first(where: { $0.id == id })?.chatMemory } ?? ""
        let memoryPrompt = !isIsolated && isPrePromptEnabled("thread_memory") && !savedThreadSummary.isEmpty
            ? "[EARLIER THREAD SUMMARY]\n\(savedThreadSummary)"
            : ""
        let timeContext = isPrePromptEnabled("time_context") && requestIntent.needsTime ? getCurrentTimeContext() : ""
        
        // Chat isolation prevents old transcripts, rolling summaries, and task
        // lists from leaking into a new chat. AMKG is different: it is the
        // explicit, user-managed persistent memory store and must remain part
        // of the compiled prompt when the knowledge-graph pre-prompt is on.
        let nodesToUse = memoryNodes.isEmpty ? self.globalMemoryNodes : memoryNodes
        let edgesToUse = memoryEdges.isEmpty ? self.globalMemoryEdges : memoryEdges
        
        var graphPrompt = ""
        if isPrePromptEnabled("knowledge_graph") && !nodesToUse.isEmpty {
            graphPrompt = "[PERSISTENT KNOWLEDGE GRAPH MEMORY]\nYou have recorded the following structured facts and connections about the user:\n"
            for node in nodesToUse {
                graphPrompt += "- Entity: \(node.label) [ID: \(node.id), Category: \(node.category)]\n"
            }
            for edge in edgesToUse {
                let sourceLabel = nodesToUse.first(where: { $0.id == edge.source })?.label ?? edge.source
                let targetLabel = nodesToUse.first(where: { $0.id == edge.target })?.label ?? edge.target
                graphPrompt += "- Connection: \(sourceLabel) -> \(edge.label) -> \(targetLabel)\n"
            }
            graphPrompt += "\nUse this graph only for user/entity context. New personal facts and relationships may be saved with advanced_memory. Operational fixes and reusable behavior rules must use learning instead."
        }
        
        // Unified effort setting controls both provider-native reasoning and
        // the fallback instruction used by models without a native parameter.
        let effortLevel = configuredEffortLevel()
        let threadProvider = threadId.flatMap { id in threads.first(where: { $0.id == id })?.provider }
        let isThinkingEnabled = reasoningIsEnabled(for: threadProvider)
        let thinkingPrompt: String
        if isPrePromptEnabled("thinking_mode") {
            thinkingPrompt = isThinkingEnabled
                ? "\(exposedSkillInstructions(StarterSkillCatalog.reasoningID))\n[EFFORT: \(effortLevel)] Use proportionally \(effortLevel.lowercased()) internal reasoning. Complete the task fully, but never expose private chain-of-thought."
                : exposedSkillInstructions(StarterSkillCatalog.directResponseID)
        } else {
            thinkingPrompt = ""
        }
        let isProgressTrackingActive = threadId.map { ultraTaskRuns[$0] != nil } ?? requestIntent.shouldTrackProgress
        let ultraPrompt = isProgressTrackingActive ? """
        [AUTONOMOUS TASK TRACKING]
        This run is tracked as a verified task checklist in Activity. For multi-step work, execute exactly one necessary tool action at a time. Each emitted tool action becomes a checklist task and is marked complete only from its actual successful tool response. After every result, continue with the next required action. Do not give a final answer while any requested action remains. Finish only after all actions have succeeded and the result has been verified. If progress is genuinely impossible, report the precise blocker; never claim completion.
        """ : ""
        
        // Cross Check Mode
        let isCrossCheckEnabled = preferences.object(forKey: "enableCrossCheck") as? Bool ?? false
        let isLocalClockRequest = Self.isLocalDateTimeQuestion(effectiveRequest)
        let crossCheckPrompt = (isPrePromptEnabled("cross_check") && isCrossCheckEnabled && !isLocalClockRequest) ? exposedSkillInstructions(StarterSkillCatalog.crossCheckID) : ""

        let canSearchLive = isToolUseEnabled &&
            (preferences.object(forKey: "enableInternetSearch") as? Bool ?? true) &&
            isExposedSkillEnabled(StarterSkillCatalog.internetSearchID)
        let isCapabilityOrCasual = Self.isSelfOrCapabilityQuery(effectiveRequest) || Self.isNonSearchConversationalOrCapability(effectiveRequest)
        let liveSearchRequirement = requestIntent.needsSearch && canSearchLive && !isCapabilityOrCasual
            ? """
            [WEB RETRIEVAL]
            This request needs current or independently verifiable evidence. Use `internet_use` before answering. Search the user's actual subject—not instruction wording—prefer primary or authoritative sources, distinguish strong evidence from preliminary claims, and cite only fetched pages that support the answer.
            """
            : ""
        let localClockPrompt = isLocalClockRequest
            ? "[LOCAL CLOCK ANSWER]\nThe current date and time supplied by the system is authoritative for this request. Answer from it directly. Do not call internet_use or cite websites."
            : ""
        
        // Persona & Relationship Obedience Directive
        let personaObediencePrompt = isPrePromptEnabled("persona_obedience") ? exposedSkillInstructions(StarterSkillCatalog.personaID) : ""
        
        // Self-Learning & Error-Resolution Memory Mandate
        let selfLearningPrompt = isPrePromptEnabled("self_learning_memory")
            ? "[LEARNING] Save only verified, reusable fixes after a confirmed correction. Use learning list before append/update; never store guesses, logs, credentials, personal facts, or private reasoning."
            : ""
        
        // A selected system prompt is part of the thread contract, not an
        // optional pre-prompt. Always include it unchanged (apart from legacy
        // embedded tool directives removed below) for every provider.
        var effectiveSystemInstructions = systemInstructions
        // Older builds embedded Library API directives directly into each
        // thread's system prompt. Strip those legacy copies from model context;
        // the editable Space → Skills record below is now the single source.
        for definition in ChatManager.allLibraryApiDefs {
            let tag = "[API_TOOL: \(definition.id)]"
            effectiveSystemInstructions = effectiveSystemInstructions
                .replacingOccurrences(of: "\n\(tag): \(definition.name) capability attached. \(definition.promptDirective)", with: "")
                .replacingOccurrences(of: definition.promptDirective, with: "")
        }
        
        var toolPrompt = ""
        if isToolUseEnabled && isPrePromptEnabled("tool_schemas") {
            let isDynamicInsightsEnabled = preferences.object(forKey: "enableDynamicInsights") as? Bool ?? true
            let isSearchEnabled = preferences.object(forKey: "enableInternetSearch") as? Bool ?? true
            let isFileSystemEnabled = preferences.object(forKey: "enableFileSystem") as? Bool ?? true
            toolPrompt = compactToolInstructions([
                // Enabled Toolbox capabilities must always be visible to the
                // model. Intent routing is advisory and can miss natural
                // phrasing; hiding schemas made an enabled tool inaccessible.
                2: isDynamicInsightsEnabled,
                4: isSearchEnabled,
                5: true,
                6: isFileSystemEnabled,
                9: true
            ])
        }
        
        let universalExcellenceDirective = "Answer accurately, directly, and completely. Match depth and formatting to the request; state uncertainty and never invent facts or completed actions."
        
        let targetThread = threadId.flatMap { id in threads.first(where: { $0.id == id }) }
        let currentModelName = targetThread?.activeModelName ?? "the active model"
        let currentProviderName = targetThread?.provider.displayName ?? "local / cloud engine"
        
        var availableCapabilitiesList: [String] = []
        if isToolUseEnabled {
            if preferences.object(forKey: "enableInternetSearch") as? Bool ?? true {
                availableCapabilitiesList.append("• Web Research (`internet_use`): Live search and multi-source retrieval for up-to-date information, benchmarks, and real-time facts.")
            }
            if preferences.object(forKey: "enableFileSystem") as? Bool ?? true {
                availableCapabilitiesList.append("• Terminal & File System (`file_system`): Full authorized native macOS shell command execution (zsh, brew, scripts) and file operations (read, write, create, inspect).")
            }
            availableCapabilitiesList.append("• Structured Long-Term Memory (`advanced_memory`): Graph-based entity and relationship knowledge store across turns.")
            availableCapabilitiesList.append("• Self-Learning & Rules (`learning`): Recording and applying verified operational corrections, patterns, and workflows.")
            if preferences.object(forKey: "enableDynamicInsights") as? Bool ?? true {
                availableCapabilitiesList.append("• Dynamic Insights (`dynamic_insights`): Structured analysis cards and visual summaries.")
            }
            for mcpTool in MCPServerManager.shared.allTools {
                availableCapabilitiesList.append("• MCP Integration (`\(mcpTool.serverName)`): \(mcpTool.name) - \(mcpTool.description)")
            }
        }
        let capabilitiesStr = availableCapabilitiesList.isEmpty ? "Direct conversation and reasoning." : availableCapabilitiesList.joined(separator: "\n")

        let haliteIdentityPrompt = """
        [AGENT IDENTITY & ARCHITECTURE]
        You are Halite, a native, state-of-the-art macOS AI Agent.
        - Core Engine: Running on top of \(currentModelName) via \(currentProviderName).
        - Tuning & Alignment: Optimized for proactive problem solving, tool execution, direct truthfulness, and precise developer/creative assistance.
        - Capabilities & Tool Access:
        \(capabilitiesStr)
        - Self-Awareness: You know you are Halite. If asked who you are, what you can do, your architecture, or how you compare to other models/agents, accurately state your identity as Halite powered by \(currentModelName), detail your exact live capabilities and tools, and answer with confidence without unnecessary generic disclaimers.
        """

        var components: [String] = []
        components.append(haliteIdentityPrompt)
        if !effectiveSystemInstructions.isEmpty {
            components.append("[USER SYSTEM INSTRUCTIONS]\n\(effectiveSystemInstructions)")
        }
        components.append(universalExcellenceDirective)
        if !personaObediencePrompt.isEmpty { components.append(personaObediencePrompt) }
        if !selfLearningPrompt.isEmpty { components.append(selfLearningPrompt) }
        if !thinkingPrompt.isEmpty { components.append(thinkingPrompt) }
        if !ultraPrompt.isEmpty { components.append(ultraPrompt) }
        if !crossCheckPrompt.isEmpty { components.append(crossCheckPrompt) }
        if !liveSearchRequirement.isEmpty { components.append(liveSearchRequirement) }
        if !localClockPrompt.isEmpty { components.append(localClockPrompt) }
        let isContinuationPrompt: Bool = {
            let lower = effectiveRequest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return [
                "continue", "continue.", "continue from where you left off", "continue from where you left off.",
                "go on", "go on.", "proceed", "proceed.", "keep going", "keep going.", "continue answering"
            ].contains(lower) || (lower.hasPrefix("continue") && lower.count < 40)
        }()
        var continuationPrompt = ""
        if isContinuationPrompt,
           let prevUserMsg = threads.first(where: { $0.id == threadId })?.messages.reversed().first(where: {
               $0.role == .user && !$0.isToolResponse && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) != effectiveRequest
           })?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !prevUserMsg.isEmpty {
            continuationPrompt = "[CONTINUATION CONTEXT]\nThe user is prompting you to continue with the previous task: \"\(prevUserMsg)\". Rely on the conversation history and any retrieved evidence above to produce the direct, complete answer now. Do not output a generic disclaimer claiming you lack history."
        }

        if !continuationPrompt.isEmpty { components.append(continuationPrompt) }
        if !constraintPrompt.isEmpty { components.append(constraintPrompt) }
        if !toolPrompt.isEmpty { components.append(toolPrompt) }
        if !memoryPrompt.isEmpty { components.append(memoryPrompt) }
        if !graphPrompt.isEmpty { components.append(graphPrompt) }
        if !timeContext.isEmpty { components.append(timeContext) }

        let enabledSkills = customSkills.filter {
            $0.isEnabled &&
            !StarterSkillCatalog.isInfrastructure($0.id) &&
            !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !enabledSkills.isEmpty {
            let activeSkills = enabledSkills.filter { skill in
                StarterSkillCatalog.isStarter(skill.id)
                    ? StarterSkillCatalog.matches(skill, request: effectiveRequest)
                    : Self.customSkillMatches(skill, request: effectiveRequest)
            }
            var skillsPrompt = ""
            if !activeSkills.isEmpty {
                skillsPrompt = "[ACTIVE SKILLS]\nApply these locally matched workflows:\n"
            }
            for skill in activeSkills {
                skillsPrompt += "\n## \(skill.name)\nWhen to use: \(skill.summary)\nInstructions:\n\(skill.instructions)\n"
            }
            if !skillsPrompt.isEmpty { components.append(skillsPrompt) }
        }
        
        // Inject installed Library API directives into the compiled prompt
        let globalInstalledTools = Set(preferences.stringArray(forKey: "InstalledLibraryTools") ?? [])
        for def in ChatManager.allLibraryApiDefs {
            let tag = "[API_TOOL: \(def.id)]"
            let prePromptId = "library_api_\(def.id)"
            let isInstalled = globalInstalledTools.contains(def.id) || systemInstructions.contains(tag) || systemInstructions.contains(def.id) || systemInstructions.contains(def.name)
            if isInstalled && !self.disabledPrePromptIds.contains(prePromptId) {
                // Credentials are supplied only to their transport layer; a
                // model never needs to see them in a system prompt.
                if let skillID = StarterSkillCatalog.librarySkillID(for: def.id) {
                    let editableDirective = exposedSkillInstructions(skillID)
                    if !editableDirective.isEmpty { components.append(editableDirective) }
                }
            }
        }

        // Keep this final so long tool schemas, skills, or memory cannot push
        // the completion contract into the easy-to-ignore middle of context.
        components.append("[FINAL CHECK] Cover every requested item and exact constraint. Perform all calculations and unit conversions internally; never expose scratchpad notes, rough drafts, backtracking, or self-correction monologues. Present a clean, consistent, verified answer with exact matching totals.")
        if !exactConstraints.isEmpty {
            components.append("[FINAL CONSTRAINT CHECK]\nPreserve these exact user values in the answer: \(exactConstraints.joined(separator: ", ")).")
        }
        
        return components.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compact routing contract. Detailed tool documentation no longer consumes
    /// context on every generation; validation stays deterministic in Swift.
    private func compactToolInstructions(_ enabled: [Int: Bool]) -> String {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var names: [String] = [
            enabled[2] == true ? "dynamic_insights(title,description,fields)" : nil,
            enabled[4] == true ? "internet_use(query)" : nil,
            enabled[5] == true ? "advanced_memory(action,nodes,edges)" : nil,
            enabled[6] == true ? "file_system(action,path,content,command,files); actions execute_command (runs macOS zsh shell commands),list,read_file,create_file,create_files,create_folder; home=\(home). You have authorized terminal access via execute_command." : nil,
            enabled[9] == true ? "learning(action,learningId,learningKind,learningTopic,content)" : nil
        ].compactMap { $0 }

        // Inject active MCP tools into prompt
        for mcpTool in MCPServerManager.shared.allTools {
            let params = mcpTool.parameterNames.joined(separator: ",")
            let desc = mcpTool.description.isEmpty ? "" : " - \(mcpTool.description)"
            names.append("mcp_\(mcpTool.serverName)_\(mcpTool.name)(\(params))\(desc)")
        }

        guard !names.isEmpty else { return "" }
        return """
        [TOOL ROUTER & DIRECTIVE]
        \(names.joined(separator: "\n"))
        You are Halite, a native macOS agent with FULL authorization to run terminal commands and manage files using `file_system`.
        - Before emitting any tool call, write a brief, polite 1-sentence intro acknowledging what you will do (e.g. "I'll install Vue CLI for you now using Homebrew." or "Checking system status...").
        - When the user asks you to install software, run commands, create files, or troubleshoot, DO NOT refuse or say you cannot execute commands.
        - DO NOT print manual tutorial steps when asked to do something. Perform the action directly by emitting exactly one tool JSON object: {"type": "file_system", "action": "execute_command", "command": "..."}.
        - For installing macOS packages or tools, use Homebrew (e.g. `brew install <package>` or `brew install --cask <app>`).
        - When running development servers (e.g. `npm run dev`, `vite`, `nuxt`, `next dev`), report the active `http://localhost:...` URL to the user in your final response and complete your turn immediately.
        - Inspect the tool result before taking the next step. Stop immediately when the request is complete.
        """
    }

    private struct RequestIntent {
        let needsFileSystem: Bool
        let needsTasks: Bool
        let needsSearch: Bool
        let isEvidenceSensitive: Bool
        let allowsAutomaticSearch: Bool
        let needsVisualization: Bool
        let needsInput: Bool
        let needsTime: Bool
        let isComplex: Bool
        let shouldTrackProgress: Bool
    }

    nonisolated public static func isSelfOrCapabilityQuery(_ text: String) -> Bool {
        let q = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let capabilityPhrases = [
            "what can you do", "what can u do", "what else can you do", "what else can u do",
            "what are your capabilities", "what are your features", "what are your tools",
            "what are your skills", "what do you do", "what can this app do", "how can you help",
            "how can u help", "who are you", "what are you", "tell me about yourself",
            "who made you", "who created you", "how do you work", "introduce yourself",
            "what is your name", "whats your name", "what's your name", "what are your functions",
            "what else do you do", "what else can be done", "what all can you do", "what all can u do"
        ]
        return capabilityPhrases.contains { q.contains($0) }
    }

    nonisolated public static func isNonSearchConversationalOrCapability(_ text: String) -> Bool {
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if isSelfOrCapabilityQuery(trimmed) { return true }
        let exactCasualMessages: Set<String> = [
            "hi", "hello", "hey", "howdy", "sup", "yo",
            "thanks", "thank you", "thanks a lot", "thank you so much",
            "good morning", "good afternoon", "good evening", "good night",
            "bye", "goodbye", "see you", "cya",
            "ok", "okay", "cool", "great", "awesome", "nice", "perfect",
            "continue", "go on", "proceed", "yes", "no", "yep", "nope",
            "what's up", "whats up", "how are you", "how are you doing", "how r u"
        ]
        if exactCasualMessages.contains(trimmed) { return true }
        
        let conversationalPrefixes = [
            "how are you", "how r u", "who are you", "what can you do", "what can u do",
            "what else can you do", "what else can u do", "what did i", "what have i",
            "do you remember", "thanks for", "thank you for", "tell me a joke", "tell me a story",
            "write me a poem", "write a poem", "write a story", "help me with", "can you help me"
        ]
        return conversationalPrefixes.contains { trimmed.hasPrefix($0) }
    }

    nonisolated private static func requestIntent(for request: String) -> RequestIntent {
        let q = request.lowercased()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        func has(_ terms: [String]) -> Bool { terms.contains { q.contains($0) } }
        func starts(_ terms: [String]) -> Bool {
            return terms.contains { trimmed.hasPrefix($0) }
        }
        let localClock = isLocalDateTimeQuestion(request)
        let isCapability = isSelfOrCapabilityQuery(trimmed)
        let conversational = isNonSearchConversationalOrCapability(trimmed)
        
        let filesystem = has(["file", "folder", "directory", "download", "desktop", "document", "workspace", "code", "website", "project", "terminal", "command", "install", "open app", "html", "css", "javascript", "swift"])
        let tasks = has(["task", "todo", "to-do", "remind", "schedule", "due date", "mark complete"])
        let explicitSearch = has([
            "search the web", "search online", "look up online", "google ", "find online",
            "find links", "fetch links", "verify online", "search for ", "research online",
            "browse the web", "use search", "web search", "search it", "look it up", "verify it"
        ])
        // Treat broad freshness language as live-data intent. Previously this
        // only recognized a few exact phrases such as `latest news`, allowing
        // requests like "latest iOS beta release changes" to be answered from
        // a local model's stale training cutoff instead of current sources.
        let currentRealWorldInfo = has([
            "latest", "most recent", "recent changes", "recent update", "newest",
            "what's new", "whats new", "currently available", "current version",
            "current release", "current price", "stock price", "current weather",
            "release changes", "release notes", "new release", "beta release", " beta ",
            "latest news", "breaking news", "today's headlines", "todays headlines",
            "this week", "this month", "this year", "as of today", "as of now",
            "election results", "release date of", "who won"
        ])
        
        let directCreationOrMutation = starts([
            "write ", "rewrite ", "draft ", "compose ", "create ", "make ", "build ",
            "implement ", "fix ", "edit ", "change ", "update ", "delete ", "remove ",
            "run ", "open ", "install ", "rename ", "move ", "summarize this",
            "summarise this", "translate ", "proofread ", "format ", "tell me a joke",
            "tell me a story", "write me", "roleplay ", "brainstorm "
        ])
        let suppliedOrLocalContext = has([
            "this code", "this function", "this error", "this output", "this file",
            "this document", "this text", "this image",
            "attached file", "attached image", "following code", "code below", "text below",
            "error below", "these logs", "my workspace", "my repository", "my repo",
            "my files", "my tasks", "task list"
        ])
        let explicitlyDisablesSearch = has([
            "don't search", "do not search", "without searching", "don't use the web",
            "do not use the web", "no web search", "offline only", "answer from memory"
        ])
        let visualization = has(["interactive", "dashboard", "calculator", "simulator", "visualization", "chart", "graph"])
        let input = has(["ask me", "collect", "form", "questionnaire", "need my", "choose from"])

        let localFileAction = filesystem && (directCreationOrMutation || suppliedOrLocalContext || starts([
            "list ", "show ", "read ", "find ", "inspect ", "check ", "organize ", "organise "
        ]) || has([
            "use terminal", "use the terminal", "run command", "open app", "on my desktop",
            "in my downloads", "in this project", "in this workspace"
        ]))
        let taskAction = tasks && (directCreationOrMutation || suppliedOrLocalContext || has([
            "add a task", "create a task", "list tasks", "show tasks", "complete task",
            "delete task", "remove task", "my todo", "my to-do"
        ]))
        let visualAction = visualization && directCreationOrMutation
        let inputAction = input && (directCreationOrMutation || starts(["ask me", "collect ", "give me a form", "show me a form"]))
        let explicitlyNamesAnotherTool = has([
            "use vision", "vision mode", "file_system", "task_management",
            "use filesystem", "use the filesystem", "use my files", "use the task tool",
            "dynamic input", "use visualization", "use the visualization"
        ])
        let dedicatedNonSearchTool = suppliedOrLocalContext || explicitlyNamesAnotherTool ||
            localFileAction || taskAction || visualAction || inputAction

        let evidenceDomain = evidenceDomain(for: request)
        let evidenceSensitive: Bool
        switch evidenceDomain {
        case .nutrition, .health, .legal, .finance, .academic:
            evidenceSensitive = true
        case .aiModel, .software, .product, .news, .travel, .general:
            evidenceSensitive = false
        }
        let allowsAutomaticSearch = !conversational && !isCapability && !localClock &&
            !explicitlyDisablesSearch && !dedicatedNonSearchTool
        let needsLiveSearch = (explicitSearch || currentRealWorldInfo || evidenceSensitive) && allowsAutomaticSearch
        let time = localClock || has(["today", "tomorrow", "yesterday", "current time", "date", "schedule", "deadline", "due"])
        let complex = filesystem || visualization || q.count > 500 || has(["analyze", "debug", "research", "compare", "architecture", "multi-step"])
        let explicitlyMultiStep = has([
            "multi-step", "multistep", "multiple steps", "step by step", "and then",
            "after that", "followed by", "all of the following", "complete every",
            "implement and test", "build and run", "fix and verify"
        ])
        let agenticWorkspaceWork = localFileAction && (
            directCreationOrMutation || has(["debug", "test", "verify", "refactor", "configure", "set up"])
        )
        let shouldTrackProgress = !conversational && !isCapability && !localClock && (
            explicitlyMultiStep || (agenticWorkspaceWork && complex)
        )
        return RequestIntent(
            needsFileSystem: filesystem,
            needsTasks: tasks,
            needsSearch: needsLiveSearch,
            isEvidenceSensitive: evidenceSensitive,
            allowsAutomaticSearch: allowsAutomaticSearch,
            needsVisualization: visualization,
            needsInput: input,
            needsTime: time,
            isComplex: complex,
            shouldTrackProgress: shouldTrackProgress
        )
    }

    /// The composer Web toggle is the only unconditional search mode. Without
    /// it, deterministic routing is limited to requests that explicitly ask
    /// for search or need fresh/high-stakes evidence.
    private func shouldUseInternetSearch(
        for request: String,
        mandatoryForCurrentTurn: Bool
    ) -> Bool {
        if mandatoryForCurrentTurn { return true }
        let intent = Self.requestIntent(for: request)
        guard intent.allowsAutomaticSearch else { return false }
        if intent.needsSearch { return true }
        if isPrePromptEnabled("cross_check"),
           preferences.object(forKey: "enableCrossCheck") as? Bool ?? false,
           intent.isEvidenceSensitive {
            return true
        }
        return false
    }

    nonisolated private static func isLocalDateTimeQuestion(_ request: String) -> Bool {
        let q = request.lowercased()
        let asksClock = [
            "what's today", "whats today", "today's date", "todays date",
            "what date is it", "what is the date", "current date",
            "what time is it", "what's the time", "whats the time", "current time",
            "what day is it", "what is today", "date and time"
        ].contains { q.contains($0) }
        guard asksClock else { return false }
        let explicitlyOnline = ["search", "web", "online", "google", "source", "verify"].contains { q.contains($0) }
        let asksExternalCurrentInfo = ["weather", "news", "price", "market", "schedule", "deadline", "release"].contains { q.contains($0) }
        return !explicitlyOnline && !asksExternalCurrentInfo
    }

    private func localDateTimeAnswer(for request: String) -> String {
        let now = Date()
        let q = request.lowercased()
        let asksForTime = q.contains("time")
        let asksForDate = q.contains("date") || q.contains("today") || q.contains("day")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        dateFormatter.timeZone = .current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.timeZone = .current
        let zone = TimeZone.current.abbreviation() ?? TimeZone.current.identifier
        if asksForTime && asksForDate {
            return "Today is \(dateFormatter.string(from: now)), and the local time is \(timeFormatter.string(from: now)) \(zone)."
        }
        if asksForTime {
            return "The local time is \(timeFormatter.string(from: now)) \(zone)."
        }
        return "Today is \(dateFormatter.string(from: now))."
    }

    nonisolated private static func exactHardwareConstraints(in text: String) -> [String] {
        let patterns = [#"(?i)\bM[1-9][0-9]?\b"#, #"(?i)\b[0-9]+\s*GB\b"#]
        var values: [String] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in expression.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let value = String(text[swiftRange]).uppercased().replacingOccurrences(of: " ", with: "")
                if !values.contains(value) { values.append(value) }
            }
        }
        return values
    }

    nonisolated private static func explicitYears(in text: String) -> [Int] {
        guard let expression = try? NSRegularExpression(pattern: #"\b(?:19|20)[0-9]{2}\b"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return Int(text[swiftRange])
        }
    }

    nonisolated private static func hasAppleChipConstraintMismatch(request: String, answer: String) -> Bool {
        let requested = exactHardwareConstraints(in: request).filter { $0.hasPrefix("M") }
        guard !requested.isEmpty, !answer.isEmpty else { return false }
        let lowerAnswer = answer.lowercased()
        if requested.contains(where: { !lowerAnswer.contains($0.lowercased()) }) { return true }

        let allChips = exactHardwareConstraints(in: answer).filter { $0.hasPrefix("M") }
        for chip in allChips where !requested.contains(chip) {
            let lowerChip = chip.lowercased()
            let incorrectOwnership = [
                "your \(lowerChip)", "their \(lowerChip)", "on an \(lowerChip)",
                "for an \(lowerChip)", "for your \(lowerChip)", "with an \(lowerChip)"
            ].contains { lowerAnswer.contains($0) }
            if incorrectOwnership { return true }
        }
        return false
    }

    nonisolated private static func customSkillMatches(_ skill: CustomSkill, request: String) -> Bool {
        let query = request.lowercased()
        let name = skill.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && query.contains(name) { return true }
        let ignored: Set<String> = ["this", "that", "with", "when", "user", "asks", "use", "skill", "specific", "workflow", "complete", "from", "into", "your", "their", "have", "will"]
        let terms = skill.summary.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !ignored.contains($0) }
        return terms.filter { query.contains($0) }.count >= min(2, max(1, terms.count))
    }

    nonisolated private static func assistantDisplayText(from rawText: String) -> String {
        // Local models can emit an untagged `thought:` / `thought\n` block.
        // The UI recognizes it as private reasoning, but the old history
        // serializer replayed it as a normal assistant answer. That caused a
        // later request to continue an earlier thought instead of answering
        // the newest user message.
        let parsed = ChatMessage.extractReasoning(from: rawText)
        let displayText = parsed.reasoningText != nil && parsed.mainText.isEmpty ? "" : parsed.mainText
        return displayText
            .replacingOccurrences(of: #"(?is)<think>.*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<thought>.*?</thought>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)\[THINKING\].*?\[/THINKING\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<\|tool_call\|>.*?<\|tool_call\|>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<\|tool_call\|>.*?<tool_call\|>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<tool_call>.*?</tool_call>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)call:\w+\{.*?\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func getCompiledPrePrompt(for threadId: UUID? = nil) -> String {
        let targetThread = threads.first(where: { $0.id == (threadId ?? activeThreadId) }) ?? threads.first
        guard let thread = targetThread else {
            return getCombinedInstructions(isToolUseEnabled: true, systemInstructions: "You are a helpful assistant.")
        }
        let activeNodes = self.globalMemoryNodes.isEmpty ? thread.memoryNodes : self.globalMemoryNodes
        let activeEdges = self.globalMemoryEdges.isEmpty ? thread.memoryEdges : self.globalMemoryEdges
        let compiled = getCombinedInstructions(
            isToolUseEnabled: thread.isToolUseEnabled,
            systemInstructions: thread.systemInstructions,
            memoryNodes: activeNodes,
            memoryEdges: activeEdges,
            threadId: thread.id
        )
        guard thread.provider == .lmStudio else { return compiled }
        return compiled + localModelToolProtocol(isToolUseEnabled: thread.isToolUseEnabled)
    }

    /// Provider-specific system text appended to LM Studio requests. Keeping it
    /// here makes the right-sidebar preview byte-for-byte identical to the
    /// system-role string assembled by generation.
    private func localModelToolProtocol(isToolUseEnabled: Bool) -> String {
        guard isToolUseEnabled, isPrePromptEnabled("tool_schemas") else { return "" }
        return """


        [LOCAL TOOL ROUTER]
        For file organization use file_system with the exact supported action and requested path. List first for complex conditional changes. Keep commands scoped and never delete or overwrite unless explicitly requested. Inspect every tool result before continuing or answering.
        """
    }
    
    public func getPrePromptItems(for threadId: UUID? = nil) -> [PrePromptItem] {
        let targetThread = threads.first(where: { $0.id == (threadId ?? activeThreadId) }) ?? threads.first
        let systemInst = targetThread?.systemInstructions ?? "You are a helpful assistant."
        let isToolEnabled = targetThread?.isToolUseEnabled ?? true
        
        let memoryPrompt = getSystemMemoryPrompt()
        let timeContext = getCurrentTimeContext()
        
        let nodesToUse = (targetThread?.memoryNodes.isEmpty ?? true) ? self.globalMemoryNodes : (targetThread?.memoryNodes ?? [])
        let edgesToUse = (targetThread?.memoryEdges.isEmpty ?? true) ? self.globalMemoryEdges : (targetThread?.memoryEdges ?? [])
        
        var graphPrompt = ""
        if !nodesToUse.isEmpty {
            graphPrompt = "[PERSISTENT KNOWLEDGE GRAPH MEMORY]\nYou have recorded the following structured facts and connections about the user:\n"
            for node in nodesToUse {
                graphPrompt += "- Entity: \(node.label) [ID: \(node.id), Category: \(node.category)]\n"
            }
            for edge in edgesToUse {
                let sourceLabel = nodesToUse.first(where: { $0.id == edge.source })?.label ?? edge.source
                let targetLabel = nodesToUse.first(where: { $0.id == edge.target })?.label ?? edge.target
                graphPrompt += "- Connection: \(sourceLabel) -> \(edge.label) -> \(targetLabel)\n"
            }
            graphPrompt += "\nUse this graph only for user/entity context. Store operational fixes in Learning, not AMKG."
        }
        
        let isThinkingEnabled = reasoningIsEnabled(for: targetThread?.provider)
        let isCrossCheckEnabled = preferences.object(forKey: "enableCrossCheck") as? Bool ?? false
        
        let personaObediencePrompt = exposedSkillInstructions(StarterSkillCatalog.personaID)
        let selfLearningPrompt = "[SELF LEARNING]\nSave only verified reusable operational knowledge in Learning. Use a prevention rule after a confirmed correction. A difficult run (2+ failed tool attempts then success, or a verified 6+ step workflow lasting 60+ seconds) requires a How-to: list first, then update the matching learningId or append learningKind how-to with a stable 2–6 word learningTopic, applicability, preconditions, ordered successful steps, verification, and pitfalls. Related entries reuse the same topic and appear under that visible subheading in Skills → Learning. Never store raw logs, private reasoning, credentials, or personal facts."
        
        let activeInstructions = compactToolInstructions([
            2: preferences.object(forKey: "enableDynamicInsights") as? Bool ?? true,
            4: preferences.object(forKey: "enableInternetSearch") as? Bool ?? true,
            5: true,
            6: preferences.object(forKey: "enableFileSystem") as? Bool ?? true,
            8: true,
            9: true
        ])
        
        let resolveStatus = { (id: String, defaultActive: Bool) -> (isEnabled: Bool, text: String) in
            if self.disabledPrePromptIds.contains(id) {
                return (false, "Temporarily Off")
            }
            if !defaultActive {
                return (false, "Disabled in Settings")
            }
            return (true, "Active")
        }
        
        let stSys = (isEnabled: !systemInst.isEmpty, text: systemInst.isEmpty ? "Not Configured" : "Active")
        let stPersona = resolveStatus("persona_obedience", true)
        let stThink = resolveStatus("thinking_mode", isThinkingEnabled)
        let stCross = resolveStatus("cross_check", isCrossCheckEnabled)
        let stTools = resolveStatus("tool_schemas", isToolEnabled)
        let stMem = resolveStatus("thread_memory", !memoryPrompt.isEmpty)
        let stGraph = resolveStatus("knowledge_graph", !nodesToUse.isEmpty)
        let stTime = resolveStatus("time_context", true)
        
        var items: [PrePromptItem] = [
            PrePromptItem(
                id: "system_instructions",
                title: "System Instructions & Persona",
                category: "Instructions",
                iconName: "doc.text.fill",
                iconColorName: "blue",
                isEnabled: stSys.isEnabled,
                statusText: stSys.text,
                summary: "Core system prompt and persona instructions defining the AI assistant's role, tone, and behavior.",
                rawContent: systemInst.isEmpty ? "You are a helpful assistant." : systemInst
            ),
            PrePromptItem(
                id: "persona_obedience",
                title: "User Authority & Persona Adoption",
                category: "Directives",
                iconName: "person.badge.shield.checkmark.fill",
                iconColorName: "indigo",
                isEnabled: stPersona.isEnabled,
                statusText: stPersona.text,
                summary: "Directs model to accept user-assigned personas, roles, and relationship dynamics without breaking character.",
                rawContent: personaObediencePrompt
            ),
            PrePromptItem(
                id: "self_learning_memory",
                title: "Self-Learning & Error-Resolution Memory",
                category: "Directives",
                iconName: "wand.and.stars.inverse",
                iconColorName: "orange",
                isEnabled: resolveStatus("self_learning_memory", true).isEnabled,
                statusText: resolveStatus("self_learning_memory", true).text,
                summary: "Instructs AI to save only verified reusable fixes into the writable Learning skill.",
                rawContent: selfLearningPrompt
            ),
            PrePromptItem(
                id: "thinking_mode",
                title: targetThread?.provider == .lmStudio
                    ? "LM Studio Thinking: \(isThinkingEnabled ? "On" : "Off") · \(configuredEffortLevel()) Effort"
                    : "AI Effort: \(configuredEffortLevel())",
                category: "Directives",
                iconName: "brain.head.profile",
                iconColorName: "purple",
                isEnabled: stThink.isEnabled,
                statusText: stThink.text,
                summary: targetThread?.provider == .lmStudio
                    ? "The composer Think pill enables or disables LM Studio reasoning; Effort controls its strength when enabled."
                    : "Controls provider-native reasoning strength, response budget, and fallback reasoning instructions.",
                rawContent: isThinkingEnabled ? "\(exposedSkillInstructions(StarterSkillCatalog.reasoningID))\n[EFFORT: \(configuredEffortLevel())]" : exposedSkillInstructions(StarterSkillCatalog.directResponseID)
            ),
            PrePromptItem(
                id: "cross_check",
                title: "Fact Cross-Check Verification",
                category: "Directives",
                iconName: "checkmark.seal.fill",
                iconColorName: "teal",
                isEnabled: stCross.isEnabled,
                statusText: stCross.text,
                summary: "Directs the AI model to cross-check factual claims against live web search before answering.",
                rawContent: isCrossCheckEnabled ? exposedSkillInstructions(StarterSkillCatalog.crossCheckID) : "Fact cross-check verification is currently disabled in settings."
            ),
            PrePromptItem(
                id: "tool_schemas",
                title: "Tool Router",
                category: "Tools",
                iconName: "wrench.and.screwdriver.fill",
                iconColorName: "orange",
                isEnabled: stTools.isEnabled,
                statusText: stTools.text,
                summary: "Compact routing contract listing only enabled tools; detailed schemas remain in deterministic app-side validation.",
                rawContent: isToolEnabled ? activeInstructions : "Dynamic tool execution is disabled for this chat thread."
            ),
            PrePromptItem(
                id: "thread_memory",
                title: "Thread Summaries (Chat Memory)",
                category: "Memory",
                iconName: "tray.full.fill",
                iconColorName: "cyan",
                isEnabled: stMem.isEnabled,
                statusText: stMem.text,
                summary: "Summarized milestones and conversation history preserved from previous turns in this thread.",
                rawContent: memoryPrompt.isEmpty ? "No thread history summaries recorded yet." : memoryPrompt
            ),
            PrePromptItem(
                id: "knowledge_graph",
                title: "Knowledge Graph Memory",
                category: "Memory",
                iconName: "network",
                iconColorName: "purple",
                isEnabled: stGraph.isEnabled,
                statusText: stGraph.text,
                summary: "Recorded facts, entities, and relational connections about the user stored in the global knowledge graph.",
                rawContent: graphPrompt.isEmpty ? "No persistent knowledge graph entities or relations recorded yet." : graphPrompt
            ),
            PrePromptItem(
                id: "time_context",
                title: "Date, Time & Location Context",
                category: "Context",
                iconName: "clock.fill",
                iconColorName: "green",
                isEnabled: stTime.isEnabled,
                statusText: stTime.text,
                summary: "Real-time system timestamp and timezone location context provided to the model.",
                rawContent: timeContext
            )
        ]
        
        // Dynamically append installed Library APIs into Pre Prompts list
        for def in ChatManager.allLibraryApiDefs {
            let tag = "[API_TOOL: \(def.id)]"
            if systemInst.contains(tag) || systemInst.contains(def.id) || systemInst.contains(def.name) {
                let prePromptId = "library_api_\(def.id)"
                let isOff = self.disabledPrePromptIds.contains(prePromptId)
                let isConfigured = credentialStore.isConfigured("library.\(def.id)")
                let apiKeyInfo = isConfigured ? "\n\nCredential: saved privately on this Mac (not included in model context)." : ""
                
                items.append(
                    PrePromptItem(
                        id: prePromptId,
                        title: def.name,
                        category: "Library APIs",
                        iconName: def.icon,
                        iconColorName: "purple",
                        isEnabled: !isOff,
                        statusText: isOff ? "Temporarily Off" : "Active",
                        summary: def.description,
                        rawContent: def.promptDirective + apiKeyInfo
                    )
                )
            }
        }
        
        return items
    }

    public struct InstalledLibraryApiDef {
        public let id: String
        public let name: String
        public let description: String
        public let category: String
        public let icon: String
        public let promptDirective: String
    }

    public static let allLibraryApiDefs: [InstalledLibraryApiDef] = [
        InstalledLibraryApiDef(id: "weather_api", name: "wttr.in Weather & Climate API", description: "Live weather, temperature, humidity, and forecasts worldwide.", category: "Data & Weather", icon: "sun.max.fill", promptDirective: "\n[ACTIVE API TOOL: wttr.in Weather]: Live weather API active (Endpoint: https://wttr.in/<city>?format=j1). Provide accurate current temperatures, weather conditions, wind speed, and precipitation forecasts."),
        InstalledLibraryApiDef(id: "wiki_api", name: "Wikipedia Article & Knowledge API", description: "Fetches encyclopedic article summaries, historical timelines, and facts.", category: "Knowledge", icon: "book.fill", promptDirective: "\n[ACTIVE API TOOL: Wikipedia REST API]: Wikipedia Knowledge API active (Endpoint: https://en.wikipedia.org/api/rest_v1/page/summary/<topic>). Retrieve encyclopedic facts, verified history, and background summaries."),
        InstalledLibraryApiDef(id: "github_api", name: "GitHub REST & GraphQL API", description: "Deep inspection of open-source repositories, issues, pull requests, and commits.", category: "Developer", icon: "chevron.left.forwardslash.chevron.right", promptDirective: "\n[ACTIVE API TOOL: GitHub API]: GitHub REST API active (Endpoint: https://api.github.com/repos/<owner>/<repo>). Inspect code repositories, commits, issues, and release notes."),
        InstalledLibraryApiDef(id: "coingecko_api", name: "CoinGecko Crypto & Forex Market API", description: "Real-time cryptocurrency quotes, bitcoin exchange rates, and market cap data.", category: "Finance", icon: "chart.line.uptrend.xyaxis", promptDirective: "\n[ACTIVE API TOOL: CoinGecko Crypto API]: Live crypto rates API active (Endpoint: https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd). Format live price metrics and 24h market trends."),
        InstalledLibraryApiDef(id: "hackernews_api", name: "Hacker News Live Tech Trends API", description: "Streams top developer discussions, YC startup stories, and tech news.", category: "Knowledge", icon: "flame.fill", promptDirective: "\n[ACTIVE API TOOL: Hacker News API]: HackerNews Live Feed active (Endpoint: https://hacker-news.firebaseio.com/v0/topstories.json). Summarize top developer news stories."),
        InstalledLibraryApiDef(id: "nasa_api", name: "NASA Astronomy Picture & Space Data API", description: "Fetches daily deep-space imagery, planetary exploration, and satellite space data.", category: "Data & Weather", icon: "star.circle.fill", promptDirective: "\n[ACTIVE API TOOL: NASA Space API]: NASA APOD & Space API active (Endpoint: https://api.nasa.gov/planetary/apod). Retrieve daily astronomy imagery and space telemetry."),
        InstalledLibraryApiDef(id: "openlibrary_api", name: "Open Library Book & Literature Index", description: "Accesses millions of book summaries, author biographies, and ISBN metadata.", category: "Knowledge", icon: "books.vertical.fill", promptDirective: "\n[ACTIVE API TOOL: Open Library API]: Open Library Book Search active (Endpoint: https://openlibrary.org/search.json?q=<query>). Access book summaries, author bios, and ISBNs."),
        InstalledLibraryApiDef(id: "geoip_api", name: "IP-API Global GeoIP & Network Inspection", description: "Inspects IP geolocation coordinates, ISP providers, ASN numbers, and DNS data.", category: "Developer", icon: "network", promptDirective: "\n[ACTIVE API TOOL: IP-API GeoIP]: IP & Network Geolocation API active (Endpoint: http://ip-api.com/json/<ip_or_domain>). Perform DNS, ASN, ISP, and IP geolocation queries."),
        InstalledLibraryApiDef(id: "forex_api", name: "ExchangeRate-API Global Forex Rates", description: "Real-time exchange rate conversions between 160+ world fiat currencies.", category: "Finance", icon: "coloncurrencysign.circle.fill", promptDirective: "\n[ACTIVE API TOOL: ExchangeRate Forex API]: Live Currency Exchange Rates API active (Endpoint: https://open.er-api.com/v6/latest/USD). Convert between 160+ fiat currencies."),
        InstalledLibraryApiDef(id: "arxiv_api", name: "arXiv Scientific Papers & AI Pre-prints", description: "Searches open-access research papers in Computer Science, Quantum Physics, & AI.", category: "Research", icon: "doc.text.fill", promptDirective: "\n[ACTIVE API TOOL: arXiv Scientific Papers API]: arXiv Pre-print Server API active (Endpoint: http://export.arxiv.org/api/query?search_query=<query>). Retrieve research papers and AI pre-prints."),
        InstalledLibraryApiDef(id: "restcountries_api", name: "REST Countries Intelligence API", description: "Retrieves country capitals, populations, languages, currencies, and bounding boxes.", category: "Data & Weather", icon: "globe.americas.fill", promptDirective: "\n[ACTIVE API TOOL: REST Countries API]: Global Country Intelligence API active (Endpoint: https://restcountries.com/v3.1/name/<country>). Query country capitals, populations, and currencies."),
        InstalledLibraryApiDef(id: "spotify_api", name: "Spotify Audio & Music Analytics API", description: "Searches track tempos, artist discographies, album releases, and playlist recommendations.", category: "Media", icon: "music.note", promptDirective: "\n[ACTIVE API TOOL: Spotify Web API]: Spotify Audio Analytics API active (Endpoint: https://api.spotify.com/v1/me/top/tracks). Search track tempos, artist discographies, top tracks, and recommendations."),
        InstalledLibraryApiDef(id: "jsonplaceholder_api", name: "JSONPlaceholder Prototyping REST API", description: "Mock REST API for testing code generation, JSON data fetching, and API prototyping.", category: "Developer", icon: "arrow.triangle.2.circlepath", promptDirective: "\n[ACTIVE API TOOL: JSONPlaceholder REST API]: Prototyping REST API active (Endpoint: https://jsonplaceholder.typicode.com/posts). Use for code generation examples and mock payloads."),
        InstalledLibraryApiDef(id: "pubmed_api", name: "PubMed Biomedical Research Index API", description: "Indexes scientific medical studies, clinical trial papers, and DOI citations.", category: "Research", icon: "cross.case.fill", promptDirective: "\n[ACTIVE API TOOL: PubMed Research API]: PubMed NCBI Search API active (Endpoint: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi). Reference peer-reviewed medical publications."),
        InstalledLibraryApiDef(id: "market_api", name: "AlphaVantage Financial Stock API", description: "Fetches live stock quotes, market trends, ticker valuation multiples, and trading indicators.", category: "Finance", icon: "dollarsign.circle.fill", promptDirective: "\n[ACTIVE API TOOL: AlphaVantage Finance]: AlphaVantage Financial API active (Endpoint: https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=<TICKER>). Analyze ticker symbols and financial data."),
        InstalledLibraryApiDef(id: "apple_notes_api", name: "Apple Notes macOS Integration", description: "Direct native connection to Apple Notes. Create, read, search, append, and organize notes and folders.", category: "macOS Integrations", icon: "note.text", promptDirective: "\n[ACTIVE API TOOL: Apple Notes]: Native Apple Notes access active. Use `apple_notes(action,title,content,folder,query,noteId)` with actions `list`, `search`, `read`, `create`, `append`, `folders`, `delete`, `show`.")
    ]


    
    private enum LearningKind: String {
        case rule
        case howTo = "how-to"
    }

    private struct LearnedRule {
        var id: String
        var kind: LearningKind
        var topic: String
        var content: String
    }

    private func normalizedLearningTopic(_ rawTopic: String?, fallback content: String) -> String {
        let source = rawTopic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? rawTopic!
            : content.components(separatedBy: CharacterSet(charactersIn: ".:\n")).first ?? content
        let cleaned = source
            .replacingOccurrences(of: #"[#\[\]\r\n]+"#, with: " ", options: .regularExpression)
            .split { $0.isWhitespace }
            .prefix(6)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "General" : String(cleaned.prefix(60))
    }

    private func learnedRules(from instructions: String) -> [LearnedRule] {
        guard let markerRange = instructions.range(of: StarterSkillCatalog.learningRulesMarker) else { return [] }
        var rules: [LearnedRule] = []
        var currentTopic = "General"
        for rawLine in instructions[markerRange.upperBound...].split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("### ") {
                currentTopic = normalizedLearningTopic(String(line.dropFirst(4)), fallback: "General")
                continue
            }
            guard let match = line.range(of: #"^- \[([^\]]+)\]\s+(.+)$"#, options: .regularExpression) else { continue }
            let matched = String(line[match])
            guard let close = matched.firstIndex(of: "]") else { continue }
            let idStart = matched.index(matched.startIndex, offsetBy: 3)
            let id = String(matched[idStart..<close])
            let contentStart = matched.index(close, offsetBy: 1)
            var content = matched[contentStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: LearningKind
            if content.hasPrefix("[HOW-TO]") {
                kind = .howTo
                content = String(content.dropFirst("[HOW-TO]".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                kind = .rule
                if content.hasPrefix("[RULE]") {
                    content = String(content.dropFirst("[RULE]".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if !id.isEmpty && !content.isEmpty {
                rules.append(LearnedRule(id: id, kind: kind, topic: currentTopic, content: content))
            }
        }
        return rules
    }

    private func renderedLearningInstructions(base current: String, rules: [LearnedRule]) -> String {
        let marker = StarterSkillCatalog.learningRulesMarker
        let base: String
        if let range = current.range(of: marker) {
            base = String(current[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            base = (StarterSkillCatalog.defaultInstructions(for: StarterSkillCatalog.learningID) ?? current)
                .components(separatedBy: marker).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? current
        }
        func section(title: String, kind: LearningKind, tag: String) -> String? {
            let matching = rules.filter { $0.kind == kind }
            guard !matching.isEmpty else { return nil }
            let topics = Array(Set(matching.map(\.topic))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let topicSections = topics.map { topic in
                let entries = matching.filter { $0.topic == topic }
                    .map { "- [\($0.id)] [\(tag)] \($0.content)" }
                    .joined(separator: "\n")
                return "### \(topic)\n\(entries)"
            }
            return "## \(title)\n" + topicSections.joined(separator: "\n\n")
        }
        var sections: [String] = []
        if let howTos = section(title: "How-tos", kind: .howTo, tag: "HOW-TO") { sections.append(howTos) }
        if let preventionRules = section(title: "Prevention Rules", kind: .rule, tag: "RULE") { sections.append(preventionRules) }
        return sections.isEmpty ? "\(base)\n\n\(marker)" : "\(base)\n\n\(marker)\n\(sections.joined(separator: "\n\n"))"
    }

    @MainActor
    private func performLearningAction(toolRequest: ToolRequest, threadId: UUID) {
        guard let skillIndex = customSkills.firstIndex(where: { $0.id == StarterSkillCatalog.learningID }),
              customSkills[skillIndex].isEnabled else {
            sendLearningResponse(status: "Error: Learning skill is disabled.", success: false, rules: [], threadId: threadId)
            return
        }

        let action = (toolRequest.action ?? "list").lowercased()
        var rules = learnedRules(from: customSkills[skillIndex].instructions)
        let content = toolRequest.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestedID = toolRequest.learningId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestedTopic = toolRequest.learningTopic?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedKind: LearningKind? = {
            switch toolRequest.learningKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "how-to", "howto", "how_to", "procedure": return .howTo
            case "rule", "prevention", "prevention-rule": return .rule
            default: return nil
            }
        }()
        let run = controller(for: threadId).activeRun
        let goal = run?.userGoal.lowercased() ?? ""
        let explicit = [
            "remember this fix", "learn this", "save this lesson", "add this learning",
            "remember this rule", "save this how-to", "save this how to", "remember how to"
        ].contains { goal.contains($0) }
        let verifiedRecovery = !(run?.failedToolCalls.isEmpty ?? true) && !(run?.completedToolCalls.isEmpty ?? true)
        let hardWonSolution = pendingHowToThreadIds.contains(threadId) || ((run?.failedToolCalls.count ?? 0) >= 2 && !(run?.completedToolCalls.isEmpty ?? true))
        var status: String
        var success = true

        switch action {
        case "list":
            let howToCount = rules.filter { $0.kind == .howTo }.count
            status = rules.isEmpty ? "No reusable learnings are saved." : "Loaded \(rules.count) reusable learnings, including \(howToCount) How-to\(howToCount == 1 ? "" : "s")."
        case "append":
            guard explicit || verifiedRecovery || hardWonSolution else {
                sendLearningResponse(status: "Error: A learning can be appended only after explicit user confirmation or a tool failure followed by a verified successful correction.", success: false, rules: rules, threadId: threadId)
                return
            }
            let kind = hardWonSolution ? LearningKind.howTo : (requestedKind ?? .rule)
            let topic = normalizedLearningTopic(requestedTopic, fallback: content)
            guard kind != .howTo || explicit || hardWonSolution else {
                sendLearningResponse(status: "Error: A How-to requires explicit user instruction or a verified difficult run with multiple failed attempts before success.", success: false, rules: rules, threadId: threadId)
                return
            }
            let maximumLength = kind == .howTo ? 1_200 : 600
            guard content.count >= 8 && content.count <= maximumLength else {
                sendLearningResponse(status: "Error: \(kind == .howTo ? "How-to" : "Learning") content must be between 8 and \(maximumLength) characters.", success: false, rules: rules, threadId: threadId)
                return
            }
            let sensitive = ["password", "api key", "secret key", "private key", "bearer token"].contains { content.lowercased().contains($0) }
            guard !sensitive else {
                sendLearningResponse(status: "Error: Credentials and secrets cannot be stored as learnings.", success: false, rules: rules, threadId: threadId)
                return
            }
            if let duplicateIndex = rules.firstIndex(where: { $0.content.caseInsensitiveCompare(content) == .orderedSame }) {
                if kind == .howTo { rules[duplicateIndex].kind = .howTo }
                rules[duplicateIndex].topic = topic
                status = "That \(kind == .howTo ? "How-to" : "learning") already exists; no duplicate was added."
            } else {
                let id = String(UUID().uuidString.lowercased().prefix(8))
                rules.append(LearnedRule(id: id, kind: kind, topic: topic, content: content))
                status = "Saved verified \(kind == .howTo ? "How-to" : "learning") \(id) under \(topic)."
            }
        case "update":
            guard !requestedID.isEmpty, !content.isEmpty,
                  let index = rules.firstIndex(where: { $0.id == requestedID }) else {
                sendLearningResponse(status: "Error: update requires an existing learningId and replacement content.", success: false, rules: rules, threadId: threadId)
                return
            }
            let kind = hardWonSolution ? LearningKind.howTo : (requestedKind ?? rules[index].kind)
            let topic = requestedTopic.map { normalizedLearningTopic($0, fallback: content) } ?? rules[index].topic
            let maximumLength = kind == .howTo ? 1_200 : 600
            guard content.count >= 8 && content.count <= maximumLength else {
                sendLearningResponse(status: "Error: \(kind == .howTo ? "How-to" : "Learning") content must be between 8 and \(maximumLength) characters.", success: false, rules: rules, threadId: threadId)
                return
            }
            let sensitive = ["password", "api key", "secret key", "private key", "bearer token"].contains { content.lowercased().contains($0) }
            guard !sensitive else {
                sendLearningResponse(status: "Error: Credentials and secrets cannot be stored as learnings.", success: false, rules: rules, threadId: threadId)
                return
            }
            rules[index].kind = kind
            rules[index].topic = topic
            rules[index].content = content
            status = "Updated \(kind == .howTo ? "How-to" : "learning") \(requestedID) under \(topic)."
        case "delete":
            let oldCount = rules.count
            rules.removeAll { $0.id == requestedID }
            success = rules.count != oldCount
            status = success ? "Deleted learning \(requestedID)." : "Error: Learning \(requestedID) was not found."
        case "clear":
            rules.removeAll()
            status = "Cleared all reusable learnings."
        default:
            sendLearningResponse(status: "Error: Unsupported learning action. Use list, append, update, delete, or clear.", success: false, rules: rules, threadId: threadId)
            return
        }

        if action != "list", success {
            var refreshedSkills = customSkills
            refreshedSkills[skillIndex].instructions = renderedLearningInstructions(base: refreshedSkills[skillIndex].instructions, rules: rules)
            // Assign the collection so Observation and the Skills UI receive a
            // definite change notification immediately after the learning write.
            customSkills = refreshedSkills
            if action == "append" || action == "update" {
                pendingHowToThreadIds.remove(threadId)
            }
        }
        sendLearningResponse(status: status, success: success, rules: rules, threadId: threadId)
    }

    @MainActor
    private func sendLearningResponse(status: String, success: Bool, rules: [LearnedRule], threadId: UUID) {
        let response: [String: Any] = [
            "tool_response": [
                "success": success,
                "status": status,
                "learnings": rules.map { ["learningId": $0.id, "learningKind": $0.kind.rawValue, "learningTopic": $0.topic, "content": $0.content] }
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        Task { await self.sendToolResponse(text: json, threadId: threadId) }
    }

    @MainActor
    private func performAdvancedMemoryUpdate(toolRequest: ToolRequest, threadId: UUID) {
        guard self.threads.contains(where: { $0.id == threadId }) else { return }
        
        let action = toolRequest.action?.lowercased() ?? "upsert"
        let rawNewNodes = toolRequest.nodes ?? []
        // AMKG stores factual user/entity context only. Operational lessons
        // belong to the Learning skill and are rejected here.
        let newNodes = rawNewNodes.filter {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.category.lowercased() != "learning"
        }
        let newEdges = toolRequest.edges ?? []
        
        var currentNodes = self.globalMemoryNodes
        var currentEdges = self.globalMemoryEdges
        
        if action == "clear" {
            currentNodes = []
            currentEdges = []
        } else if action == "delete" {
            for node in newNodes {
                currentNodes.removeAll(where: { $0.id == node.id })
                currentEdges.removeAll(where: { $0.source == node.id || $0.target == node.id })
            }
            for edge in newEdges {
                currentEdges.removeAll(where: { $0.source == edge.source && $0.target == edge.target && $0.label == edge.label })
            }
        } else { // "upsert"
            for node in newNodes {
                if let idx = currentNodes.firstIndex(where: { $0.id == node.id }) {
                    currentNodes[idx] = node
                } else {
                    currentNodes.append(node)
                }
            }
            let knownIDs = Set(currentNodes.map(\.id))
            for edge in newEdges where knownIDs.contains(edge.source) && knownIDs.contains(edge.target) && !edge.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !currentEdges.contains(where: { $0.source == edge.source && $0.target == edge.target && $0.label == edge.label }) {
                    currentEdges.append(edge)
                }
            }
        }
        let validIDs = Set(currentNodes.map(\.id))
        currentEdges.removeAll { !validIDs.contains($0.source) || !validIDs.contains($0.target) }
        
        self.globalMemoryNodes = currentNodes
        self.globalMemoryEdges = currentEdges
        self.saveGlobalMemory()
        
        for i in 0..<self.threads.count {
            self.threads[i].memoryNodes = currentNodes
            self.threads[i].memoryEdges = currentEdges
        }
        self.saveThreads()
        
        let savedEdgeCount = newEdges.filter { edge in currentEdges.contains(where: { $0.source == edge.source && $0.target == edge.target && $0.label == edge.label }) }.count
        let rejectedLearningCount = rawNewNodes.count - newNodes.count
        let rejectionNote = rejectedLearningCount > 0 ? " Rejected \(rejectedLearningCount) learning node(s); use the Learning skill for operational lessons." : ""
        let statusString = action == "clear" ? "Cleared long-term memory graph." : (action == "delete" ? "Deleted requested memory nodes and edges." : "Successfully saved \(newNodes.count) factual memory nodes and \(savedEdgeCount) valid connections.\(rejectionNote)")
        let responseJSON = """
        {
          "tool_response": {
            "status": "\(statusString)"
          }
        }
        """
        
        Task {
            await self.sendToolResponse(text: responseJSON, threadId: threadId)
        }
    }
    
    @MainActor
    private func performFileSystemAction(toolRequest: ToolRequest, threadId: UUID) async {
        let isFileSystemEnabled = preferences.object(forKey: "enableFileSystem") as? Bool ?? true
        if !isFileSystemEnabled {
            let responseJSON = """
            {
              "tool_response": {
                "status": "Error: File system access tool is disabled by the user in settings."
              }
            }
            """
            Task {
                await self.sendToolResponse(text: responseJSON, threadId: threadId)
            }
            return
        }
        
        guard var action = toolRequest.action else {
            let responseJSON = """
            {
              "tool_response": {
                "status": "Error: Missing action parameter. Allowed: list, create_file, create_folder, read_file."
              }
            }
            """
            Task {
                await self.sendToolResponse(text: responseJSON, threadId: threadId)
            }
            return
        }
        action = Self.canonicalFileSystemAction(action)
        
        var rawPath = toolRequest.path ?? "~"
        // Compatibility router for local models still trained on the legacy
        // shell recipe. Convert this intent to the verified native skill.
        let legacyCommand = (toolRequest.command ?? toolRequest.content ?? "").lowercased()
        let userGoal = threads.first(where: { $0.id == threadId })?.messages.reversed().first(where: { $0.role == .user && !$0.isToolResponse })?.text.lowercased() ?? ""
        let isDownloadsOrganization = userGoal.contains("organize") && userGoal.contains("download")
        if ["execute_command", "command", "terminal", "run_command"].contains(action.lowercased()),
           legacyCommand.contains("downloads"), legacyCommand.contains("mv"), isDownloadsOrganization {
            action = userGoal.contains("image") || userGoal.contains("photo") || userGoal.contains("picture") ? "organize_images" : "organize_downloads"
            rawPath = "~/Downloads"
        }
        // Older local models sometimes invent folder-specific actions such as
        // `organize_documents`. Normalize these to the one verified action.
        switch action.lowercased() {
        case "organize_documents":
            action = "organize_directory"
            rawPath = "~/Documents"
        case "organize_desktop":
            action = "organize_directory"
            rawPath = "~/Desktop"
        default:
            break
        }
        // If a local model invents another `organize_*` name, recover only
        // when the original request identifies a supported folder.
        if action.lowercased().hasPrefix("organize_"),
           let route = FileSystemSkill.routedAction(for: userGoal) {
            action = route.action
            rawPath = route.path
        }
        // FileManager resolves relative paths against the app process working
        // directory, which is `/` for an app launched by LaunchServices. The
        // terminal UI has its own writable working directory, so filesystem
        // tools must resolve relative paths against that same directory.
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        let path: String
        if (expandedPath as NSString).isAbsolutePath {
            path = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
        } else {
            path = URL(fileURLWithPath: terminalCurrentDirectory, isDirectory: true)
                .appendingPathComponent(expandedPath)
                .standardizedFileURL.path
        }
        var statusMessage = ""
        
        switch action {
        case "organize_images":
            statusMessage = FileSystemSkill.organizeImages(in: rawPath == "~" ? "~/Downloads" : rawPath)
        case "organize_downloads":
            statusMessage = FileSystemSkill.organizeDownloads(in: rawPath == "~" ? "~/Downloads" : rawPath)
        case "organize_directory":
            statusMessage = FileSystemSkill.organizeDownloads(in: rawPath)
        case "execute_command", "command", "terminal", "run_command":
            let cmdToRun = toolRequest.command ?? toolRequest.content ?? ""
            guard !cmdToRun.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                statusMessage = "Error: Missing command parameter for execute_command action."
                break
            }
            switch CommandPolicy.evaluate(cmdToRun) {
            case .block(let reason):
                statusMessage = "Error: \(reason)"
            case .requiresConfirmation(let reason):
                statusMessage = "Error: Confirmation required. \(reason)"
            case .allow:
                isTerminalCommandRunning = true
                activeTerminalCommand = cmdToRun
                activeTerminalStatusText = Self.terminalCommandStatusText(for: cmdToRun)
                let liveLogId = startLiveTerminalLog(command: cmdToRun, directory: path, action: "execute_command")
                let execution = await Task.detached {
                    Self.executeTerminalCommand(cmdToRun, in: path) { chunk in
                        Task { @MainActor [weak self] in
                            self?.updateLiveTerminalLog(id: liveLogId, chunk: chunk)
                        }
                    }
                }.value
                finalizeLiveTerminalLog(id: liveLogId, finalOutput: execution.output, exitCode: execution.exitCode, finalDirectory: execution.directory)
                isTerminalCommandRunning = false
                activeTerminalCommand = nil
                activeTerminalStatusText = "Accessing File System & Running Command…"
                terminalCurrentDirectory = execution.directory
                let output = boundedToolOutput(execution.output)
                statusMessage = "Terminal Command Executed (Exit code \(execution.exitCode)):\n$ \(cmdToRun)\nDirectory: \(execution.directory)\n\nOutput:\n\(output)"
            }
            
        case "list":
            do {
                if !fileManager.fileExists(atPath: path) {
                    statusMessage = "Error: Directory does not exist at path: \(rawPath)"
                } else {
                    let items = try fileManager.contentsOfDirectory(atPath: path)
                    if items.isEmpty {
                        statusMessage = "Directory is empty: \(rawPath)"
                    } else {
                        let itemsDetails = items.map { item -> String in
                            var isDir: ObjCBool = false
                            let fullPath = (path as NSString).appendingPathComponent(item)
                            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                                return "\(item) (\(isDir.boolValue ? "Folder" : "File"))"
                            }
                            return item
                        }
                        statusMessage = "Contents of directory \(rawPath):\n" + itemsDetails.joined(separator: "\n")
                    }
                }
            } catch {
                statusMessage = "Error listing directory: \(error.localizedDescription)"
            }
            
        case "create_folder":
            do {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                // Complete the common compound request in one verified native
                // operation even when a small model emits only create_folder:
                // "create folder X and create main.py inside it".
                let filePattern = #"(?i)\b([a-z0-9][a-z0-9._-]*\.[a-z0-9]+)\b"#
                let requestedFilename: String? = {
                    guard userGoal.contains("inside"),
                          let regex = try? NSRegularExpression(pattern: filePattern),
                          let match = regex.firstMatch(in: userGoal, range: NSRange(userGoal.startIndex..., in: userGoal)),
                          let range = Range(match.range(at: 1), in: userGoal) else { return nil }
                    return String(userGoal[range])
                }()
                if let requestedFilename {
                    let filePath = (path as NSString).appendingPathComponent(requestedFilename)
                    if !fileManager.fileExists(atPath: filePath) {
                        guard fileManager.createFile(atPath: filePath, contents: Data()) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                    }
                    guard fileManager.fileExists(atPath: filePath) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    statusMessage = "Successfully created and verified folder: \(path)\nSuccessfully created and verified file: \(filePath)"
                } else {
                    statusMessage = "Successfully created and verified folder: \(path)"
                }
            } catch {
                statusMessage = "Error creating folder: \(error.localizedDescription)"
            }

        case "create_files":
            let requestedFiles = Array((toolRequest.files ?? []).prefix(12))
            guard !requestedFiles.isEmpty else {
                statusMessage = "Error: create_files requires a non-empty files array."
                break
            }
            let preparedFiles: [(path: String, content: String)] = requestedFiles.map {
                (($0.path as NSString).expandingTildeInPath, Self.sanitizedGeneratedFileContent($0.content))
            }
            let invalidFile = preparedFiles.first { item in
                let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || item.content.contains("<|channel") || item.content.contains("<|tool_call") { return true }
                if URL(fileURLWithPath: item.path).pathExtension.lowercased() == "html" {
                    let lower = item.content.lowercased()
                    return !lower.contains("<html") || !lower.contains("</html>")
                }
                return false
            }
            guard invalidFile == nil else {
                statusMessage = "Error: Batch validation failed; no files were written. Check for empty, incomplete, or transport-token content."
                break
            }
            do {
                for item in preparedFiles {
                    try fileManager.createDirectory(atPath: (item.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    try item.content.write(toFile: item.path, atomically: true, encoding: .utf8)
                    let verified = try String(contentsOfFile: item.path, encoding: .utf8)
                    guard verified == item.content else { throw CocoaError(.fileWriteUnknown) }
                    let attributes = try? fileManager.attributesOfItem(atPath: item.path)
                    fileReadCache[item.path] = (attributes?[.modificationDate] as? Date ?? Date(), item.content)
                }
                statusMessage = "Successfully created and verified \(preparedFiles.count) files:\n" + preparedFiles.map(\.path).joined(separator: "\n")
            } catch {
                statusMessage = "Error creating project files: \(error.localizedDescription)"
            }
            
        case "create_file":
            let content = Self.sanitizedGeneratedFileContent(toolRequest.content ?? "")
            do {
                let parentDir = (path as NSString).deletingLastPathComponent
                try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true, attributes: nil)

                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    statusMessage = "Error: Refusing to create an empty file after removing model transport tokens."
                    break
                }
                guard !content.contains("<|channel") && !content.contains("<|tool_call") else {
                    statusMessage = "Error: Refusing to write model transport tokens into a generated file."
                    break
                }
                if URL(fileURLWithPath: path).pathExtension.lowercased() == "html" {
                    let lowerHTML = content.lowercased()
                    guard lowerHTML.contains("<html") && lowerHTML.contains("</html>") else {
                        statusMessage = "Error: HTML verification failed before writing; the document is incomplete."
                        break
                    }
                }
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                let writtenContent = try String(contentsOfFile: path, encoding: .utf8)
                guard writtenContent == content else {
                    statusMessage = "Error: File verification failed after writing: \(rawPath)"
                    break
                }
                let writtenAttributes = try? fileManager.attributesOfItem(atPath: path)
                fileReadCache[path] = (writtenAttributes?[.modificationDate] as? Date ?? Date(), content)
                statusMessage = "Successfully created/updated and verified file at: \(rawPath) (\(content.count) characters)"
            } catch {
                statusMessage = "Error writing file: \(error.localizedDescription)"
            }
            
        case "read_file":
            do {
                if !fileManager.fileExists(atPath: path) {
                    statusMessage = "Error: File does not exist at: \(rawPath)"
                } else {
                    let modifiedAt = (try fileManager.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
                    let content: String
                    if let cached = fileReadCache[path], cached.modifiedAt == modifiedAt {
                        content = cached.content
                    } else {
                        content = try String(contentsOfFile: path, encoding: .utf8)
                        fileReadCache[path] = (modifiedAt, content)
                    }
                    statusMessage = "Contents of file \(rawPath):\n\(content)"
                }
            } catch {
                statusMessage = "Error reading file: \(error.localizedDescription)"
            }
            
        default:
            statusMessage = "Error: Unknown file system action '\(action)'. Allowed: execute_command, list, create_file, create_folder, read_file."
        }
        
        // Log to live terminal
        let cmdDisplay: String
        let exitCodeForLog: Int32
        let isErrorLog: Bool
        switch action {
        case "organize_images":
            cmdDisplay = "organize images in \(rawPath)"
            exitCodeForLog = statusMessage.hasPrefix("Error") ? 1 : 0
            isErrorLog = exitCodeForLog != 0
        case "organize_downloads":
            cmdDisplay = "organize Downloads in \(rawPath)"
            exitCodeForLog = statusMessage.hasPrefix("Error") ? 1 : 0
            isErrorLog = exitCodeForLog != 0
        case "organize_directory":
            cmdDisplay = "organize files in \(rawPath)"
            exitCodeForLog = statusMessage.hasPrefix("Error") ? 1 : 0
            isErrorLog = exitCodeForLog != 0
        case "execute_command", "command", "terminal", "run_command":
            cmdDisplay = toolRequest.command ?? toolRequest.content ?? "(empty)"
            exitCodeForLog = statusMessage.contains("Exit code 0") ? 0 : 1
            isErrorLog = exitCodeForLog != 0
        case "list":
            cmdDisplay = "ls \(rawPath)"
            exitCodeForLog = statusMessage.hasPrefix("Error") ? 1 : 0
            isErrorLog = exitCodeForLog != 0
        case "create_file":
            cmdDisplay = "touch \(rawPath) # write \(toolRequest.content?.count ?? 0) chars"
            exitCodeForLog = statusMessage.hasPrefix("Error") ? 1 : 0
            isErrorLog = exitCodeForLog != 0
        case "create_files":
            cmdDisplay = "create and verify \(toolRequest.files?.count ?? 0) project files"
            exitCodeForLog = statusMessage.hasPrefix("Error") ? 1 : 0
            isErrorLog = exitCodeForLog != 0
        case "create_folder":
            cmdDisplay = "mkdir -p \(rawPath)"
            exitCodeForLog = statusMessage.hasPrefix("Error") ? 1 : 0
            isErrorLog = exitCodeForLog != 0
        case "read_file":
            cmdDisplay = "cat \(rawPath)"
            exitCodeForLog = statusMessage.hasPrefix("Error") ? 1 : 0
            isErrorLog = exitCodeForLog != 0
        default:
            cmdDisplay = "\(action) \(rawPath)"
            exitCodeForLog = 1
            isErrorLog = true
        }
        
        if !["execute_command", "command", "terminal", "run_command"].contains(action) {
            appendTerminalLog(TerminalLogEntry(
                timestamp: Date(),
                command: cmdDisplay,
                directory: path,
                output: statusMessage,
                exitCode: exitCodeForLog,
                isError: isErrorLog,
                action: action
            ))
        }
        
        // Every command, including `open`, must return a tool response only
        // after the process exits. This keeps the model's tool loop alive so
        // it can inspect the actual result and finish the user's request.
        let responseJSON = """
        {
          "tool_response": {
            "success": \(!statusMessage.hasPrefix("Error:")),
            "status": \(Swift.String(reflecting: statusMessage))
          }
        }
        """
        
        if action == "organize_images" || action == "organize_downloads" || action == "organize_directory" || action == "create_folder" || action == "create_file" || action == "create_files" {
            // This action has deterministic completion semantics. Do not ask a
            // small local model for another turn just to summarize it. Apart
            // from unrelated answers, a model can invent unsafe remediation
            // for a simple filesystem error instead of reporting the result.
            appendVerifiedToolSummary(statusMessage, threadId: threadId)
        } else {
            Task { await self.sendToolResponse(text: responseJSON, threadId: threadId) }
        }
    }

    @MainActor
    private func performAppleNotesAction(toolRequest: ToolRequest, threadId: UUID) {
        let action = toolRequest.action ?? "list"
        let fallbackTitle = (toolRequest.title == "Apple Notes" || toolRequest.title == "Tool Request" || toolRequest.title.hasPrefix("Notes:")) ? nil : toolRequest.title
        let noteTitle = toolRequest.path ?? fallbackTitle
        let content = toolRequest.content
        let folder = toolRequest.folder
        let query = toolRequest.query
        let noteId = toolRequest.noteId

        let controller = self.controller(for: threadId)
        let callID = UUID().uuidString
        controller.record(AgentToolResult(callID: callID, toolName: "apple_notes", success: true))

        Task {
            let resultJSON = await Task.detached {
                AppleNotesSkill.execute(
                    action: action,
                    title: noteTitle,
                    content: content,
                    folder: folder,
                    query: query,
                    noteId: noteId
                )
            }.value

            await self.sendToolResponse(text: resultJSON, threadId: threadId)
        }
    }

    @MainActor
    private func performMCPAction(toolRequest: ToolRequest, threadId: UUID) async {
        let rawToolName = toolRequest.mcpTool ?? toolRequest.title.replacingOccurrences(of: "MCP: ", with: "").replacingOccurrences(of: "mcp_", with: "")
        let allTools = MCPServerManager.shared.allTools
        let matchedTool = allTools.first(where: {
            $0.qualifiedName.lowercased() == rawToolName.lowercased() ||
            $0.name.lowercased() == rawToolName.lowercased() ||
            rawToolName.lowercased().hasSuffix("_\($0.name.lowercased())")
        })

        let serverName = toolRequest.mcpServer ?? matchedTool?.serverName ?? MCPServerManager.shared.servers.first(where: { $0.config.isEnabled })?.name ?? ""
        let targetToolName = matchedTool?.name ?? rawToolName.replacingOccurrences(of: "mcp_\(serverName)_", with: "")

        guard !serverName.isEmpty else {
            let errorResp = ["tool_response": ["success": false, "status": "No active MCP server found for tool '\(rawToolName)'."]]
            if let data = try? JSONSerialization.data(withJSONObject: errorResp, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                await self.sendToolResponse(text: json, threadId: threadId)
            }
            return
        }

        // Build arguments dictionary
        var argumentsDict: [String: Any] = [:]
        if let args = toolRequest.mcpArguments {
            for (k, v) in args {
                argumentsDict[k] = Self.convertAgentValueToAny(v)
            }
        }
        if let query = toolRequest.query, argumentsDict["query"] == nil { argumentsDict["query"] = query }
        if let path = toolRequest.path, argumentsDict["path"] == nil { argumentsDict["path"] = path }
        if let content = toolRequest.content, argumentsDict["content"] == nil { argumentsDict["content"] = content }
        if let command = toolRequest.command, argumentsDict["command"] == nil { argumentsDict["command"] = command }

        do {
            let resultOutput = try await MCPServerManager.shared.callTool(
                serverName: serverName,
                toolName: targetToolName,
                arguments: argumentsDict
            )
            let responsePayload: [String: Any] = [
                "tool_response": [
                    "success": true,
                    "status": "MCP tool '\(targetToolName)' executed on '\(serverName)'.",
                    "server": serverName,
                    "tool": targetToolName,
                    "result": resultOutput
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: responsePayload, options: [.sortedKeys]),
               let jsonString = String(data: data, encoding: .utf8) {
                await self.sendToolResponse(text: jsonString, threadId: threadId)
            }
        } catch {
            let errorPayload: [String: Any] = [
                "tool_response": [
                    "success": false,
                    "status": "MCP tool execution failed: \(error.localizedDescription)",
                    "server": serverName,
                    "tool": targetToolName,
                    "error": error.localizedDescription
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: errorPayload, options: [.sortedKeys]),
               let jsonString = String(data: data, encoding: .utf8) {
                await self.sendToolResponse(text: jsonString, threadId: threadId)
            }
        }
    }

    nonisolated private static func convertAgentValueToAny(_ value: AgentValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .boolean(let b): return b
        case .array(let a): return a.map(convertAgentValueToAny)
        case .object(let o):
            var dict: [String: Any] = [:]
            for (k, v) in o { dict[k] = convertAgentValueToAny(v) }
            return dict
        case .null: return NSNull()
        }
    }

    @MainActor
    private func appendVerifiedToolSummary(_ status: String, threadId: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        let succeeded = !status.hasPrefix("Error")
        let toolPayload = """
        {
          "tool_response": {
            "success": \(succeeded),
            "status": \(Swift.String(reflecting: status))
          }
        }
        """
        // Preserve the tool-result boundary used by the transcript UI while
        // keeping it hidden from the visible conversation.
        threads[index].messages.append(ChatMessage(role: .user, text: toolPayload))
        let prefix = status.hasPrefix("Error") ? "I couldn’t complete the filesystem action. " : "Done — "
        threads[index].messages.append(ChatMessage(role: .assistant, text: prefix + status))
        saveThreads()
        controller(for: threadId).complete()
        activeGenerationTasks[threadId]?.cancel()
        activeGenerationTasks[threadId] = nil
        activeGenerationIDs[threadId] = nil
        refreshGenerationState()
    }

    @MainActor
    private func performInternetSearch(toolRequest: ToolRequest, threadId: UUID) {
        var rawQueries: [String] = []
        if let explicitQueries = toolRequest.queries, !explicitQueries.isEmpty {
            rawQueries = explicitQueries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if let single = toolRequest.query?.trimmingCharacters(in: .whitespacesAndNewlines), !single.isEmpty {
            rawQueries = [single]
        }
        guard !rawQueries.isEmpty else { return }

        let rawOriginalRequest = controller(for: threadId).activeRun?.userGoal ?? rawQueries.first ?? ""
        let originalRequest = contextualizedSearchRequest(
            for: threadId,
            currentRequest: rawOriginalRequest
        )
        let previousQueries = searchQueriesByThread[threadId] ?? []

        var plannedQueries: [String] = []
        for rawQ in rawQueries {
            let seed = Self.preparedSearchQuery(
                modelQuery: rawQ,
                originalRequest: originalRequest,
                preferOriginal: false
            )
            guard !seed.isEmpty else { continue }
            for fq in Self.focusedSearchQueries(seedQuery: seed, originalRequest: originalRequest) {
                if !plannedQueries.contains(where: { Self.normalizedSearchQuery($0) == Self.normalizedSearchQuery(fq) }) {
                    plannedQueries.append(fq)
                }
            }
        }

        let previousNormalized = Set(previousQueries.map(Self.normalizedSearchQuery))
        let distinctQueries = plannedQueries.filter { !previousNormalized.contains(Self.normalizedSearchQuery($0)) }
        let availableSearchSlots = max(0, 4 - previousQueries.count)
        let queries = Array(distinctQueries.prefix(availableSearchSlots))
        if queries.isEmpty {
            let reason = previousQueries.count >= 4
                ? "The maximum of four distinct search queries was reached."
                : "Every planned evidence query was already searched in this turn."
            let responseDict: [String: Any] = [
                "success": false,
                "status": reason,
                "original_request": originalRequest,
                "previous_queries": previousQueries,
                "instruction": previousQueries.count >= 4
                    ? "Synthesize the best supported answer now. Clearly identify any remaining evidence gaps; do not search again."
                    : "If a material part of the original request is still unsupported, call internet_use once with a meaningfully different, targeted query. Never repeat a previous query."
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: ["tool_response": responseDict], options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else { return }
            Task {
                await self.sendToolResponse(
                    text: json,
                    threadId: threadId,
                    forceDirectAnswer: true
                )
            }
            return
        }
        searchQueriesByThread[threadId, default: []].append(contentsOf: queries)
        
        let isSearchEnabled = preferences.object(forKey: "enableInternetSearch") as? Bool ?? true
        if !isSearchEnabled {
            let results = "Error: Web search is disabled by the user in settings."
            let responseDict: [String: Any] = [
                "success": false,
                "status": results,
                "search_results": results
            ]
            let payload: [String: Any] = ["tool_response": responseDict]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            
            Task {
                await self.sendToolResponse(text: jsonString, threadId: threadId)
            }
            return
        }
        
        // Search progress is rendered inline in the transcript. Internet
        // search never requires user input, so it must not open ToolCardView.
        self.toolRequestManager.beginProcessing(threadId: threadId)
        
        Task {
            let outcome = await self.searchWeb(
                queries: queries,
                allowAutomaticRefinement: previousQueries.count + queries.count < 4
            )
            var allTurnQueries = self.searchQueriesByThread[threadId] ?? queries
            var seenQueries = Set(allTurnQueries.map(Self.normalizedSearchQuery))
            for executedQuery in outcome.queriesUsed {
                if seenQueries.insert(Self.normalizedSearchQuery(executedQuery)).inserted {
                    allTurnQueries.append(executedQuery)
                }
            }
            self.searchQueriesByThread[threadId] = allTurnQueries
            let canSearchAgain = allTurnQueries.count < 4
            
            let status: String
            if outcome.success {
                status = "Live search and source fetching completed."
            } else if canSearchAgain {
                status = "The first search attempt lacked relevant evidence. Refining the search automatically."
            } else {
                status = "Error: \(outcome.text)"
            }
            let responseDict: [String: Any] = [
                "success": outcome.success,
                "status": status,
                "fetched_evidence": outcome.success ? outcome.text : "",
                "original_request": originalRequest,
                "executed_query": queries.first ?? rawQueries.first ?? "",
                "executed_queries": queries,
                "provider_queries": outcome.queriesUsed,
                "successful_queries": outcome.successfulQueries,
                "query_sources": outcome.querySources,
                "search_round": allTurnQueries.count,
                "previous_queries": allTurnQueries,
                "can_search_again": canSearchAgain,
                "verified_source_count": outcome.verifiedSourceCount,
                "source_domains": outcome.domains,
                "coverage": outcome.coverage,
                "instruction": outcome.success
                    ? (canSearchAgain
                        ? "Answer the original request from the fetched evidence with inline markdown links. Present a clean, definitive, verified answer without exposing internal scratchpad reasoning, backtracking, self-corrections, or draft recalculations. Perform all calculations and unit conversions internally and present consistent numbers in a polished table/breakdown."
                        : "Answer the original request from the fetched evidence. Present a clean, definitive, verified answer without exposing internal scratchpad reasoning, backtracking, self-corrections, or draft recalculations. Perform all calculations and unit conversions internally and present consistent numbers in a polished table/breakdown. Prefer primary and authoritative sources, cite supporting pages inline, and preserve every user constraint.")
                    : (canSearchAgain
                        ? "The previous search did not produce relevant fetched evidence. Do not answer from memory. Emit internet_use with one meaningfully different, narrower query aimed at the missing fact; preserve original_request constraints and never repeat previous_queries."
                        : "Do not answer a current-information question from memory. State that relevant live evidence could not be verified after the allowed search rounds and identify the limitation.")
            ]
            let payload: [String: Any] = ["tool_response": responseDict]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                self.toolRequestManager.clearActiveRequest()
                self.toolRequestManager.finishProcessing(threadId: threadId)
                return
            }
            
            self.toolRequestManager.clearActiveRequest()
            // The search phase is complete before answer generation begins.
            // Keeping this true until the model's first token caused both the
            // “Searching web…” and “Thinking…” indicators to appear together.
            self.toolRequestManager.finishProcessing(threadId: threadId)
            await self.sendToolResponse(
                text: jsonString,
                threadId: threadId,
                forceDirectAnswer: !canSearchAgain
            )
        }
    }

    nonisolated private static func preparedSearchQuery(
        modelQuery: String,
        originalRequest: String,
        preferOriginal: Bool
    ) -> String {
        func normalized(_ string: String) -> String {
            string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let original = normalized(originalRequest)
        var proposed = normalized(modelQuery)
        
        let isProposedConversational = isSelfOrCapabilityQuery(proposed) || isNonSearchConversationalOrCapability(proposed)
        let isOriginalConversational = isSelfOrCapabilityQuery(original) || isNonSearchConversationalOrCapability(original)
        
        if isProposedConversational && isOriginalConversational {
            return ""
        }
        
        if proposed.isEmpty || isProposedConversational {
            proposed = original
        }
        
        guard !proposed.isEmpty else { return "" }

        let cleaned = cleanedSearchSubject(proposed)
        return cleaned.isEmpty ? proposed : cleaned
    }

    nonisolated private static func normalizedSearchQuery(_ query: String) -> String {
        query.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum SearchEvidenceDomain {
        case nutrition, health, legal, finance, aiModel, software, product, news, academic, travel, general
    }

    /// Remove conversational filler language while preserving core search keywords
    nonisolated private static func cleanedSearchSubject(_ input: String) -> String {
        var output = input
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let hasComparativeTerm = output.localizedCaseInsensitiveContains("compared") ||
                                 output.localizedCaseInsensitiveContains("versus") ||
                                 output.localizedCaseInsensitiveContains(" vs ") ||
                                 output.localizedCaseInsensitiveContains(" vs. ") ||
                                 output.localizedCaseInsensitiveContains("compare")
        
        if isSelfOrCapabilityQuery(output) && !hasComparativeTerm {
            return ""
        }
        
        // Common typo / spelling corrections for tech and AI terms
        let commonCorrections: [(String, String)] = [
            (#"(?i)\bchatpgt\b"#, "ChatGPT"),
            (#"(?i)\bchatgbt\b"#, "ChatGPT"),
            (#"(?i)\bchatgdp\b"#, "ChatGPT"),
            (#"(?i)\bchagpt\b"#, "ChatGPT"),
            (#"(?i)\bgemmini\b"#, "Gemini"),
            (#"(?i)\bgimini\b"#, "Gemini"),
            (#"(?i)\bclade\b"#, "Claude"),
            (#"(?i)\bcloude\b"#, "Claude"),
            (#"(?i)\bdeepsek\b"#, "DeepSeek"),
            (#"(?i)\bdeekseek\b"#, "DeepSeek"),
            (#"(?i)\bopena\b"#, "OpenAI"),
            (#"(?i)\bopenrouter\b"#, "OpenRouter"),
            (#"(?i)\blmstudio\b"#, "LM Studio")
        ]
        for (pattern, replacement) in commonCorrections {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        
        let leadingPatterns = [
            #"(?i)^please\s+"#,
            #"(?i)^(?:can|could|would|will)\s+you\s+(?:please\s+)?"#,
            #"(?i)^how\s+(?:smart|capable|good|fast|powerful|accurate|advanced)\s+(?:are\s+(?:you|u|they|models?)|is\s+(?:it|this\s+model|the\s+model))\s+(?:compared\s+to|vs\.?|versus|against)?\s*"#,
            #"(?i)^how\s+do\s+(?:you|u)\s+compare\s+(?:to|with|against)\s*"#,
            #"(?i)^compare\s+(?:yourself\s+with|yourself\s+to|you\s+with|you\s+to|u\s+with|u\s+to)\s*"#,
            #"(?i)^i(?:'m|\s+am|\s+m)?\s+(?:gonna|going\s+to|planning\s+to|having|eating|taking|consuming)\s+(?:have|eat|take|consume)?\s*"#,
            #"(?i)^(?:i\s+have|i\s+got|i've\s+got)\s+"#,
            #"(?i)^(?:calculate|compute|estimate|find|get|check|give\s+me|tell\s+me|show\s+me|what\s+are)\s+(?:the\s+)?(?:macros?|macro\s+breakdown|calories?|nutrition(?:al)?\s+(?:values?|facts?)|breakdown)\s+(?:for|of)?\s*"#,
            #"(?i)^i\s+(?:want|wanna|need)\s+(?:you\s+)?to\s+(?:know|find|check|research|explain|look\s+up|list(?:\s+me)?(?:\s+out)?|tell\s+me)\s+"#,
            #"(?i)^i\s+(?:want|wanna|need)\s+to\s+(?:know|find|check|research|look\s+up)\s+"#,
            #"(?i)^(?:search|research|google|look\s+up|find\s+out|find)\s+(?:the\s+web\s+)?(?:for\s+)?"#,
            #"(?i)^(?:tell|show|give|list)\s+me\s+(?:out\s+)?(?:about\s+)?"#,
            #"(?i)^(?:list\s+out|give\s+me\s+a\s+list\s+of|list\s+of|top\s+list\s+of)\s+"#,
            #"(?i)^explain\s+(?:to\s+me\s+)?"#,
            #"(?i)^(?:who|what|where|when|why|how|which)\s+(?:is|are|was|were|does|do|did|can|could|should|would)\s+"#,
            #"(?i)^(?:what\s+are\s+the|what\s+is\s+the|who\s+are\s+the)\s+"#,
            #"(?i)^(?:what\s+else\s+can\s+(?:you|u)\s+do)\b"#,
            #"(?i)^(?:what\s+can\s+(?:you|u)\s+do)\b"#,
            #"(?i)^(?:changes?|differences?)\s+(?:between|in|of)\s+"#,
            #"(?i)^(?:what(?:'s|\s+is)\s+new\s+in)\s+"#,
            #"(?i)^(?:what\s+changed\s+in)\s+"#,
            #"(?i)^(?:compare|contrast)\s+"#
        ]
        for pattern in leadingPatterns {
            output = output.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        let inlinePatterns: [(String, String)] = [
            (#"(?i)\b(?:are\s+u|are\s+you|do\s+u|do\s+you|can\s+u|can\s+you)\b"#, ""),
            (#"(?i)\b(?:latest\s+ones)\b"#, "latest")
        ]
        for (pattern, replacement) in inlinePatterns {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        
        let trailingPatterns = [
            #"(?i)\s+(?:and\s+)?(?:include|provide|list)\s+(?:the\s+)?(?:sources?|citations?)(?:\s+links?)?.*$"#,
            #"(?i)\s+(?:and\s+)?cite\s+(?:the\s+)?sources?.*$"#,
            #"(?i)\s+(?:in|as)\s+(?:a\s+)?(?:table|bullet\s+list|short\s+answer|detailed\s+answer).*$"#,
            #"(?i)\s+(?:and\s+)?(?:summari[sz]e|explain)\s+(?:the\s+)?(?:results?|findings?).*$"#,
            #"(?i)\s+(?:and\s+)?tell\s+me\s+(?:what\s+you\s+found|the\s+answer).*$"#,
            #"(?i)\s+(?:and\s+)?(?:give|tell|calculate|compute|estimate|show|what\s+are)\s+(?:me\s+)?(?:the\s+)?(?:macros?|macro\s+breakdown|calories?|nutrition(?:al)?\s+values?|nutrition\s+facts?).*$"#,
            #"(?i)\s+(?:macros?|nutrition|calories?)\s*(?:please|breakdown|info)?$"#
        ]
        for pattern in trailingPatterns {
            output = output.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return output
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "?.!,\"';:")))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    nonisolated private static func extractedAIModelName(from text: String) -> String {
        var clean = text
        let removePatterns = [
            #"(?i)\bcan\s+(?:i|it|we|you)\s+run\b"#,
            #"(?i)\bhow\s+to\s+run\b"#,
            #"(?i)\brun\s+(?:locally|local)?\b"#,
            #"(?i)\bin\s+my\b"#,
            #"(?i)\bon\s+my\b"#,
            #"(?i)\bwith\b"#,
            #"(?i)\bfor\b"#,
            #"(?i)\bmacbook\b"#,
            #"(?i)\bm5\b"#,
            #"(?i)\bm4\b"#,
            #"(?i)\bm3\b"#,
            #"(?i)\bm2\b"#,
            #"(?i)\bm1\b"#,
            #"(?i)\bair\b"#,
            #"(?i)\bpro\b"#,
            #"(?i)\bmax\b"#,
            #"(?i)\bultra\b"#,
            #"(?i)\b16gb\b"#,
            #"(?i)\b8gb\b"#,
            #"(?i)\b24gb\b"#,
            #"(?i)\b32gb\b"#,
            #"(?i)\b64gb\b"#,
            #"(?i)\b128gb\b"#,
            #"(?i)\bram\b"#,
            #"(?i)\bmemory\b"#,
            #"(?i)\bcompatibility\b"#,
            #"(?i)\brequirements\b"#
        ]
        for pattern in removePatterns {
            clean = clean.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        clean = clean
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "?.!,\"';:-_")))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return clean.isEmpty ? text : clean
    }

    nonisolated private static func evidenceDomain(for text: String) -> SearchEvidenceDomain {
        let lower = text.lowercased()
        func contains(_ terms: [String]) -> Bool { terms.contains { lower.contains($0) } }
        if contains(["glimmer", "llama", "deepseek", "mistral", "gemma", "qwen", "phi", "starcoder", "codellama", "wizardlm", "vicuna", "yi-", "command r", "quantiz", "gguf", "mlx", "ollama", "vram", "parameter", "airllm", "exl2", "awq", "gptq", " 7b", " 8b", " 12b", " 13b", " 14b", " 27b", " 30b", " 32b", " 70b", "local llm", "run local", "run model", "can i run", "can it run"]) {
            return .aiModel
        }
        if contains(["macro", "calorie", "nutrition", "protein", "carbohydrate", "dietary", "fooddata"]) { return .nutrition }
        if contains([
            "medical", "health", "symptom", "diagnos", "treatment", "medicine", "drug", "disease", "clinical",
            "benefits of eating", "benefits of drinking", "health benefits", "side effects", "is it safe to eat",
            "is it safe to drink", "dosage", "drug interaction", "antioxidant", "inflammation", "blood pressure",
            "cholesterol", "immune system", "digestive health"
        ]) { return .health }
        if contains(["law", "legal", "statute", "regulation", "court", "rights", "visa rule", "tax rule"]) { return .legal }
        if contains(["stock", "share price", "earnings", "investment", "finance", "market cap", "sec filing", "fund"]) { return .finance }
        if contains(["api", "sdk", "framework", "library", "software", "version", "release notes", "programming", "code", "swift", "python", "javascript"]) { return .software }
        if contains(["news", "latest", "today", "current event", "election", "announced", "breaking"]) { return .news }
        if contains(["study", "research paper", "journal", "science", "evidence", "statistics", "systematic review"]) { return .academic }
        if contains(["travel", "hotel", "flight", "train", "tourism", "restaurant", "visit", "itinerary"]) { return .travel }
        if contains(["game", "games", "gaming", "best", "recommend", "buy", "price", "product", "phone", "laptop", "device", "spec", "versus", " vs ", "compare", "compatible", "benchmark"]) { return .product }
        return .general
    }

    nonisolated private static func domainFocusedQueries(subject: String, originalRequest: String) -> [String] {
        let lower = originalRequest.lowercased()
        let year = Calendar.current.component(.year, from: Date())
        switch evidenceDomain(for: "\(subject) \(originalRequest)") {
        case .aiModel:
            let modelName = extractedAIModelName(from: subject.isEmpty ? originalRequest : subject)
            return [
                "\(modelName) model architecture Hugging Face",
                "\(modelName) hardware requirements VRAM GGUF MLX"
            ]
        case .nutrition:
            let cleanSubj = cleanedSearchSubject(subject)
            return ["\(cleanSubj) USDA nutrition facts per 100g calories protein carbohydrates fat"]
        case .health:
            return [
                "\(subject) clinical guideline NIH CDC WHO",
                "\(subject) systematic review evidence"
            ]
        case .legal:
            return [
                "\(subject) official statute law regulation",
                "\(subject) legal analysis"
            ]
        case .finance:
            return [
                "\(subject) financial report \(year)",
                "\(subject) market analysis \(year)"
            ]
        case .software:
            return [
                "\(subject) official documentation API reference",
                "\(subject) release notes"
            ]
        case .product:
            if ["game", "games", "gaming", "play"].contains(where: { lower.contains($0) }) {
                return [
                    "\(subject) release date reviews",
                    "\(subject) gameplay"
                ]
            }
            if ["best", "recommend", "buy", "compare", "versus", " vs ", "benchmark"].contains(where: { lower.contains($0) }) {
                return [
                    "\(subject) review",
                    "\(subject) specs comparison"
                ]
            }
            return ["\(subject) review specs"]
        case .news:
            return [
                "\(subject) latest news",
                "\(subject) updates \(year)"
            ]
        case .academic:
            return [
                "\(subject) research paper arXiv",
                "\(subject) systematic review"
            ]
        case .travel:
            return [
                "\(subject) travel guide",
                "\(subject) logistics guide \(year)"
            ]
        case .general:
            return [subject]
        }
    }

    /// Convert a search seed into high-quality, targeted web queries.
    /// Decomposes multi-entity or comparative queries into focused parallel searches.
    nonisolated private static func focusedSearchQueries(seedQuery: String, originalRequest: String) -> [String] {
        let cleanSeed = cleanedSearchSubject(seedQuery)
        let primaryQuery = cleanSeed.isEmpty ? seedQuery : cleanSeed
        let currentYear = Calendar.current.component(.year, from: Date())
        
        let recognizedAIEntities = [
            "ChatGPT", "GPT-4o", "GPT-4", "Gemini", "Claude",
            "DeepSeek", "Llama", "Mistral", "Qwen", "Apple Intelligence", "Grok"
        ]
        
        let combined = "\(primaryQuery) \(originalRequest)"
        var foundEntities: [String] = []
        for entity in recognizedAIEntities {
            let pattern = #"(?i)\b\#(entity)\b"#
            if combined.range(of: pattern, options: .regularExpression) != nil {
                if !foundEntities.contains(entity) {
                    foundEntities.append(entity)
                }
            }
        }
        
        if foundEntities.count >= 2 {
            var entityQueries: [String] = []
            for entity in foundEntities.prefix(2) {
                entityQueries.append("\(entity) latest capabilities benchmarks \(currentYear)")
            }
            entityQueries.append("\(foundEntities[0]) vs \(foundEntities[1]) comparison")
            return entityQueries
        } else if foundEntities.count == 1 {
            let entity = foundEntities[0]
            let isBenchmarkOrCapability = combined.localizedCaseInsensitiveContains("benchmark") ||
                                          combined.localizedCaseInsensitiveContains("smart") ||
                                          combined.localizedCaseInsensitiveContains("capable") ||
                                          combined.localizedCaseInsensitiveContains("capability") ||
                                          combined.localizedCaseInsensitiveContains("compare")
            if isBenchmarkOrCapability {
                return [
                    "\(entity) latest capabilities benchmarks \(currentYear)",
                    primaryQuery
                ]
            }
        }
        
        let originalLower = originalRequest.lowercased()
        let isChangelog = originalLower.contains("change") || originalLower.contains("difference") ||
                          originalLower.contains("what's new") || originalLower.contains("whats new") ||
                          originalLower.contains("release note") || originalLower.contains("changelog")
        let isBenchmark = originalLower.contains("benchmark") || originalLower.contains("performance") ||
                          originalLower.contains("speed") || originalLower.contains("fps")
        
        // Multi-subject comparison "A and B", "A vs B"
        let vsPattern = #"(?i)^(.+?)\s+(?:vs\.?|versus|compared\s+to|against)\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: vsPattern) {
            let nsString = primaryQuery as NSString
            if let match = regex.firstMatch(in: primaryQuery, range: NSRange(location: 0, length: nsString.length)) {
                var firstPart = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                var secondPart = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                
                firstPart = cleanedSearchSubject(firstPart)
                
                // Inherit entity context if second part is a minor suffix (e.g. "beta 2" when first is "gptk 4 beta 1")
                let firstWords = firstPart.components(separatedBy: " ")
                let secondWords = secondPart.components(separatedBy: " ")
                if firstWords.count > secondWords.count && secondWords.count <= 2 {
                    let sharedWord = secondWords[0].lowercased()
                    if let indexInFirst = firstWords.firstIndex(where: { $0.lowercased() == sharedWord }), indexInFirst > 0 {
                        let entityPrefix = firstWords[..<indexInFirst].joined(separator: " ")
                        secondPart = "\(entityPrefix) \(secondPart)"
                    } else if !firstWords.isEmpty {
                        let entityPrefix = firstWords[0]
                        if !secondPart.lowercased().contains(entityPrefix.lowercased()) {
                            secondPart = "\(entityPrefix) \(secondPart)"
                        }
                    }
                }
                
                let querySuffix: String
                let itemSuffix: String
                if isChangelog {
                    querySuffix = "changes changelog release notes"
                    itemSuffix = "release notes"
                } else if isBenchmark {
                    querySuffix = "benchmarks comparison"
                    itemSuffix = "benchmarks"
                } else {
                    querySuffix = "comparison"
                    itemSuffix = "specs"
                }
                
                if !firstPart.isEmpty && !secondPart.isEmpty {
                    return [
                        "\(firstPart) vs \(secondPart) \(querySuffix)".trimmingCharacters(in: .whitespaces),
                        "\(firstPart) \(itemSuffix)".trimmingCharacters(in: .whitespaces),
                        "\(secondPart) \(itemSuffix)".trimmingCharacters(in: .whitespaces)
                    ]
                }
            }
        }
        
        return [primaryQuery]
    }

    /// A short follow-up such as “what about M5?” needs the preceding subject,
    /// but a complete new request must remain isolated from old chat wording.
    nonisolated private static func contextualizedSearchSeed(currentRequest: String, previousUserRequest: String?) -> String {
        let current = currentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = current.lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "?.!,\"';:")))
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let searchOnlyFollowUps: Set<String> = [
            "use search", "use search and tell me", "search it", "search for it",
            "look it up", "verify it", "check online", "use the web", "browse the web"
        ]
        let isFollowUp = words.count <= 9 && [
            "what about", "how about", "and this", "and that", "does it", "can it",
            "them", "those", "these", "same one", "latest one", "use search",
            "search it", "look it up", "verify it", "check online", "use the web"
        ].contains(where: { lower.contains($0) })
        guard isFollowUp,
              let previous = previousUserRequest?.trimmingCharacters(in: .whitespacesAndNewlines),
              !previous.isEmpty else { return current }
        // A search-only follow-up contributes no new subject. Returning the
        // previous request verbatim prevents the planner from searching for the
        // command itself (for example, “use search and tell me”).
        if searchOnlyFollowUps.contains(lower) { return previous }
        return "\(previous). \(current)"
    }

    private func contextualizedSearchRequest(for threadId: UUID, currentRequest: String) -> String {
        let current = currentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        var userRequests = threads.first(where: { $0.id == threadId })?.messages.compactMap { message -> String? in
            guard message.role == .user,
                  !message.isToolResponse,
                  !message.text.hasPrefix("[System:"),
                  !message.text.hasPrefix("[SYSTEM:") else { return nil }
            let value = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } ?? []
        if userRequests.last?.caseInsensitiveCompare(current) == .orderedSame {
            userRequests.removeLast()
        }
        return Self.contextualizedSearchSeed(
            currentRequest: current,
            previousUserRequest: userRequests.last
        )
    }

    private struct WebSearchResult: Sendable {
        let title: String
        let snippet: String
        let url: String
        var evidence: String = ""
    }

    private struct WebSearchOutcome: Sendable {
        let success: Bool
        let text: String
        let verifiedSourceCount: Int
        let domains: [String]
        let queriesUsed: [String]
        let successfulQueries: [String]
        let coverage: String
        let uncoveredQueries: [String]
        let querySources: [[String: Any]]
    }

    /// Search both providers, favor independent domains, and fetch the result
    /// pages themselves. If the first pass has weak coverage, automatically
    /// run one refined discovery query before returning evidence to the model.
    /// snippets are discovery metadata, not evidence; fetched page text is
    /// what the model may use for factual claims.
    private func searchWeb(queries: [String], allowAutomaticRefinement: Bool) async -> WebSearchOutcome {
        guard !queries.isEmpty else {
            return WebSearchOutcome(success: false, text: "No focused search query was produced.", verifiedSourceCount: 0, domains: [], queriesUsed: [], successfulQueries: [], coverage: "none", uncoveredQueries: [], querySources: [])
        }

        var queriesUsed = queries
        let resultsByQuery = await withTaskGroup(
            of: (Int, String, [WebSearchResult]).self,
            returning: [(query: String, results: [WebSearchResult])].self
        ) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    async let duckResults = self.searchDuckDuckGoResults(query: query)
                    async let bingResults = self.searchBingResults(query: query)
                    return (
                        index,
                        query,
                        Self.rankedDomainDiverseSearchResults(
                            await duckResults + bingResults,
                            query: query
                        )
                    )
                }
            }
            var indexed: [(Int, String, [WebSearchResult])] = []
            for await result in group { indexed.append(result) }
            return indexed.sorted { $0.0 < $1.0 }.map { (query: $0.1, results: $0.2) }
        }
        guard resultsByQuery.contains(where: { !$0.results.isEmpty }) else {
            return WebSearchOutcome(success: false, text: "No search provider returned usable results.", verifiedSourceCount: 0, domains: [], queriesUsed: queriesUsed, successfulQueries: [], coverage: "none", uncoveredQueries: queries, querySources: [])
        }

        let resultsPerQuery = max(4, 12 / max(1, queries.count))
        var selected: [WebSearchResult] = []
        var queryByURL: [String: String] = [:]
        for entry in resultsByQuery {
            for result in entry.results.prefix(resultsPerQuery) {
                guard queryByURL[result.url] == nil else { continue }
                queryByURL[result.url] = entry.query
                selected.append(result)
            }
        }
        var enriched = await Self.fetchEvidence(
            for: selected,
            queryByURL: queryByURL,
            fallbackQuery: queries.joined(separator: " "),
            networkSession: networkSession
        )
        var verified = Self.domainDiverseSearchResults(enriched
            .filter {
                !$0.evidence.isEmpty &&
                Self.searchRelevanceScore($0, query: queryByURL[$0.url] ?? queries.joined(separator: " ")) >= 0.20
            }
            .sorted {
                Self.searchRelevanceScore($0, query: queryByURL[$0.url] ?? "") >
                Self.searchRelevanceScore($1, query: queryByURL[$1.url] ?? "")
            })

        // When fewer than 3 verified links are found, trigger automatic refinement
        // to discover additional relevant sources.
        if allowAutomaticRefinement, verified.count < 3, queriesUsed.count < 4 {
            let query = queries.first ?? queriesUsed.first ?? ""
            let refinement = Self.refinedSearchQuery(from: query)
            if !refinement.isEmpty,
               Self.normalizedSearchQuery(refinement) != Self.normalizedSearchQuery(query),
               !queriesUsed.map(Self.normalizedSearchQuery).contains(Self.normalizedSearchQuery(refinement)) {
                queriesUsed.append(refinement)
                async let refinedDuck = searchDuckDuckGoResults(query: refinement)
                async let refinedBing = searchBingResults(query: refinement)
                let additionalDuck = await refinedDuck
                let additionalBing = await refinedBing
                let results = Self.rankedDomainDiverseSearchResults(
                    (resultsByQuery.first?.results ?? []) + additionalDuck + additionalBing,
                    query: refinement
                )
                let fetchedURLs = Set(enriched.map(\.url))
                let additions = results.filter { !fetchedURLs.contains($0.url) }.prefix(max(3, 8 - verified.count))
                for result in additions { queryByURL[result.url] = refinement }
                enriched.append(contentsOf: await Self.fetchEvidence(
                    for: Array(additions),
                    queryByURL: queryByURL,
                    fallbackQuery: refinement,
                    networkSession: networkSession
                ))
                verified = Self.domainDiverseSearchResults(enriched.filter {
                    !$0.evidence.isEmpty && Self.searchRelevanceScore($0, query: queryByURL[$0.url] ?? query) >= 0.20
                }).sorted {
                    Self.searchRelevanceScore($0, query: queryByURL[$0.url] ?? query) >
                    Self.searchRelevanceScore($1, query: queryByURL[$1.url] ?? query)
                }
            }
        }

        // If verified page evidence still has fewer than 3 links, backfill using
        // remaining snippet-backed search results to ensure minimum 3 links requirement.
        if verified.count < 3 {
            var existingURLs = Set(verified.map(\.url))
            var allCandidatePool: [WebSearchResult] = []
            for entry in resultsByQuery {
                for res in entry.results {
                    if queryByURL[res.url] == nil { queryByURL[res.url] = entry.query }
                    allCandidatePool.append(res)
                }
            }
            let candidatesWithSnippets = enriched + allCandidatePool
            let remaining = Self.domainDiverseSearchResults(
                Self.uniqueSearchResults(candidatesWithSnippets)
                    .filter { !existingURLs.contains($0.url) && !$0.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .sorted {
                        Self.searchRelevanceScore($0, query: queryByURL[$0.url] ?? "") >
                        Self.searchRelevanceScore($1, query: queryByURL[$1.url] ?? "")
                    }
            )
            for candidate in remaining {
                guard verified.count < 3 else { break }
                var backfill = candidate
                if backfill.evidence.isEmpty {
                    backfill.evidence = candidate.snippet
                }
                verified.append(backfill)
                existingURLs.insert(backfill.url)
            }
            // If domain diversity was too strict (e.g. niche query on few domains), allow distinct URLs
            if verified.count < 3 {
                let duplicateDomainCandidates = Self.uniqueSearchResults(candidatesWithSnippets)
                    .filter { !existingURLs.contains($0.url) && !$0.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                for candidate in duplicateDomainCandidates {
                    guard verified.count < 3 else { break }
                    var backfill = candidate
                    if backfill.evidence.isEmpty {
                        backfill.evidence = candidate.snippet
                    }
                    verified.append(backfill)
                    existingURLs.insert(backfill.url)
                }
            }
        }

        guard !verified.isEmpty else {
            return WebSearchOutcome(success: false, text: "Search returned pages, but none contained enough query-relevant fetched evidence to support the request.", verifiedSourceCount: 0, domains: [], queriesUsed: queriesUsed, successfulQueries: [], coverage: "none", uncoveredQueries: queries, querySources: [])
        }
        verified = Array(verified.prefix(10))
        let domains = verified.compactMap { URL(string: $0.url)?.host?.replacingOccurrences(of: "www.", with: "") }
        let coveredQueries = Set(verified.compactMap { queryByURL[$0.url] }).count
        let coveredQueryValues = Set(verified.compactMap { queryByURL[$0.url] }.map(Self.normalizedSearchQuery))
        let successfulQueries = queriesUsed.filter {
            coveredQueryValues.contains(Self.normalizedSearchQuery($0))
        }
        let uncoveredQueries = queries.filter { !coveredQueryValues.contains(Self.normalizedSearchQuery($0)) }
        let coverage = coveredQueries == queries.count && verified.count >= queries.count
            ? "strong"
            : (coveredQueries >= max(1, queries.count / 2) ? "moderate" : "weak")
        let formatted = verified.map { result in
            "- Title: \(result.title)\n  Evidence query: \(queryByURL[result.url] ?? queries[0])\n  Snippet: \(result.snippet)\n  URL: \(result.url)\n  Fetched evidence: \(result.evidence)"
        }.joined(separator: "\n\n")

        var querySourcesList: [[String: Any]] = []
        for q in queriesUsed {
            let matched = verified.filter { (queryByURL[$0.url] ?? queries.first) == q }
            let sources = matched.map { ["title": $0.title, "url": $0.url] }
            querySourcesList.append(["query": q, "sources": sources])
        }

        return WebSearchOutcome(success: true, text: formatted, verifiedSourceCount: verified.count, domains: domains, queriesUsed: queriesUsed, successfulQueries: successfulQueries, coverage: coverage, uncoveredQueries: uncoveredQueries, querySources: querySourcesList)
    }

    nonisolated private static func fetchEvidence(
        for selected: [WebSearchResult],
        queryByURL: [String: String],
        fallbackQuery: String,
        networkSession: URLSession
    ) async -> [WebSearchResult] {
        await withTaskGroup(of: (Int, String).self, returning: [WebSearchResult].self) { group in
            for (index, result) in selected.enumerated() {
                let query = queryByURL[result.url] ?? fallbackQuery
                group.addTask {
                    (
                        index,
                        await Self.fetchReadableEvidence(
                            from: result.url,
                            query: query,
                            networkSession: networkSession
                        )
                    )
                }
            }
            var evidenceByIndex: [Int: String] = [:]
            for await (index, evidence) in group { evidenceByIndex[index] = evidence }
            return selected.enumerated().map { index, result in
                WebSearchResult(title: result.title, snippet: result.snippet, url: result.url, evidence: evidenceByIndex[index] ?? "")
            }
        }
    }

    nonisolated private static func refinedSearchQuery(from query: String) -> String {
        let lower = query.lowercased()
        if ["nutrition", "calorie", "protein", "carbohydrate", "dietary"].contains(where: lower.contains) {
            if lower.contains("usda fooddata central") && lower.contains("authoritative nutrient data") { return query }
            return "\(query) USDA FoodData Central authoritative nutrient data"
        }
        if ["crossover", "wine", "proton", "compatib", "playable", "benchmark"].contains(where: lower.contains) {
            if lower.contains("compatibility benchmark test results official") { return query }
            return "\(query) compatibility benchmark test results official"
        }
        if ["api", "sdk", "framework", "library", "software", "version"].contains(where: lower.contains) {
            if lower.contains("official documentation current version") { return query }
            return "\(query) official documentation current version"
        }
        if ["medical", "health", "treatment", "medicine", "symptom"].contains(where: lower.contains) {
            if lower.contains("official clinical guideline systematic review") { return query }
            return "\(query) official clinical guideline systematic review"
        }
        return query
    }

    nonisolated private static func searchRelevanceScore(_ result: WebSearchResult, query: String) -> Double {
        let stopWords: Set<String> = [
            "about", "after", "also", "and", "are", "authoritative", "best", "browser", "can", "current",
            "documentation", "find", "for", "from", "good", "into", "latest", "list", "more", "need", "official",
            "one", "primary", "search", "show", "source", "that", "the", "this", "through", "use", "using", "want", "web", "with"
        ]
        let terms = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter {
            ($0.count >= 3 || $0.range(of: #"^[a-z]\d+$"#, options: .regularExpression) != nil) && !stopWords.contains($0)
        })
        guard !terms.isEmpty else { return 1 }
        let haystack = "\(result.title) \(result.snippet) \(result.url) \(result.evidence)".lowercased()
        let matches = terms.filter { haystack.contains($0) }.count
        var score = Double(matches) / Double(terms.count)
        if let rarest = terms.max(by: { $0.count < $1.count }), haystack.contains(rarest) { score += 0.18 }
        score += sourceAuthorityScore(for: result.url, query: query)
        return min(1.25, score)
    }

    private func searchDuckDuckGoResults(query: String) async -> [WebSearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encodedQuery)") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await networkSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            guard let html = String(data: data, encoding: .utf8) else {
                return []
            }
            let lowerHTML = html.lowercased()
            guard !lowerHTML.contains("anomaly-modal"), !lowerHTML.contains("bots use duckduckgo too") else { return [] }

            var results: [WebSearchResult] = []
            let blocks = html.components(separatedBy: "result__body")
            for block in blocks.dropFirst().prefix(12) {
                let title = extractString(from: block, start: "class=\"result__a\"", end: "</a>")
                let snippet = extractString(from: block, start: "class=\"result__snippet\"", end: "</a>")
                let rawLink = Self.firstHref(in: block, after: "<h2") ?? ""
                let link = Self.normalizedSearchResultURL(rawLink)
                if !title.isEmpty, !snippet.isEmpty, !link.isEmpty {
                    results.append(WebSearchResult(title: title, snippet: snippet, url: link))
                }
            }
            return Self.uniqueSearchResults(results)
        } catch {
            return []
        }
    }

    private func searchBingResults(query: String) async -> [WebSearchResult] {
        guard var components = URLComponents(string: "https://www.bing.com/search") else { return [] }
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: "12")]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await networkSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else { return [] }
            var results: [WebSearchResult] = []
            for block in html.components(separatedBy: "<li class=\"b_algo\"").dropFirst().prefix(12) {
                let title = extractString(from: block, start: "<h2", end: "</h2>")
                let snippet = extractString(from: block, start: "<div class=\"b_caption\"", end: "</div>")
                let rawLink = Self.firstHref(in: block, after: "<h2") ?? ""
                let link = Self.normalizedSearchResultURL(rawLink)
                if !title.isEmpty, !snippet.isEmpty, !link.isEmpty {
                    results.append(WebSearchResult(title: title, snippet: snippet, url: link))
                }
            }
            return Self.uniqueSearchResults(results)
        } catch { return [] }
    }

    nonisolated private static func uniqueSearchResults(_ results: [WebSearchResult]) -> [WebSearchResult] {
        var seen = Set<String>()
        return results.filter { seen.insert($0.url).inserted }
    }

    nonisolated private static func domainDiverseSearchResults(_ results: [WebSearchResult]) -> [WebSearchResult] {
        let unique = uniqueSearchResults(results)
        var perDomain: [String: Int] = [:]
        return unique.filter { result in
            let domain = URL(string: result.url)?.host?.lowercased() ?? result.url.lowercased()
            let count = perDomain[domain, default: 0]
            guard count < 1 else { return false }
            perDomain[domain] = count + 1
            return true
        }
    }

    nonisolated private static func rankedDomainDiverseSearchResults(
        _ results: [WebSearchResult],
        query: String
    ) -> [WebSearchResult] {
        domainDiverseSearchResults(
            uniqueSearchResults(results).sorted {
                searchRelevanceScore($0, query: query) > searchRelevanceScore($1, query: query)
            }
        )
    }

    nonisolated private static func sourceAuthorityScore(for rawURL: String, query: String) -> Double {
        guard let host = URL(string: rawURL)?.host?.lowercased() else { return 0 }
        var score = 0.0
        if host.hasSuffix(".gov") || host.contains(".gov.") { score += 0.22 }
        if host.hasSuffix(".edu") || host.contains(".edu.") { score += 0.16 }
        if ["who.int", "pubmed.ncbi.nlm.nih.gov", "pmc.ncbi.nlm.nih.gov", "doi.org"].contains(where: host.contains) {
            score += 0.20
        }
        if ["developer.apple.com", "learn.microsoft.com", "docs.github.com", "docs.python.org", "swift.org"].contains(where: host.contains) {
            score += 0.18
        }
        let lowerQuery = query.lowercased()
        if lowerQuery.contains("official"), !host.contains("reddit.com"), !host.contains("pinterest.") {
            score += 0.04
        }
        if ["pinterest.", "quora.com", "facebook.com", "instagram.com", "tiktok.com"].contains(where: host.contains) {
            score -= 0.20
        }
        return score
    }

    nonisolated private static func firstHref(in html: String, after marker: String) -> String? {
        guard let markerRange = html.range(of: marker) else { return nil }
        let tail = html[markerRange.lowerBound...]
        guard let hrefRange = tail.range(of: #"href\s*=\s*[\"'][^\"']+[\"']"#, options: .regularExpression) else { return nil }
        let attribute = String(tail[hrefRange])
        guard let equals = attribute.firstIndex(of: "=") else { return nil }
        return String(attribute[attribute.index(after: equals)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'"))
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    nonisolated private static func normalizedSearchResultURL(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        if let components = URLComponents(string: raw), components.host?.contains("duckduckgo.com") == true,
           let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value { return target }
        if let components = URLComponents(string: raw), components.host?.contains("bing.com") == true,
           let encoded = components.queryItems?.first(where: { $0.name == "u" })?.value,
           encoded.hasPrefix("a1") {
            var base64 = String(encoded.dropFirst(2)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            if let data = Data(base64Encoded: base64), let decoded = String(data: data, encoding: .utf8), decoded.hasPrefix("http") { return decoded }
        }
        return raw.hasPrefix("http") ? raw : ""
    }

    nonisolated private static func convertTablesToMarkdown(_ input: String) -> String {
        var output = input
        let tablePattern = #"(?is)<table[^>]*>(.*?)</table>"#
        guard let tableRegex = try? NSRegularExpression(pattern: tablePattern) else { return input }
        let matches = tableRegex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        
        for match in matches.reversed() {
            guard let tableRange = Range(match.range, in: input),
                  let bodyRange = Range(match.range(at: 1), in: input) else { continue }
            let tableHTML = String(input[bodyRange])
            
            let rowPattern = #"(?is)<tr[^>]*>(.*?)</tr>"#
            guard let rowRegex = try? NSRegularExpression(pattern: rowPattern) else { continue }
            let rowMatches = rowRegex.matches(in: tableHTML, range: NSRange(tableHTML.startIndex..., in: tableHTML))
            
            var markdownRows: [[String]] = []
            for rowMatch in rowMatches {
                guard let cellBodyRange = Range(rowMatch.range(at: 1), in: tableHTML) else { continue }
                let rowContent = String(tableHTML[cellBodyRange])
                let cellPattern = #"(?is)<(?:td|th)[^>]*>(.*?)</(?:td|th)>"#
                guard let cellRegex = try? NSRegularExpression(pattern: cellPattern) else { continue }
                let cellMatches = cellRegex.matches(in: rowContent, range: NSRange(rowContent.startIndex..., in: rowContent))
                let cells = cellMatches.compactMap { cellMatch -> String? in
                    guard let cellRange = Range(cellMatch.range(at: 1), in: rowContent) else { return nil }
                    let rawCell = String(rowContent[cellRange])
                    let clean = rawCell.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
                        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return clean.replacingOccurrences(of: "|", with: "/")
                }
                if !cells.isEmpty {
                    markdownRows.append(cells)
                }
            }
            
            guard !markdownRows.isEmpty else { continue }
            let columnCount = markdownRows.map(\.count).max() ?? 0
            guard columnCount > 0 else { continue }
            
            var tableMarkdown = "\n\n"
            let firstRow = markdownRows[0]
            let headerCells = (0..<columnCount).map { i in i < firstRow.count ? firstRow[i] : "" }
            tableMarkdown += "| " + headerCells.joined(separator: " | ") + " |\n"
            tableMarkdown += "| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |\n"
            
            for row in markdownRows.dropFirst() {
                let cells = (0..<columnCount).map { i in i < row.count ? row[i] : "" }
                tableMarkdown += "| " + cells.joined(separator: " | ") + " |\n"
            }
            tableMarkdown += "\n"
            
            output.replaceSubrange(tableRange, with: tableMarkdown)
        }
        return output
    }

    nonisolated private static func decodeHTMLEntities(_ text: String) -> String {
        var str = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "…")
            .replacingOccurrences(of: "&trade;", with: "™")
            .replacingOccurrences(of: "&copy;", with: "©")
            .replacingOccurrences(of: "&reg;", with: "®")
        
        let numPattern = #"&#(\d+);"#
        if let regex = try? NSRegularExpression(pattern: numPattern) {
            let matches = regex.matches(in: str, range: NSRange(str.startIndex..., in: str))
            for match in matches.reversed() {
                if let fullRange = Range(match.range, in: str),
                   let numRange = Range(match.range(at: 1), in: str),
                   let code = UInt32(str[numRange]),
                   let scalar = UnicodeScalar(code) {
                    str.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }
        return str
    }

    nonisolated private static func convertHTMLToReadableMarkdown(_ rawHTML: String) -> String {
        var html = rawHTML
        
        let removePatterns = [
            #"(?is)<script.*?</script>"#,
            #"(?is)<style.*?</style>"#,
            #"(?is)<noscript.*?</noscript>"#,
            #"(?is)<svg.*?</svg>"#,
            #"(?is)<form.*?</form>"#,
            #"(?is)<nav.*?</nav>"#,
            #"(?is)<header.*?</header>"#,
            #"(?is)<footer.*?</footer>"#,
            #"(?is)<aside.*?</aside>"#,
            #"(?is)<!--.*?-->"#
        ]
        for pattern in removePatterns {
            html = html.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        
        html = convertTablesToMarkdown(html)
        html = html.replacingOccurrences(of: #"(?i)<h[1-3][^>]*>(.*?)</h[1-3]>"#, with: "\n\n## $1\n", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)<h[4-6][^>]*>(.*?)</h[4-6]>"#, with: "\n\n### $1\n", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)<li[^>]*>(.*?)</li>"#, with: "\n- $1", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)</?(?:p|article|section|main|div|tr|ul|ol|dl|dt|dd)[^>]*>"#, with: "\n", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
        html = decodeHTMLEntities(html)
        html = html.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
        html = html.replacingOccurrences(of: #"\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        
        return html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func fetchReadableEvidence(
        from rawURL: String,
        query: String,
        networkSession: URLSession
    ) async -> String {
        guard let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return "" }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-262143", forHTTPHeaderField: "Range")
        do {
            let (data, response) = try await networkSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return "" }
            let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard mime.contains("text") || mime.contains("html") || mime.isEmpty else { return "" }
            let bounded = data.prefix(262_144)
            guard let text = String(data: bounded, encoding: .utf8) ?? String(data: bounded, encoding: .isoLatin1) else { return "" }
            let markdown = convertHTMLToReadableMarkdown(text)
            guard markdown.count >= 60 else { return "" }
            return relevantEvidencePassage(from: markdown, query: query)
        } catch { return "" }
    }

    nonisolated private static func relevantEvidencePassage(from text: String, query: String) -> String {
        let stopWords: Set<String> = [
            "about", "and", "are", "authoritative", "current", "for", "from", "latest",
            "official", "primary", "search", "source", "that", "the", "this", "use", "web", "with",
            "what", "where", "when", "which", "will", "would", "could", "should", "your", "their"
        ]
        let terms = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter {
            ($0.count >= 3 || $0.range(of: #"^[a-z]\d+$"#, options: .regularExpression) != nil) && !stopWords.contains($0)
        })

        let rawParagraphs = text.components(separatedBy: "\n\n")
        var passages: [String] = []
        for p in rawParagraphs {
            let cleanP = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanP.count >= 30 else { continue }
            if cleanP.count > 650 && !cleanP.contains("|") {
                var currentChunk = ""
                cleanP.enumerateSubstrings(in: cleanP.startIndex..<cleanP.endIndex, options: [.bySentences]) { sentence, _, _, _ in
                    guard let sentence else { return }
                    if currentChunk.count + sentence.count > 500 {
                        if !currentChunk.isEmpty { passages.append(currentChunk) }
                        currentChunk = sentence
                    } else {
                        currentChunk += (currentChunk.isEmpty ? "" : " ") + sentence
                    }
                }
                if !currentChunk.isEmpty { passages.append(currentChunk) }
            } else {
                passages.append(cleanP)
            }
        }

        guard !passages.isEmpty else { return String(text.prefix(1_200)) }

        var scoredPassages: [(index: Int, text: String, score: Double)] = []
        for (index, passage) in passages.enumerated() {
            let lower = passage.lowercased()
            
            if lower.contains("@media") || lower.contains("font-family:") ||
               lower.contains("cookie policy") || lower.contains("all rights reserved") ||
               lower.contains("sign in to your account") || lower.contains("subscribe to our newsletter") {
                continue
            }
            
            var score = 0.0
            let matchCount = terms.filter { lower.contains($0) }.count
            guard terms.isEmpty || matchCount > 0 else { continue }
            
            score += terms.isEmpty ? 0.1 : (Double(matchCount) / Double(terms.count)) * 1.0
            
            if passage.contains("| --- |") || passage.contains("|") {
                score += 0.35
            } else if passage.hasPrefix("- ") || passage.contains("\n- ") {
                score += 0.15
            }
            
            for term in terms {
                if term.range(of: #"\d"#, options: .regularExpression) != nil && lower.contains(term) {
                    score += 0.20
                }
            }
            
            if passage.count >= 100 && passage.count <= 650 {
                score += 0.10
            }
            
            scoredPassages.append((index, passage, score))
        }

        let topPassages = scoredPassages
            .sorted {
                if $0.score == $1.score { return $0.index < $1.index }
                return $0.score > $1.score
            }
            .prefix(4)
            .sorted { $0.index < $1.index }
            .map(\.text)
            
        guard !topPassages.isEmpty else {
            return String(text.prefix(1_200))
        }
        
        let result = topPassages.joined(separator: "\n\n")
        return String(result.prefix(1_800))
    }
    
    private func extractString(from text: String, start: String, end: String) -> String {
        guard let startRange = text.range(of: start) else { return "" }
        let sub = text[startRange.upperBound...]
        guard let tagStart = sub.range(of: ">") else { return "" }
        let valueSub = sub[tagStart.upperBound...]
        guard let tagEnd = valueSub.range(of: end) else { return "" }
        let raw = String(valueSub[..<tagEnd.lowerBound])
        
        var clean = ""
        var inTag = false
        for char in raw {
            if char == "<" {
                inTag = true
            } else if char == ">" {
                inTag = false
            } else if !inTag {
                clean.append(char)
            }
        }
        
        return clean
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x60;", with: "`")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Unbuffered Just-In-Time SSE Stream Parsers
    @MainActor
    private func parseAndStreamSSE(
        bytes: URLSession.AsyncBytes,
        onChunk: @escaping (String) -> Void
    ) async throws -> Bool {
        var lineBuffer = Data()
        lineBuffer.reserveCapacity(2048)
        var isInsideReasoningTag = false
        var hitOutputLimit = false
        
        for try await byte in bytes {
            if Task.isCancelled { break }
            if byte == 10 { // '\n'
                if !lineBuffer.isEmpty {
                    if let line = String(data: lineBuffer, encoding: .utf8) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data:") {
                            let dataStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                            if dataStr == "[DONE]" {
                                lineBuffer.removeAll(keepingCapacity: true)
                                break
                            }
                            if let data = dataStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first {
                                if let reason = first["finish_reason"] as? String,
                                   ["length", "max_tokens"].contains(reason.lowercased()) {
                                    hitOutputLimit = true
                                }
                                guard let delta = first["delta"] as? [String: Any] else { continue }
                                
                                let reasoning = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String) ?? ""
                                if !reasoning.isEmpty {
                                    if !isInsideReasoningTag {
                                        onChunk("<think>" + reasoning)
                                        isInsideReasoningTag = true
                                    } else {
                                        onChunk(reasoning)
                                    }
                                }
                                
                                if let content = delta["content"] as? String, !content.isEmpty {
                                    if isInsideReasoningTag {
                                        onChunk("</think>\n" + content)
                                        isInsideReasoningTag = false
                                    } else {
                                        onChunk(content)
                                    }
                                }
                            }
                        }
                    }
                    lineBuffer.removeAll(keepingCapacity: true)
                }
            } else if byte != 13 { // ignore '\r'
                lineBuffer.append(byte)
            }
        }
        if isInsideReasoningTag {
            onChunk("</think>")
        }
        return hitOutputLimit
    }

    @MainActor
    private func parseAndStreamGeminiSSE(
        bytes: URLSession.AsyncBytes,
        onChunk: @escaping (String) -> Void
    ) async throws -> Bool {
        let isThinkingEnabled = reasoningIsEnabled()
        var lineBuffer = Data()
        lineBuffer.reserveCapacity(2048)
        var hitOutputLimit = false
        
        for try await byte in bytes {
            if Task.isCancelled { break }
            if byte == 10 { // '\n'
                if !lineBuffer.isEmpty {
                    if let line = String(data: lineBuffer, encoding: .utf8) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("data:") {
                            let dataStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let data = dataStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let candidates = json["candidates"] as? [[String: Any]],
                               let candidate = candidates.first {
                                if let reason = candidate["finishReason"] as? String,
                                   ["MAX_TOKENS", "LENGTH"].contains(reason.uppercased()) {
                                    hitOutputLimit = true
                                }
                                guard let contentObj = candidate["content"] as? [String: Any],
                                      let parts = contentObj["parts"] as? [[String: Any]] else { continue }
                                for part in parts {
                                    guard let text = part["text"] as? String, !text.isEmpty else { continue }
                                    if isThinkingEnabled, (part["thought"] as? Bool) == true {
                                        onChunk("<think>\(text)</think>")
                                    } else {
                                        onChunk(text)
                                    }
                                }
                            }
                        }
                    }
                    lineBuffer.removeAll(keepingCapacity: true)
                }
            } else if byte != 13 {
                lineBuffer.append(byte)
            }
        }
        return hitOutputLimit
    }

    private func updateAssistantMessage(threadId: UUID, messageId: UUID, text: String, saveToDisk: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let threadIndex = self.threads.firstIndex(where: { $0.id == threadId }),
               let msgIndex = self.threads[threadIndex].messages.firstIndex(where: { $0.id == messageId }) {
                self.threads[threadIndex].messages[msgIndex].text = text
                self.threads[threadIndex].messages[msgIndex].generationEndTime = Date()
                if saveToDisk {
                    self.saveThreads()
                }
            }
        }
    }
    
    // Save/Load helpers
    public func saveThreads() {
        var persisted = threads
        for threadIndex in persisted.indices {
            for messageIndex in persisted[threadIndex].messages.indices {
                let message = persisted[threadIndex].messages[messageIndex]
                if message.attachmentID != nil || message.isToolResponse {
                    persisted[threadIndex].messages[messageIndex].attachedImageBase64 = nil
                }
            }
        }
        threadRepository.scheduleSave(persisted, to: saveURL)
    }

    public func flushThreadPersistence() {
        threadRepository.flush()
        if threadRepository.lastErrorDescription() != nil {
            present(.persistenceFailure(operation: "save conversations"))
            Task { await diagnostics.record(category: "persistence", message: "thread save failed") }
        }
    }

    public func exportDiagnostics() async -> Data? {
        try? await diagnostics.exportJSON()
    }

    public func agentImprovementRecommendations() async -> [String] {
        await learningStore.recommendations()
    }
    
    private func loadThreads() {
        guard fileManager.fileExists(atPath: saveURL.path) else { return }
        do {
            self.threads = try threadRepository.load(from: saveURL)
            for threadIndex in self.threads.indices {
                self.threads[threadIndex].isToolUseEnabled = true
                for messageIndex in self.threads[threadIndex].messages.indices {
                    if let attachmentID = self.threads[threadIndex].messages[messageIndex].attachmentID {
                        self.threads[threadIndex].messages[messageIndex].attachedImageBase64 = attachmentStore.load(id: attachmentID)
                    }
                }
            }
            if preferences.object(forKey: "globalDeveloperMode") != nil {
                let isDevSaved = preferences.bool(forKey: "globalDeveloperMode")
                for i in 0..<self.threads.count {
                    self.threads[i].showSystemMessages = isDevSaved
                }
            }
        } catch {
            print("Failed to load threads: \(error)")
            present(.persistenceFailure(operation: "load conversations"))
            Task { await diagnostics.record(category: "persistence", message: "thread load failed") }
        }
    }
    
    private func saveGlobalMemory() {
        do {
            let payload = GlobalMemoryPayload(nodes: globalMemoryNodes, edges: globalMemoryEdges)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: globalMemoryURL, options: .atomic)
        } catch {
            print("Failed to save global memory graph: \(error)")
            present(.persistenceFailure(operation: "save memory"))
            Task { await diagnostics.record(category: "persistence", message: "memory save failed") }
        }
    }
    
    private func loadGlobalMemory() {
        guard fileManager.fileExists(atPath: globalMemoryURL.path) else { return }
        do {
            let data = try Data(contentsOf: globalMemoryURL)
            let payload = try JSONDecoder().decode(GlobalMemoryPayload.self, from: data)
            // Loading is read-only: never rename nodes, create edges, or infer
            // relationships from persisted AMKG data.
            self.globalMemoryNodes = payload.nodes
            self.globalMemoryEdges = payload.edges
        } catch {
            print("Failed to load global memory graph: \(error)")
            present(.persistenceFailure(operation: "load memory"))
            Task { await diagnostics.record(category: "persistence", message: "memory load failed") }
        }
    }

    /// Older builds stored operational lessons as AMKG nodes. Move them into
    /// the writable Learning skill once, then remove their graph edges so the
    /// right sidebar remains a factual user/entity graph.
    private func migrateLegacyLearningNodes() {
        let legacy = globalMemoryNodes.filter { $0.category.lowercased() == "learning" }
        guard !legacy.isEmpty,
              let skillIndex = customSkills.firstIndex(where: { $0.id == StarterSkillCatalog.learningID }) else { return }
        var rules = learnedRules(from: customSkills[skillIndex].instructions)
        for node in legacy where !rules.contains(where: { $0.content.caseInsensitiveCompare(node.label) == .orderedSame }) {
            rules.append(LearnedRule(id: String(UUID().uuidString.lowercased().prefix(8)), kind: .rule, topic: "Imported Learnings", content: node.label))
        }
        customSkills[skillIndex].instructions = renderedLearningInstructions(base: customSkills[skillIndex].instructions, rules: rules)
        let ids = Set(legacy.map(\.id))
        globalMemoryNodes.removeAll { ids.contains($0.id) }
        globalMemoryEdges.removeAll { ids.contains($0.source) || ids.contains($0.target) }
        saveGlobalMemory()
        for index in threads.indices {
            threads[index].memoryNodes = globalMemoryNodes
            threads[index].memoryEdges = globalMemoryEdges
        }
        saveThreads()
    }
    
    // MARK: - Chat Memory Methods
    
    @MainActor
    public func updateChatMemoryText(id: UUID, text: String) {
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].chatMemory = text.isEmpty ? nil : text
            saveThreads()
        }
    }
    
    @MainActor
    public func clearMemoryGraph(id: UUID) {
        self.globalMemoryNodes = []
        self.globalMemoryEdges = []
        self.saveGlobalMemory()
        for i in 0..<threads.count {
            threads[i].memoryNodes = []
            threads[i].memoryEdges = []
        }
        saveThreads()
    }
    


    @MainActor
    public func addManualMemoryNode(label: String, category: String, sourceNodeId: String = "user", targetNodeId: String? = nil, edgeLabel: String? = nil) {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty else { return }
        // Sanitize: lowercase, replace spaces with underscores, strip non-alphanumeric/underscore chars
        let slug = cleanLabel.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
        guard !slug.isEmpty else { return }
        
        let node = MemoryNode(id: slug, label: cleanLabel, category: category)
        if let idx = globalMemoryNodes.firstIndex(where: { $0.id == slug }) {
            globalMemoryNodes[idx] = node
        } else {
            globalMemoryNodes.append(node)
        }
        
        if let target = targetNodeId, !target.isEmpty, let edgeL = edgeLabel, !edgeL.isEmpty {
            // Connect the newly created fact/entity to the selected existing
            // node. The previous implementation connected `user` to the
            // target and left the new node orphaned in the sidebar.
            let edge = MemoryEdge(source: slug, target: target, label: edgeL)
            if !globalMemoryEdges.contains(where: { $0.source == edge.source && $0.target == edge.target && $0.label == edge.label }) {
                globalMemoryEdges.append(edge)
            }
        }
        
        self.saveGlobalMemory()
        for i in 0..<threads.count {
            threads[i].memoryNodes = globalMemoryNodes
            threads[i].memoryEdges = globalMemoryEdges
        }
        self.saveThreads()
    }

    @MainActor
    public func deleteMemoryNode(id: String) {
        globalMemoryNodes.removeAll(where: { $0.id == id })
        globalMemoryEdges.removeAll(where: { $0.source == id || $0.target == id })
        self.saveGlobalMemory()
        for i in 0..<threads.count {
            threads[i].memoryNodes = globalMemoryNodes
            threads[i].memoryEdges = globalMemoryEdges
        }
        self.saveThreads()
    }
    
    @MainActor
    public func clearAllMemoryCompletely() {
        self.globalMemoryNodes = []
        self.globalMemoryEdges = []
        self.saveGlobalMemory()
        
        for i in 0..<threads.count {
            threads[i].chatMemory = nil
            threads[i].memoryNodes = []
            threads[i].memoryEdges = []
        }
        saveThreads()
    }
    
    @MainActor
    public func updateChatMemory(for threadId: UUID) async {
        guard let thread = threads.first(where: { $0.id == threadId }), !thread.messages.isEmpty else { return }
        
        let messages = thread.messages.filter { $0.role == .user || $0.role == .assistant }
        let validMessages = messages.filter { msg in
            let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text != "..." && !text.hasPrefix("[System:") && !text.hasPrefix("[SYSTEM:") && !text.contains("tool_response")
        }
        
        guard !validMessages.isEmpty else { return }
        
        self.isGeneratingMemory = true
        defer { self.isGeneratingMemory = false }
        
        var historyText = ""
        for msg in validMessages {
            let role = msg.role == .user ? "User" : "Assistant"
            historyText += "\(role): \(msg.text)\n\n"
        }
        
        let prompt = """
        Write a short overview summary (a single brief sentence or two) of the following conversation history. Keep it concise, high-level, and focus on the main objective or outcome (for example: "The user asked to build a chess game and it has been built").
        
        Chat Conversation:
        \(historyText)
        
        Provide ONLY the overview text. Do not include any greeting or introduction.
        """
        
        do {
            let summary: String
            switch thread.provider {
            case .gemini:
                let apiKey = self.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !apiKey.isEmpty else { throw NSError(domain: "GeminiError", code: -1, userInfo: [NSLocalizedDescriptionKey: "API Key is empty"]) }
                let model = thread.geminiModelId ?? "gemini-2.5-flash"
                guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
                    throw URLError(.badURL)
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = [
                    "contents": [
                        ["role": "user", "parts": [["text": prompt]]]
                    ],
                    "generationConfig": ["temperature": 0.3]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, _) = try await networkSession.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let candidate = candidates.first,
                   let content = candidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let part = parts.first,
                   let text = part["text"] as? String {
                    summary = text.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    throw NSError(domain: "GeminiError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
                }
                
            case .lmStudio, .mlx:
                let isMLX = thread.provider == .mlx
                let baseURL = isMLX ? self.mlxBaseURL : self.lmStudioBaseURL
                let modelId = isMLX
                    ? (thread.mlxModelId ?? self.mlxModelId ?? self.mlxScanner.models.first?.id ?? "default")
                    : (thread.lmStudioModelId ?? self.lmStudioAvailableModels.first ?? "default")
                guard let url = URL(string: "\(baseURL)/chat/completions") else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = [
                    "model": modelId,
                    "messages": [
                        ["role": "user", "content": prompt]
                    ],
                    "temperature": 0.3,
                    "stream": false
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, _) = try await networkSession.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    summary = content.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    let errDomain = isMLX ? "MLXError" : "LMStudioError"
                    throw NSError(domain: errDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
                }
                
            case .openRouter:
                let apiKey = self.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !apiKey.isEmpty else { throw NSError(domain: "OpenRouterError", code: -1, userInfo: [NSLocalizedDescriptionKey: "API Key is empty"]) }
                let model = thread.openRouterModelId ?? "google/gemini-2.0-flash-001"
                guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = [
                    "model": model,
                    "messages": [
                        ["role": "user", "content": prompt]
                    ],
                    "temperature": 0.3,
                    "max_tokens": 1024,
                    "stream": false
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, _) = try await networkSession.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    summary = content.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    throw NSError(domain: "OpenRouterError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
                }
                
            case .openAI:
                let apiKey = self.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !apiKey.isEmpty else { throw NSError(domain: "OpenAIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "API Key is empty"]) }
                let model = thread.openAIModelId ?? "gpt-4o-mini"
                var cleanBase = self.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanBase.hasSuffix("/") { cleanBase = String(cleanBase.dropLast()) }
                if cleanBase.isEmpty { cleanBase = "https://api.openai.com/v1" }
                guard let url = URL(string: "\(cleanBase)/chat/completions") else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = [
                    "model": model,
                    "messages": [
                        ["role": "user", "content": prompt]
                    ],
                    "max_tokens": 1024,
                    "stream": false
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, _) = try await networkSession.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    summary = content.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    throw NSError(domain: "OpenAIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
                }
            }
            
            if !summary.isEmpty {
                if let idx = self.threads.firstIndex(where: { $0.id == threadId }) {
                    self.threads[idx].chatMemory = summary
                    self.saveThreads()
                }
            }
        } catch {
            print("Error updating chat memory: \(error)")
        }
    }
    
    nonisolated public func extractMimeTypeAndBase64(from input: String) -> (mimeType: String, base64: String) {
        if input.hasPrefix("data:") {
            let parts = input.split(separator: ",")
            if parts.count > 1 {
                let header = String(parts[0])
                let base64Data = String(parts[1])
                let mimePart = header.replacingOccurrences(of: "data:", with: "").replacingOccurrences(of: ";base64", with: "")
                return (mimePart, base64Data)
            }
        }
        return ("image/jpeg", input)
    }
    
    // Pre-analyze an image using Gemini vision if selected model does not support vision input
    private func preAnalyzeImageWithVision(imageBase64: String, promptText: String? = nil) async -> String? {
        let (mimeType, cleanBase64) = extractMimeTypeAndBase64(from: imageBase64)
        guard !cleanBase64.isEmpty else { return nil }
        
        let promptText = promptText ?? "Describe everything visible in this image in detail (subject, objects, text, colors, action) so another text AI model can understand it and answer user questions accurately."
        
        // Option A: Gemini API
        let gKey = self.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !gKey.isEmpty {
            if let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(gKey)") {
                var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Any] = [
                    "contents": [
                        [
                            "role": "user",
                            "parts": [
                                ["text": promptText],
                                ["inlineData": ["mimeType": mimeType, "data": cleanBase64]]
                            ]
                        ]
                    ]
                ]
                if let bodyData = try? JSONSerialization.data(withJSONObject: payload) {
                    request.httpBody = bodyData
                    if let (data, response) = try? await networkSession.data(for: request),
                       let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let candidates = json["candidates"] as? [[String: Any]],
                       let first = candidates.first,
                       let content = first["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let part = parts.first,
                       let text = part["text"] as? String {
                        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !result.isEmpty { return result }
                    }
                }
            }
        }
        
        // Option B: OpenRouter Gemini Free model
        let oKey = self.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !oKey.isEmpty {
            if let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") {
                var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
                request.httpMethod = "POST"
                request.setValue("Bearer \(oKey)", forHTTPHeaderField: "Authorization")
                request.setValue("http://appleint.app", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("appleint", forHTTPHeaderField: "X-Title")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let dataUrl = "data:\(mimeType);base64,\(cleanBase64)"
                let payload: [String: Any] = [
                    "model": "google/gemini-2.0-flash-exp:free",
                    "messages": [
                        [
                            "role": "user",
                            "content": [
                                ["type": "text", "text": promptText],
                                ["type": "image_url", "image_url": ["url": dataUrl]]
                            ]
                        ]
                    ]
                ]
                if let bodyData = try? JSONSerialization.data(withJSONObject: payload) {
                    request.httpBody = bodyData
                    if let (data, response) = try? await networkSession.data(for: request),
                       let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let first = choices.first,
                       let message = first["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !result.isEmpty { return result }
                    }
                }
            }
        }
        
        return nil
    }
}
