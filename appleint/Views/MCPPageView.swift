import SwiftUI
import AppKit

struct MCPPageView: View {
    let accentColor: Color

    @ObservedObject private var mcpManager = MCPServerManager.shared
    @State private var selectedTab: MCPPageTab = .servers
    @State private var editorJSONText: String = ""
    @State private var jsonError: String? = nil
    @State private var saveSuccessToast: Bool = false
    @State private var expandedToolIds: Set<String> = []
    @State private var searchText: String = ""
    @State private var showingAddSheet: Bool = false
    @State private var isAddingServer: Bool = false

    // New server modal fields
    @State private var newServerName: String = ""
    @State private var newServerCommand: String = ""
    @State private var newServerArgs: String = ""
    @State private var newServerURL: String = ""
    @State private var newServerEnvKey: String = ""
    @State private var newServerEnvValue: String = ""

    private enum MCPPageTab: String, CaseIterable, Identifiable {
        case servers = "Servers & Tools"
        case editor = "Edit mcp.json"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        Text("MCP Servers")
                            .font(.largeTitle.bold())
                    }
                    Text("Model Context Protocol servers provide dynamic tools and resources to your assistant via standard mcp.json.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Spacer()

                HStack(spacing: 8) {
                    let connectedCount = mcpManager.servers.filter { if case .connected = $0.status { return true }; return false }.count
                    Text("\(connectedCount)/\(mcpManager.servers.count) servers online")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))

                    Text("\(mcpManager.allTools.count) tools active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.purple.opacity(0.12)))

                    Button {
                        mcpManager.restartAllServers()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mcpManager.isReloading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .rotationEffect(.degrees(mcpManager.isReloading ? 360 : 0))
                                .animation(mcpManager.isReloading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: mcpManager.isReloading)
                            Text("Reload")
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Restart and reload all MCP servers")

                    Button {
                        revealConfigFileInFinder()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Reveal mcp.json in Finder")

                    Menu {
                        Button("Add Filesystem Server (npx)") { addFilesystemTemplate() }
                            .disabled(isAddingServer)
                        Button("Add Fetch Server (uvx)") { addFetchTemplate() }
                            .disabled(isAddingServer)
                        Button("Add SQLite Server (uvx)") { addSQLiteTemplate() }
                            .disabled(isAddingServer)
                        Button("Add Memory Graph Server (npx)") { addMemoryTemplate() }
                            .disabled(isAddingServer)
                        Divider()
                        Button("Add Custom Server…") { showingAddSheet = true }
                            .disabled(isAddingServer)
                    } label: {
                        HStack(spacing: 4) {
                            if isAddingServer {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Adding…")
                            } else {
                                Image(systemName: "plus")
                                Text("Add Server")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)))
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(isAddingServer)
                    .fixedSize()
                }
            }

            // Tab Picker
            Picker("View", selection: $selectedTab) {
                ForEach(MCPPageTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .editor {
                    editorJSONText = mcpManager.rawConfigJSON
                    validateEditorJSON()
                }
            }

            // Content Area
            if selectedTab == .servers {
                serversAndToolsView
            } else {
                jsonEditorView
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            editorJSONText = mcpManager.rawConfigJSON
        }
        .sheet(isPresented: $showingAddSheet) {
            addCustomServerSheet
        }
    }

    // MARK: - Servers & Tools Tab

    private var serversAndToolsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Config Error Alert if any
                if let configErr = mcpManager.configError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("mcp.json configuration error").fontWeight(.semibold).foregroundStyle(.red)
                            Text(configErr).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Fix in Editor") {
                            selectedTab = .editor
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Servers Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("CONFIGURED SERVERS")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if mcpManager.servers.isEmpty {
                        emptyServersCard
                    } else {
                        ForEach(mcpManager.servers) { server in
                            serverCard(server)
                        }
                    }
                }

                // Tools Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("DISCOVERED MCP TOOLS")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !mcpManager.allTools.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                                TextField("Filter tools", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.caption)
                                    .frame(width: 140)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                        }
                    }

                    let filteredTools = mcpManager.allTools.filter {
                        searchText.isEmpty ||
                        $0.name.localizedCaseInsensitiveContains(searchText) ||
                        $0.serverName.localizedCaseInsensitiveContains(searchText) ||
                        $0.description.localizedCaseInsensitiveContains(searchText)
                    }

                    if mcpManager.allTools.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                            Text("No active tools discovered. Enable and connect an MCP server above to expose tools to your models.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else if filteredTools.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.vertical, 20)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredTools) { tool in
                                toolCard(tool)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func serverCard(_ server: MCPServerRuntime) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(server.status.color.opacity(0.14))
                    Image(systemName: server.status.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(server.status.color)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(server.name)
                            .font(.system(size: 15, weight: .bold))
                        Text(server.status.displayText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(server.status.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(server.status.color.opacity(0.12), in: Capsule())
                    }

                    if let cmd = server.config.command {
                        let fullCmd = ([cmd] + (server.config.args ?? [])).joined(separator: " ")
                        Text(fullCmd)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let url = server.config.url {
                        Text(url)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { server.config.isEnabled },
                        set: { mcpManager.toggleServer(named: server.name, isEnabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(server.config.isEnabled ? "Disable server" : "Enable server")

                    Button {
                        mcpManager.restartServer(named: server.name)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .help("Restart this server")
                }
            }

            if case .error(let errorMsg) = server.status {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).font(.caption)
                    Text(errorMsg).font(.caption).foregroundStyle(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.75))
    }

    private func toolCard(_ tool: MCPTool) -> some View {
        let isExpanded = expandedToolIds.contains(tool.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(tool.qualifiedName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text(tool.serverName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }

                    if !tool.description.isEmpty {
                        Text(tool.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                }

                Spacer()

                Button {
                    if isExpanded {
                        expandedToolIds.remove(tool.id)
                    } else {
                        expandedToolIds.insert(tool.id)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PARAMETERS:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    let paramNames = tool.parameterNames
                    if paramNames.isEmpty {
                        Text("None (takes no arguments)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(paramNames, id: \.self) { param in
                            HStack(alignment: .top, spacing: 6) {
                                Text("• \(param)")
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private var emptyServersCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 30))
                .foregroundStyle(.purple)
            Text("No MCP servers configured").font(.headline)
            Text("Add an MCP server via the template menu or edit mcp.json directly to bring external tools (filesystem, APIs, databases, web fetch) to your local and cloud models.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            HStack(spacing: 10) {
                Button("Add Fetch Server (uvx)") { addFetchTemplate() }
                    .buttonStyle(.borderedProminent)
                Button("Add Filesystem Server") { addFilesystemTemplate() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
    }

    // MARK: - JSON Editor Tab

    private var jsonEditorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(mcpManager.configFileURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let err = jsonError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                if saveSuccessToast {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Saved & Reloaded").font(.caption.weight(.semibold)).foregroundStyle(.green)
                    }
                }

                Button("Format JSON") {
                    if let formatted = mcpManager.formatJSONString(editorJSONText) {
                        editorJSONText = formatted
                        validateEditorJSON()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Revert") {
                    editorJSONText = mcpManager.rawConfigJSON
                    validateEditorJSON()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save & Reload") {
                    saveEditorJSON()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(jsonError != nil)
            }

            TextEditor(text: $editorJSONText)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(jsonError != nil ? Color.red.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1))
                .onChange(of: editorJSONText) { _, _ in
                    validateEditorJSON()
                }
        }
    }

    // MARK: - Add Custom Server Sheet

    private var addCustomServerSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Custom MCP Server").font(.headline)
            Text("Configure a local stdio command (e.g. npx, python, uvx) or a remote SSE endpoint.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Server Identifier (e.g. my-tools)", text: $newServerName)
                    .textFieldStyle(.roundedBorder)

                TextField("Command (e.g. npx, uvx, python3)", text: $newServerCommand)
                    .textFieldStyle(.roundedBorder)

                TextField("Arguments (space separated, e.g. -y @modelcontextprotocol/server-filesystem /path)", text: $newServerArgs)
                    .textFieldStyle(.roundedBorder)

                Divider()

                Text("Or Remote SSE URL (optional)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("https://example.com/sse", text: $newServerURL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { showingAddSheet = false }.buttonStyle(.plain)
                Button(isAddingServer ? "Adding…" : "Add Server") {
                    guard !isAddingServer else { return }
                    isAddingServer = true
                    let args = newServerArgs.split(separator: " ").map(String.init)
                    let config = MCPServerConfig(
                        command: newServerCommand.isEmpty ? nil : newServerCommand,
                        args: args.isEmpty ? nil : args,
                        url: newServerURL.isEmpty ? nil : newServerURL
                    )
                    let name = newServerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "custom-server" : newServerName
                    mcpManager.addTemplate(name: name, config: config)
                    showingAddSheet = false
                    editorJSONText = mcpManager.rawConfigJSON
                    isAddingServer = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAddingServer || newServerName.isEmpty || (newServerCommand.isEmpty && newServerURL.isEmpty))
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    // MARK: - Actions & Templates

    private func validateEditorJSON() {
        guard let data = editorJSONText.data(using: .utf8) else {
            jsonError = "Invalid character encoding"
            return
        }
        do {
            _ = try JSONDecoder().decode(MCPConfigFile.self, from: data)
            jsonError = nil
        } catch {
            jsonError = "Invalid mcp.json format: \(error.localizedDescription)"
        }
    }

    private func saveEditorJSON() {
        do {
            try mcpManager.saveRawConfigJSON(editorJSONText)
            saveSuccessToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                saveSuccessToast = false
            }
        } catch {
            jsonError = error.localizedDescription
        }
    }

    private func revealConfigFileInFinder() {
        let url = mcpManager.configFileURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func addFilesystemTemplate() {
        guard !isAddingServer else { return }
        isAddingServer = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let config = MCPServerConfig(
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "\(home)/Desktop"]
        )
        mcpManager.addTemplate(name: "filesystem", config: config)
        editorJSONText = mcpManager.rawConfigJSON
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isAddingServer = false
        }
    }

    private func addFetchTemplate() {
        guard !isAddingServer else { return }
        isAddingServer = true
        let config = MCPServerConfig(
            command: "uvx",
            args: ["mcp-server-fetch"]
        )
        mcpManager.addTemplate(name: "fetch", config: config)
        editorJSONText = mcpManager.rawConfigJSON
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isAddingServer = false
        }
    }

    private func addSQLiteTemplate() {
        guard !isAddingServer else { return }
        isAddingServer = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let config = MCPServerConfig(
            command: "uvx",
            args: ["mcp-server-sqlite", "--db-path", "\(home)/appleint.db"]
        )
        mcpManager.addTemplate(name: "sqlite", config: config)
        editorJSONText = mcpManager.rawConfigJSON
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isAddingServer = false
        }
    }

    private func addMemoryTemplate() {
        guard !isAddingServer else { return }
        isAddingServer = true
        let config = MCPServerConfig(
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"]
        )
        mcpManager.addTemplate(name: "memory", config: config)
        editorJSONText = mcpManager.rawConfigJSON
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isAddingServer = false
        }
    }
}
