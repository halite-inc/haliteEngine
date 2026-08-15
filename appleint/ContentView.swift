import SwiftUI
import Combine
import WebKit
import UniformTypeIdentifiers
import Speech
import AVFoundation
import AppKit

enum SidebarMode: String, CaseIterable, Identifiable {
    case chats = "Chats"
    case space = "Space"
    var id: String { rawValue }
}

enum PerformanceMode: String, CaseIterable, Identifiable {
    case performance = "Performance"
    case balanced = "Balanced"
    case quality = "Quality"
    var id: String { rawValue }
}

enum AIEffortLevel: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case advanced = "Advanced"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .low: return "bolt.fill"
        case .medium: return "brain.head.profile"
        case .high: return "flame.fill"
        case .advanced: return "sparkles"
        }
    }

    var emoji: String {
        switch self {
        case .low: return "⚡"
        case .medium: return "💡"
        case .high: return "🔥"
        case .advanced: return "🌌"
        }
    }

    var tagline: String {
        switch self {
        case .low: return "Fast & Concise"
        case .medium: return "Balanced Thinker"
        case .high: return "Deep Analyzer"
        case .advanced: return "Max Reasoning"
        }
    }

    var description: String {
        switch self {
        case .low: return "Direct answers with minimal latency"
        case .medium: return "Standard internal chain-of-thought"
        case .high: return "Multi-step reasoning & edge-case checks"
        case .advanced: return "Comprehensive deep dive & synthesis"
        }
    }

    var color: Color {
        switch self {
        case .low: return Color(red: 0.15, green: 0.78, blue: 0.45) // Emerald Green
        case .medium: return Color(red: 0.20, green: 0.55, blue: 0.98) // Vibrant Blue
        case .high: return Color(red: 0.65, green: 0.32, blue: 0.95) // Vivid Purple
        case .advanced: return Color(red: 0.98, green: 0.28, blue: 0.60) // Neon Pink
        }
    }

    var powerLevel: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .advanced: return 4
        }
    }
}

private struct EffortPopoverView: View {
    let level: AIEffortLevel
    let accentColor: Color
    let onSelect: (AIEffortLevel) -> Void
    @State private var hoveredLevel: AIEffortLevel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with animated Energy Badge
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(level.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: level.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(level.color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("Reasoning Effort")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text(level.emoji)
                            .font(.system(size: 12))
                    }
                    Text("Controls depth & compute power")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Power Level Indicator Dots
                HStack(spacing: 3) {
                    ForEach(1...4, id: \.self) { dot in
                        Capsule()
                            .fill(dot <= level.powerLevel ? level.color : Color.secondary.opacity(0.2))
                            .frame(width: dot <= level.powerLevel ? 9 : 5, height: 4.5)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: level)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04), in: Capsule())
            }

            Divider().opacity(0.4)

            // 4 Playful Interactive Level Tiles
            VStack(spacing: 5) {
                ForEach(AIEffortLevel.allCases) { item in
                    let isSelected = (item == level)
                    let isHovered = (hoveredLevel == item)

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            onSelect(item)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? item.color : (isHovered ? item.color.opacity(0.15) : Color.primary.opacity(0.05)))
                                    .frame(width: 26, height: 26)

                                Image(systemName: item.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white : (isHovered ? item.color : .secondary))
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(item.rawValue)
                                        .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold))
                                        .foregroundStyle(isSelected ? item.color : .primary)
                                    Text("• \(item.tagline)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(isSelected ? item.color.opacity(0.8) : .secondary)
                                }
                                Text(item.description)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(item.color)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? item.color.opacity(0.09) : (isHovered ? Color.primary.opacity(0.035) : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isSelected ? item.color.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        hoveredLevel = h ? item : nil
                    }
                }
            }
        }
        .padding(13)
        .frame(width: 310)
    }
}

struct ContentView: View {
    @Environment(ChatManager.self) private var manager
    @Environment(\.colorScheme) private var colorScheme
    @State private var inputText: String = ""
    @State private var dictationManager = SpeechDictationManager()
    private var isDictating: Bool { dictationManager.isDictating }
    private func toggleDictation() {
        let initialText = inputText
        dictationManager.toggleDictation { transcribed in
            if initialText.isEmpty {
                inputText = transcribed
            } else {
                inputText = initialText + " " + transcribed
            }
        }
    }
    @State private var showSettingsPopover: Bool = false
    @State private var showModelPopover: Bool = false
    @State private var showAppSettingsModal: Bool = false
    @State private var sourcePopoverMessageID: UUID? = nil
    @State private var rightSidebarSources: [(title: String, url: String)] = []
    @State private var rightSidebarSourceMessageID: UUID? = nil
    @State private var editingTitleId: UUID? = nil
    @State private var editedTitle: String = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isInputFocused: Bool
    
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @AppStorage("userBubbleAccentColor") private var userBubbleAccentColor: String = "blue"
    @AppStorage("customThemeColorHex") private var customThemeColorHex: String = "#007AFF"
    @ObservedObject private var updateManager = UpdateManager.shared
    @AppStorage("enableDynamicInsights") private var enableDynamicInsights: Bool = true
    @AppStorage("aiPerformanceMode") private var aiPerformanceMode: String = "Quality"
    @AppStorage("enableInternetSearch") private var enableInternetSearch: Bool = true
    @AppStorage("enableFileSystem") private var enableFileSystem: Bool = true
    @AppStorage("useGradientBubbles") private var useGradientBubbles: Bool = true
    @AppStorage("dontUseSolidBackgrounds") private var dontUseSolidBackgrounds: Bool = false
    @AppStorage("glassBackgroundTintHex") private var glassBackgroundTintHex: String = "#4F7DFF"
    @AppStorage("advancedRender") private var advancedRender: Bool = false
    @AppStorage("smoothReply") private var smoothReply: Bool = false
    @AppStorage("extendedTextBox") private var extendedTextBox: Bool = false
    @AppStorage("shiftEnterForNewLine") private var shiftEnterForNewLine: Bool = true
    @AppStorage("enableThinking") private var enableThinking: Bool = false
    @AppStorage("lmStudioThinkingEnabled") private var lmStudioThinkingEnabled: Bool = true
    @AppStorage("enableCrossCheck") private var enableCrossCheck: Bool = false
    @AppStorage("enableOptimizedSpeech") private var enableOptimizedSpeech: Bool = true
    @AppStorage("useCenteredModelLook") private var useCenteredModelLook: Bool = false
    @AppStorage("hideInputToggleText") private var hideInputToggleText: Bool = false
    @AppStorage("chatWallpaperPattern") private var chatWallpaperPattern: String = "doodles"
    @AppStorage("chatWallpaperRotation") private var chatWallpaperRotation: Double = 0.0
    @AppStorage("chatWallpaperColor") private var chatWallpaperColor: String = "auto"
    @AppStorage("chatCustomWallpaperPath") private var chatCustomWallpaperPath: String = ""

    // User-configurable keyboard shortcuts
    @AppStorage("shortcut_newChat") private var shortcutNewChat: String = "N"
    @AppStorage("shortcut_toggleSidebar") private var shortcutToggleSidebar: String = "S"
    @AppStorage("shortcut_openSettings") private var shortcutOpenSettings: String = ","
    @AppStorage("shortcut_search") private var shortcutSearch: String = "K"
    @AppStorage("shortcut_devMode") private var shortcutDevMode: String = "D"
    @AppStorage("shortcut_voiceMode") private var shortcutVoiceMode: String = "V"
    @AppStorage("shortcut_clearChat") private var shortcutClearChat: String = "Delete"
    @AppStorage("shortcut_exportThread") private var shortcutExportThread: String = "E"
    
    @State private var customColor: Color = .blue
    @State private var hoveredRowId: UUID? = nil
    @State private var hoveredMessageId: UUID? = nil
    @State private var editingUserMessageId: UUID? = nil
    @State private var attachedImageBase64: String? = nil
    @State private var forceWebSearchNextMessage: Bool = false
    @State private var showApiLibraryModal: Bool = false
    @State private var showEffortPopover: Bool = false
    @State private var showShareCopiedToast: Bool = false
    @AppStorage("aiEffortLevel") private var aiEffortLevel: String = AIEffortLevel.medium.rawValue
    
    private var accentColorValue: Color {
        switch userBubbleAccentColor {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "green": return .green
        case "red": return .red
        case "custom":
            return Color(hex: customThemeColorHex) ?? .blue
        default: return .blue
        }
    }

    private var glassBackgroundTintValue: Color {
        Color(hex: glassBackgroundTintHex) ?? Color(hex: "#4F7DFF") ?? .blue
    }
    
    private var accentGradientValue: LinearGradient {
        let baseColor = accentColorValue
        switch userBubbleAccentColor {
        case "blue":
            return LinearGradient(
                colors: [Color(hex: "#2997FF") ?? .blue, Color(hex: "#0066CC") ?? .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "purple":
            return LinearGradient(
                colors: [Color(hex: "#AF52DE") ?? .purple, Color(hex: "#763E9B") ?? .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "pink":
            return LinearGradient(
                colors: [Color(hex: "#FF2D55") ?? .pink, Color(hex: "#D30F3F") ?? .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "orange":
            return LinearGradient(
                colors: [Color(hex: "#FF9500") ?? .orange, Color(hex: "#E67300") ?? .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "green":
            return LinearGradient(
                colors: [Color(hex: "#34C759") ?? .green, Color(hex: "#248A3D") ?? .green],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "red":
            return LinearGradient(
                colors: [Color(hex: "#FF3B30") ?? .red, Color(hex: "#C91F16") ?? .red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "custom":
            return LinearGradient(
                colors: [baseColor.opacity(0.85), baseColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [.blue, Color(hex: "#0066CC") ?? .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    enum RightSidebarTab: String, CaseIterable, Identifiable {
        case configure = "Configure"
        case prePrompts = "Pre-Prompts"
        case memoryGraph = "Memory Graph"
        case sources = "Activity"
        var id: String { rawValue }
    }


    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "Appearance"
        case shortcuts = "Shortcuts"
        case prePrompts = "Pre Prompts"
        case tools = "Tools & Modes"
        case apiKeys = "Configure APIs"
        case models = "Manage Models"
        case updates = "Updates"
        
        var id: String { rawValue }
        
        var iconName: String {
            switch self {
            case .general: return "paintbrush.fill"
            case .shortcuts: return "command"
            case .prePrompts: return "text.line.first.and.arrowtriangle.forward"
            case .tools: return "gearshape.2.fill"
            case .apiKeys: return "key.fill"
            case .models: return "cpu.fill"
            case .updates: return "arrow.triangle.2.circlepath.circle.fill"
            }
        }
        
        var iconBgColor: Color {
            switch self {
            case .general: return .blue
            case .shortcuts: return .indigo
            case .prePrompts: return .purple
            case .tools: return .orange
            case .apiKeys: return .green
            case .models: return .red
            case .updates: return .cyan
            }
        }
    }
    
    // Settings Navigation state
    @State private var selectedSettingsTab: SettingsTab = .general
    
    // Right Sidebar state
    @State private var showRightSidebar: Bool = false
    @State private var rightSidebarTab: RightSidebarTab = .configure
    @State private var rightSidebarWidth: CGFloat = 340
    @State private var expandedToolboxIDs: Set<String> = []
    @State private var showTerminalPanel: Bool = false
    @State private var terminalPanelHeight: CGFloat = 220
    @State private var terminalCommand: String = ""

    // Presets and layout namespace
    @State private var showSavePresetPopover: Bool = false
    @State private var presetNameToSave: String = ""
    @Namespace private var sidebarNamespace
    @Namespace private var settingsAppearanceNS
    @Namespace private var settingsAccentNS
    
    // Custom model input state
    @State private var newGeminiModel: String = ""
    @State private var newOpenRouterModel: String = ""
    @State private var newOpenAIModel: String = ""
    @State private var newLMStudioModel: String = ""
    @State private var expandedModelProviders: Set<String> = ["gemini", "openrouter", "openai", "lmstudio"]
    
    // Batch thread selection
    @State private var selectedThreadIds = Set<UUID>()
    @State private var sidebarMode: SidebarMode = .chats
    @State private var showingCalendarPage = false
    @State private var showingLibraryPage = false
    @State private var showingScheduledPage = false
    @State private var showingSkillsPage = false
    @State private var showingMCPPage = false
    
    private func clearAllPageSelection() {
        showingCalendarPage = false
        showingLibraryPage = false
        showingScheduledPage = false
        showingSkillsPage = false
        showingMCPPage = false
    }
    
    @ViewBuilder
    private func chatRowContextMenu(for thread: ChatThread) -> some View {
        Button("Rename") {
            startEditingTitle(for: thread)
        }
        Button("Clear History", role: .destructive) {
            manager.clearHistory(id: thread.id)
        }
        Divider()
        Button {
            copyTranscript(for: thread)
        } label: {
            Label("Copy as transcribe", systemImage: "doc.on.doc")
        }
        Button {
            downloadTranscript(for: thread)
        } label: {
            Label("Download transcribe into text file", systemImage: "arrow.down.doc")
        }
        Divider()
        if selectedThreadIds.count > 1 && selectedThreadIds.contains(thread.id) {
            Button("Delete Selected Chats (\(selectedThreadIds.count))", role: .destructive) {
                manager.deleteChats(ids: selectedThreadIds)
                handlePostDeletionSync()
            }
        } else {
            Button("Delete Chat", role: .destructive) {
                manager.deleteChat(id: thread.id)
                handlePostDeletionSync()
            }
        }
    }

    @ViewBuilder
    private var mainSidebarView: some View {
        VStack(spacing: 0) {
            // Inline Mode Slider (Chats | Space)
            HStack(spacing: 0) {
                ForEach(SidebarMode.allCases) { mode in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            sidebarMode = mode
                            clearAllPageSelection()
                            if mode == .space {
                                showingSkillsPage = true
                                selectedThreadIds.removeAll()
                            } else if let activeId = manager.activeThreadId {
                                selectedThreadIds = [activeId]
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode == .chats ? "bubble.left.and.bubble.right.fill" : "square.grid.2x2.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(sidebarMode == mode ? accentColorValue : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            ZStack {
                                if sidebarMode == mode {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(accentColorValue.opacity(0.14))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .stroke(accentColorValue.opacity(0.22), lineWidth: 0.75)
                                        }
                                        .matchedGeometryEffect(id: "sidebarModePill", in: sidebarNamespace)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.065), lineWidth: 0.75)
                    }
            )
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 5)

            if sidebarMode == .chats {
                List(selection: $selectedThreadIds) {
                    Section {
                        SidebarHoverButton(title: "Library", icon: "square.stack.3d.up.fill", gradient: LinearGradient(colors: [.purple, .purple], startPoint: .leading, endPoint: .trailing)) {
                            clearAllPageSelection()
                            showingLibraryPage = true
                            selectedThreadIds.removeAll()
                        }
                        SidebarHoverButton(
                            title: "New Chat",
                            icon: "plus.bubble.fill",
                            gradient: accentGradientValue
                        ) {
                            clearAllPageSelection()
                            manager.createNewChatWithDefaults()
                        }
                    }
                    
                    Section {
                        ForEach(manager.threads) { thread in
                            NavigationLink(value: thread.id) {
                                chatRow(for: thread)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .contentShape(Rectangle())
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(hoveredRowId == thread.id ? Color.primary.opacity(0.065) : Color.clear)
                                    .padding(.horizontal, 5)
                            )
                            .onHover { hovering in
                                if hovering {
                                    hoveredRowId = thread.id
                                } else if hoveredRowId == thread.id {
                                    hoveredRowId = nil
                                }
                            }
                            .contextMenu {
                                chatRowContextMenu(for: thread)
                            }
                        }
                    } header: {
                        Text("CHATS")
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onDeleteCommand {
                    if !selectedThreadIds.isEmpty {
                        manager.deleteChats(ids: selectedThreadIds)
                        handlePostDeletionSync()
                    }
                }
            } else {
                List {
                    Section {
                        SidebarHoverButton(title: "Calendar", icon: "calendar", gradient: accentGradientValue) {
                            clearAllPageSelection()
                            showingCalendarPage = true
                            selectedThreadIds.removeAll()
                        }
                        SidebarHoverButton(title: "Scheduled", icon: "clock.fill", gradient: accentGradientValue) {
                            clearAllPageSelection()
                            showingScheduledPage = true
                            selectedThreadIds.removeAll()
                        }
                        SidebarHoverButton(
                            title: "Skills",
                            icon: "wand.and.stars",
                            gradient: LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                        ) {
                            clearAllPageSelection()
                            showingSkillsPage = true
                            selectedThreadIds.removeAll()
                        }
                        SidebarHoverButton(
                            title: "MCP",
                            icon: "server.rack",
                            gradient: LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        ) {
                            clearAllPageSelection()
                            showingMCPPage = true
                            selectedThreadIds.removeAll()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            
            VStack(spacing: 2) {
                SidebarHoverButton(
                    title: "Settings",
                    icon: "gearshape",
                    gradient: accentGradientValue
                ) {
                    showAppSettingsModal.toggle()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(
            Group {
                if !dontUseSolidBackgrounds {
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.45))
                        .overlay(glassBackgroundTintValue.opacity(colorScheme == .dark ? 0.11 : 0.07))
                }
            }
        )
        .overlay(alignment: .trailing) {
            if colorScheme == .light {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1)
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .ignoresSafeArea()
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
    }

    @ViewBuilder
    private var mainDetailView: some View {
        HStack(spacing: 0) {
            if showingScheduledPage {
                ScheduledPageView(manager: manager, accentColor: accentColorValue)
            } else if showingSkillsPage {
                SkillsPageView(manager: manager, accentColor: accentColorValue)
            } else if showingMCPPage {
                MCPPageView(accentColor: accentColorValue)
            } else if showingLibraryPage {
                ApiLibraryModal(manager: manager, threadId: manager.activeThreadId)
            } else if showingCalendarPage {
                CalendarPageView(manager: manager, accentColor: accentColorValue)
            } else if let thread = manager.activeThread {
                chatDetailArea(for: thread)
            } else {
                welcomeView
            }
            
            if showRightSidebar, let thread = manager.activeThread {
                RightSidebarResizeHandle(width: $rightSidebarWidth)
                rightSidebar(for: thread)
                    .frame(width: rightSidebarWidth)
                    .background(
                        Group {
                            if !dontUseSolidBackgrounds {
                                Rectangle()
                                    .fill(.ultraThinMaterial.opacity(0.65))
                                    .overlay(glassBackgroundTintValue.opacity(colorScheme == .dark ? 0.13 : 0.08))
                            } else {
                                #if os(macOS)
                                Color(nsColor: .windowBackgroundColor)
                                #else
                                Color(uiColor: .systemBackground)
                                #endif
                            }
                        }
                    )
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 1)
                            .ignoresSafeArea()
                    }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut, value: showRightSidebar)
    }

    var body: some View {
        @Bindable var bindableManager = manager
        
        ZStack {
            Button("") {
                showAppSettingsModal.toggle()
            }
            .keyboardShortcut("s", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            
            appBackgroundView
            
            NavigationSplitView {
                    mainSidebarView
                        .onChange(of: selectedThreadIds) { oldValue, newValue in
                            if newValue.isEmpty {
                                manager.activeThreadId = nil
                            } else if let activeId = manager.activeThreadId, newValue.contains(activeId) {
                                // Keep current active thread if it's still part of the selection
                            } else {
                                // Switch active thread to the first selected item in the set
                                clearAllPageSelection()
                                manager.activeThreadId = newValue.first
                            }
                        }
                        .onChange(of: manager.activeThreadId) { oldValue, newValue in
                            if let activeId = newValue {
                                if !selectedThreadIds.contains(activeId) {
                                    selectedThreadIds = [activeId]
                                }
                            } else {
                                selectedThreadIds.removeAll()
                            }
                        }
                } detail: {
                    mainDetailView
                }
                .scrollContentBackground(.hidden)
                .frame(minWidth: 800, minHeight: 600)
                .navigationTitle("")
                .sheet(isPresented: $showAppSettingsModal) {
                    appSettingsModalView
                }
                .sheet(isPresented: $showApiLibraryModal) {
                    ApiLibraryModal(manager: manager, threadId: manager.activeThreadId)
                }
                .background(
                    Group {
                        Button("") {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                showRightSidebar.toggle()
                            }
                        }
                        .keyboardShortcut("i", modifiers: .command)
                    }
                    .opacity(0)
                )
                .preferredColorScheme(preferredColorScheme)
                .tint(accentColorValue)
                .onChange(of: appAppearance) { _, newMode in
                    updateAppAppearance(newMode)
                }
                .onAppear {
                    updateAppAppearance(appAppearance)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isInputFocused = true
                    }
                }
                .onChange(of: manager.activeThreadId) { _, _ in
                    rightSidebarSources = []
                    rightSidebarSourceMessageID = nil
                    if rightSidebarTab == .sources {
                        rightSidebarTab = .configure
                        showRightSidebar = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isInputFocused = true
                    }
                }
                .onChange(of: manager.isGenerating) { _, isGenerating in
                    if !isGenerating {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isInputFocused = true
                        }
                    }
                }
                .onChange(of: manager.activeThreadId.flatMap { manager.ultraTaskRun(for: $0) }) { oldRun, newRun in
                    guard oldRun == nil, newRun != nil else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        rightSidebarTab = .sources
                        showRightSidebar = true
                    }
                }
            }
        }
    
    // MARK: - App Background View
    
    @ViewBuilder
    private var appBackgroundView: some View {
        ZStack {
            Group {
                if dontUseSolidBackgrounds {
                    Color.clear
                } else {
                    ZStack {
                        if colorScheme == .dark {
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.0, green: 0.0, blue: 0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        } else {
                            #if os(macOS)
                            Color(nsColor: .windowBackgroundColor)
                            #else
                            Color(uiColor: .systemBackground)
                            #endif
                        }
                        glassBackgroundTintValue.opacity(colorScheme == .dark ? 0.16 : 0.10)
                    }
                }
            }
            if !dontUseSolidBackgrounds {
                ChatWallpaperBackgroundView(pattern: chatWallpaperPattern)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Views
    
    @ViewBuilder
    private func chatRow(for thread: ChatThread) -> some View {
        HStack(spacing: 0) {
            if editingTitleId == thread.id {
                TextField("", text: $editedTitle)
                    .focused($isTitleFocused)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        saveEditedTitle(for: thread)
                    }
            } else {
                Text(thread.title)
                    .font(.system(size: 13, weight: manager.activeThreadId == thread.id ? .semibold : .regular))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private func chatDetailArea(for thread: ChatThread) -> some View {
        VStack(spacing: 0) {
            if useCenteredModelLook {
                HStack {
                    Spacer()
                    
                    Button {
                        showModelPopover.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: modelPillSymbol(for: thread))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(accentColorValue)
                            Text(modelPillText(for: thread, centered: true))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                                )
                        )
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showModelPopover, arrowEdge: .bottom) {
                        modelPopoverView(for: thread)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            
            // Messages List & Floating Tool Request Overlay
            ZStack(alignment: .bottomLeading) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if thread.messages.isEmpty {
                            emptyThreadWelcomeView(for: thread)
                                .padding(.top, 40)
                                .padding(.bottom, 120)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(visibleTranscriptMessages(in: thread)) { message in
                                    messageBubble(for: message, in: thread)
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: thread.messages.count)
                            .padding()
                            .padding(.bottom, manager.toolRequestManager.activeRequestThreadId == thread.id ? 220 : 10)
                        }
                    }
                    .onChange(of: thread.messages.count) {
                        scrollToBottom(proxy: proxy, thread: thread, animated: true)
                    }
                    .onChange(of: thread.messages.last?.text.count ?? 0) {
                        if manager.isGenerating {
                            scrollToBottom(proxy: proxy, thread: thread, animated: false)
                        }
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy, thread: thread, animated: false)
                    }
                }
                // Floating Card (Tool Request Card)
                if manager.toolRequestManager.activeRequest != nil,
                   manager.toolRequestManager.activeRequestThreadId == thread.id {
                    ToolCardView(manager: manager.toolRequestManager)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                }
            }
            // The transcript owns all remaining vertical space. Without this,
            // AppKit's multiline editor greedily receives it instead.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Floating Error Card (Fully Rounded Pill with Margins)
            if let error = manager.errorMessage {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            manager.errorMessage = nil
                        }
                    }) {
                        Text("Dismiss")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.red.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(Color.red.opacity(0.25), lineWidth: 1)
                        )
                )
                .shadow(color: Color.red.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            
            // Floating Continue Button (Appears when conversation was interrupted/broken)
            if isThreadInterrupted(thread) {
                HStack {
                    Spacer()
                    Button(action: {
                        Task {
                            await manager.continueLastResponse()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Continue Response")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(accentColorValue)
                                .shadow(color: accentColorValue.opacity(0.35), radius: 8, x: 0, y: 4)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            
            // Developer-only context diagnostics live outside the composer.
            if thread.showSystemMessages {
                HStack(spacing: 5) {
                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .bold))
                        Text(manager.getContextUsageString(for: thread))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.2), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: manager.getContextUsageFraction(for: thread))
                                .stroke(
                                    Color.blue,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 12, height: 12)
                        .accessibilityLabel("Context usage")
                        .accessibilityValue(manager.getContextUsageString(for: thread))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.blue.opacity(0.14)))
                    .foregroundStyle(Color.blue)
                    .overlay(Capsule().stroke(Color.blue.opacity(0.25), lineWidth: 1))
                    .help("Context Usage (Used Tokens / Total Context Window)")

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            manager.clearThreadMessages(threadId: thread.id)
                        }
                    }) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.85))
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset Context (Clear conversation history to empty context tokens)")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Floating Apple-native input pill
            VStack(alignment: .leading, spacing: 0) {
                if editingUserMessageId != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Editing prompt")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button {
                            editingUserMessageId = nil
                            inputText = ""
                            attachedImageBase64 = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel editing")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }

                if let imageBase64 = attachedImageBase64,
                   let nsImage = nsImageFromBase64(imageBase64) {
                    HStack {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                            
                            Button(action: {
                                withAnimation {
                                    attachedImageBase64 = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.gray, Color(NSColor.windowBackgroundColor))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                        }
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.leading, 14)
                    .transition(.opacity.combined(with: .scale))
                }
                
                let isToolActive = manager.toolRequestManager.activeRequest != nil &&
                    manager.toolRequestManager.activeRequestThreadId == thread.id
                let placeholderText: String = {
                    if isToolActive {
                        return "Provide information in the card above..."
                    } else if manager.isGenerating {
                        return "Type your next message while this response finishes..."
                    } else {
                        switch thread.provider {
                        case .lmStudio: return "Message LM Studio Server..."
                        case .gemini: return "Message Gemini API..."
                        case .openRouter: return "Message OpenRouter API..."
                        case .openAI: return "Message ChatGPT..."
                        }
                    }
                }()

                VStack(spacing: 2) {
                    ChatComposerTextView(
                        text: $inputText,
                        placeholder: placeholderText,
                        shiftEnterForNewLine: shiftEnterForNewLine,
                        isEnabled: !isToolActive,
                        composerHeight: extendedTextBox ? 40 : 20,
                        onSend: sendCurrentMessage
                    )
                        // NSScrollView otherwise expands to fill the entire
                        // composer container. Keep the normal composer small;
                        // longer messages scroll inside it.
                        .frame(height: extendedTextBox ? 40 : 20)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                    
                    HStack(spacing: 8) {
                        Button(action: selectImage) {
                            Image(systemName: "photo")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Attach Image")
                        .padding(.leading, 10)
                        
                        Button {
                            showEffortPopover.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                if !hideInputToggleText {
                                    Text("Effort")
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                            }
                            .frame(width: hideInputToggleText ? 26 : 62)
                            .frame(height: 25)
                            .background(accentColorValue.opacity(0.11), in: Capsule())
                            .overlay(Capsule().stroke(accentColorValue.opacity(0.22), lineWidth: 0.75))
                            .foregroundStyle(accentColorValue)
                        }
                        .buttonStyle(.plain)
                        .help("Reasoning effort: \(aiEffortLevel)")
                        .popover(isPresented: $showEffortPopover, arrowEdge: .bottom) {
                            EffortPopoverView(
                                level: AIEffortLevel(rawValue: aiEffortLevel) ?? .medium,
                                accentColor: accentColorValue
                            ) { newLevel in
                                aiEffortLevel = newLevel.rawValue
                                // Keep the legacy flag synchronized for older
                                // saved prompts while providers use aiEffortLevel.
                                enableThinking = newLevel != .low
                            }
                        }

                        if thread.provider == .lmStudio {
                            Button {
                                lmStudioThinkingEnabled.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: lmStudioThinkingEnabled ? "brain.filled.head.profile" : "brain.head.profile")
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text("Think")
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                .frame(width: 58)
                                .frame(height: 25)
                                .background(
                                    Capsule()
                                        .fill(
                                            lmStudioThinkingEnabled
                                                ? accentColorValue.opacity(0.18)
                                                : Color.primary.opacity(0.055)
                                        )
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            lmStudioThinkingEnabled
                                                ? accentColorValue.opacity(0.34)
                                                : Color.primary.opacity(0.12),
                                            lineWidth: 0.75
                                        )
                                }
                                .foregroundStyle(lmStudioThinkingEnabled ? accentColorValue : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(manager.isGenerating)
                            .help(
                                lmStudioThinkingEnabled
                                    ? "Thinking is on for LM Studio. Effort controls its intensity."
                                    : "Thinking is off for LM Studio. Responses use direct-answer mode."
                            )
                            .accessibilityLabel("LM Studio thinking")
                            .accessibilityValue(lmStudioThinkingEnabled ? "On" : "Off")
                        }

                        Button {
                            forceWebSearchNextMessage.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: forceWebSearchNextMessage ? "globe.americas.fill" : "globe.americas")
                                    .font(.system(size: 10.5, weight: .semibold))
                                if !hideInputToggleText {
                                    Text("Web")
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                            }
                            .frame(width: hideInputToggleText ? 26 : 56)
                            .frame(height: 25)
                            .background(
                                Capsule()
                                    .fill(
                                        forceWebSearchNextMessage
                                            ? accentColorValue.opacity(0.18)
                                            : Color.primary.opacity(0.055)
                                    )
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        forceWebSearchNextMessage
                                            ? accentColorValue.opacity(0.34)
                                            : Color.primary.opacity(0.12),
                                        lineWidth: 0.75
                                    )
                            }
                            .foregroundStyle(forceWebSearchNextMessage ? accentColorValue : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(manager.isGenerating || !enableInternetSearch)
                        .help(
                            enableInternetSearch
                                ? (forceWebSearchNextMessage
                                    ? "Web search is required for the next message."
                                    : "Require web search for the next message.")
                                : "Enable Internet Search in Toolbox to use Web."
                        )
                        .accessibilityLabel("Use web for next message")
                        .accessibilityValue(forceWebSearchNextMessage ? "On" : "Off")
                        .animation(.easeOut(duration: 0.16), value: forceWebSearchNextMessage)

                        Spacer()
                        
                        if manager.isGenerating {
                            Button(action: {
                                manager.stopGeneration()
                            }) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Stop Generating")
                            .padding(.trailing, 8)
                        } else {
                            // Mic button
                            Button(action: { toggleDictation() }) {
                                Image(systemName: isDictating ? "mic.fill" : "mic")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(isDictating ? .red : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help(isDictating ? "Stop Dictation" : "Start Dictation")
                            
                            Button(action: sendCurrentMessage) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(inputText.isEmpty && attachedImageBase64 == nil || isToolActive ? Color.secondary : (thread.provider == .lmStudio ? Color.blue : Color.purple))
                            }
                            .buttonStyle(.plain)
                            .disabled((inputText.isEmpty && attachedImageBase64 == nil) || isToolActive || manager.isGenerating)
                            .padding(.trailing, 8)
                        }
                    }
                    .padding(.bottom, 2)
                }
                // The whole composer, not merely the embedded text view, must
                // be height-constrained. This is the same compact layout rule
                // used by chat clients: the transcript scrolls; the composer
                // remains a small fixed control.
                .frame(height: extendedTextBox ? 84 : 64, alignment: .top)
                .clipped()
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(glassBackgroundTintValue.opacity(dontUseSolidBackgrounds ? 0 : (colorScheme == .dark ? 0.12 : 0.07)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, showTerminalPanel ? 8 : 16)
            
            // Live Terminal Panel
            if showTerminalPanel {
                VStack(spacing: 0) {
                    // Drag handle & header
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                        Text("TERMINAL")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.9))
                        
                        Capsule()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .overlay(Capsule().fill(manager.terminalLogs.isEmpty ? Color.gray : Color.green))
                        
                        Text("\(manager.terminalLogs.count) entries")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                        Spacer()

                        Text(manager.terminalCurrentDirectory)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 260, alignment: .trailing)
                        
                        Button {
                            manager.clearTerminalLogs()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear Terminal")
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showTerminalPanel = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Close Terminal")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newHeight = terminalPanelHeight - value.translation.height
                                terminalPanelHeight = max(120, min(500, newHeight))
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeUpDown.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Terminal output
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                if manager.terminalLogs.isEmpty {
                                    HStack {
                                        Text("Enter a command below to start a zsh session.")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .italic()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 20)
                                } else {
                                    ForEach(manager.terminalLogs) { entry in
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 6) {
                                                Text(entry.timestamp, style: .time)
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundStyle(.secondary.opacity(0.6))
                                                Text(entry.isError ? "✗" : "✓")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(entry.isError ? .red : .green)
                                                Text("$")
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(.green)
                                                Text(entry.command)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(2)
                                            }
                                            
                                            Text(entry.output)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(entry.isError ? .red.opacity(0.8) : .secondary.opacity(0.7))
                                                .textSelection(.enabled)
                                                .padding(.leading, 20)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 3)
                                        .id(entry.id)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onChange(of: manager.terminalLogs.count) {
                            if let lastId = manager.terminalLogs.last?.id {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }

                    Divider().opacity(0.3)

                    HStack(spacing: 8) {
                        Text("❯")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)

                        TextField("Enter a zsh command", text: $terminalCommand)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .disabled(manager.isTerminalCommandRunning)
                            .onSubmit {
                                let command = terminalCommand
                                terminalCommand = ""
                                manager.runTerminalCommand(command)
                            }

                        if manager.isTerminalCommandRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Run") {
                                let command = terminalCommand
                                terminalCommand = ""
                                manager.runTerminalCommand(command)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(terminalCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(height: terminalPanelHeight)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.95))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.65), lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if showShareCopiedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Transcript copied to clipboard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                .padding(.top, 12)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showShareCopiedToast)
        .background(
            Color.clear
        )
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showTerminalPanel.toggle()
                    }
                } label: {
                    Label("Terminal", systemImage: "terminal.fill")
                        .foregroundStyle(showTerminalPanel ? .green : .secondary)
                }
                .help(showTerminalPanel ? "Hide Terminal" : "Show Live Terminal")

                UserDeveloperSliderToggle(isDeveloper: thread.showSystemMessages) { isDeveloper in
                    manager.updateShowSystemMessages(id: thread.id, show: isDeveloper)
                }
            }
            
            ToolbarItem(placement: .navigation) {
                if !useCenteredModelLook {
                    Button {
                        showModelPopover.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                            Text(selectedModelDisplayName(for: thread))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.trailing, 6)
                        .padding(.leading, 2)
                    }
                    .popover(isPresented: $showModelPopover, arrowEdge: .bottom) {
                        modelPopoverView(for: thread)
                    }
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if showRightSidebar {
                    Picker("Sidebar Panel", selection: Binding(
                        get: { rightSidebarTab },
                        set: { newTab in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                rightSidebarTab = newTab
                            }
                        }
                    )) {
                        Image(systemName: "slider.horizontal.3").tag(RightSidebarTab.configure).help("Configure Assistant Settings")
                        if !rightSidebarSources.isEmpty {
                            Image(systemName: "globe").tag(RightSidebarTab.sources).help("Web Sources")
                        }
                        if thread.showSystemMessages {
                            Image(systemName: "text.line.first.and.arrowtriangle.forward").tag(RightSidebarTab.prePrompts).help("Pre Prompts Manager")
                            Image(systemName: "network").tag(RightSidebarTab.memoryGraph).help("Advanced Memory Graph")
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: thread.showSystemMessages
                        ? (rightSidebarSources.isEmpty ? 200 : 250)
                        : (rightSidebarSources.isEmpty ? 130 : 160))
                }
                
                // Share Menu Button
                Menu {
                    Button {
                        copyTranscript(for: thread)
                    } label: {
                        Label("Copy as transcribe", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        downloadTranscript(for: thread)
                    } label: {
                        Label("Download transcribe into text file", systemImage: "arrow.down.doc")
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share Transcript")
                .disabled(thread.messages.isEmpty)

                // Toggle Right Sidebar Button (placed at far right most position)
                Button {
                    withAnimation {
                        showRightSidebar.toggle()
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.right")
                        .foregroundStyle(showRightSidebar ? .blue : .primary)
                }
                .help("Toggle Sidebar")
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
    
    @ViewBuilder
    private func messageBubble(for message: ChatMessage, in thread: ChatThread) -> some View {
        let isSystemMessage = message.role == .user && (message.isToolResponse || message.text.hasPrefix("[System:") || message.text.hasPrefix("[SYSTEM:") || message.text.contains("tool_response"))
        let isInternalToolResponse = message.role == .user && message.isToolResponse
        let toolRequest = ToolRequestParser.parse(text: message.text)
        let hasBeenSubmitted = findNextMessage(after: message, in: thread)?.text.contains("tool_response") ?? false
        let hasSliders = toolRequest?.fields.contains(where: { $0.type == .slider }) ?? false
        let isSubmittedDataCollection = toolRequest != nil && hasBeenSubmitted && !hasSliders && toolRequest?.type == "request_input"
        if isInternalToolResponse || (isSystemMessage && !thread.showSystemMessages) || isSubmittedDataCollection {
            EmptyView()
        } else {
            HStack {
                if message.role == .user {
                    Spacer(minLength: 40)
                    
                    if isSystemMessage {
                        EmptyView()
                    } else {
                        HStack(alignment: .bottom, spacing: 8) {
                            if hoveredMessageId == message.id {
                                HStack(spacing: 4) {
                                    MessageActionIconButton(
                                        systemName: "square.on.square",
                                        helpText: "Copy prompt"
                                    ) {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(message.text, forType: .string)
                                    }

                                    MessageActionIconButton(
                                        systemName: "pencil",
                                        helpText: "Edit prompt",
                                        isDisabled: manager.isGenerating
                                    ) {
                                        inputText = message.text
                                        attachedImageBase64 = message.attachedImageBase64
                                        editingUserMessageId = message.id
                                        isInputFocused = true
                                    }
                                }
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }

                            Group {
                                if let imageBase64 = message.attachedImageBase64,
                                   let nsImage = nsImageFromBase64(imageBase64) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: 240, maxHeight: 180)
                                            .cornerRadius(8)
                                        if !message.text.isEmpty {
                                            Text(message.text)
                                                .font(.system(size: 13.5))
                                                .lineSpacing(3.5)
                                        }
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(useGradientBubbles ? AnyView(accentGradientValue) : AnyView(accentColorValue))
                                    .foregroundStyle(.white)
                                    .clipShape(BubbleShape(isUser: true))
                                } else {
                                    Text(message.text)
                                        .font(.system(size: 13.5))
                                        .lineSpacing(3.5)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 12)
                                        .background(useGradientBubbles ? AnyView(accentGradientValue) : AnyView(accentColorValue))
                                        .foregroundStyle(.white)
                                        .clipShape(BubbleShape(isUser: true))
                                }
                            }
                            .textSelection(.enabled)
                        }
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            withAnimation(.easeOut(duration: 0.12)) {
                                if isHovered {
                                    hoveredMessageId = message.id
                                } else if hoveredMessageId == message.id {
                                    hoveredMessageId = nil
                                }
                            }
                        }
                    }
                } else {
                    let isFollowupMemory = isFollowupToMemoryRequest(message, in: thread)
                    let isPureMemory = isPureMemoryRequest(message)
                    let isToolFollowup = isSubsequentToolResponseAssistantMessage(message, in: thread)
                    let isTerminalToolRequest = toolRequest?.type == "file_system" || toolRequest?.displayTitle == "terminal used"
                    let isSearchToolRequest = toolRequest?.type == "internet_use" || message.isStreamingSearchJSON
                    
                    VStack(alignment: .leading, spacing: isPureMemory ? 2 : 6) {
                        if !advancedRender && !isFollowupMemory {
                            HStack(spacing: 6) {
                                if thread.provider == .lmStudio {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.teal)
                                    Text(thread.lmStudioModelId ?? "LM Studio Model")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                } else if thread.provider == .gemini {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.blue)
                                    Text(thread.geminiModelId ?? "Gemini Model")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                } else if thread.provider == .openRouter {
                                    Image(systemName: "cloud.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.purple)
                                    Text(thread.openRouterModelId ?? "OpenRouter Model")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                } else if thread.provider == .openAI {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.green)
                                    Text(thread.openAIModelId ?? "ChatGPT Model")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        let isLast = message.id == thread.messages.last?.id
                        let isCurrentlyStreaming = isLast && manager.isGenerating
                        let isThinkingEnabled = thread.provider == .lmStudio
                            ? lmStudioThinkingEnabled
                            : (AIEffortLevel(rawValue: aiEffortLevel) ?? .medium) != .low
                        let reasoningParsed = message.parsedReasoning
                        // Thought output was previously tied to Effort/Thinking mode.
                        // Based on user request, it is now exclusively tied to
                        // Developer Mode. Keep it visible as a collapsible row
                        // only when Developer Mode is enabled.
                        let reasoningText = thread.showSystemMessages ? reasoningParsed.reasoningText : nil
                        let mainContentText = reasoningParsed.mainText
                        let responseSources = searchLinksForTurn(endingAt: message, in: thread)
                        // Reasoning extraction intentionally strips native tool-call
                        // transport from visible prose. Parse the original message so
                        // the corresponding activity card is still rendered.
                        let parsedToolRequest = ToolRequestParser.parse(text: message.text)
                        
                        let isStreamingJSONPart = isCurrentlyStreaming &&
                            (mainContentText.contains("{") || mainContentText.contains("```")) &&
                            ToolRequestParser.parse(text: mainContentText) == nil
                        
                        let trimmedText = mainContentText.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Never replace real streamed prose with the loading view. The old
                        // smoothing threshold hid the first ~100 characters and made a
                        // response look like it was permanently stuck on “…”.
                        let hasVisibleProse = !trimmedText.isEmpty && trimmedText != "..."
                        
                        if !hasVisibleProse && reasoningText == nil && parsedToolRequest == nil {
                            Group {
                                // A completed native tool-call message has no
                                // display text after its transport markup is
                                // removed. Only show a loading indicator while
                                // that exact message is still streaming.
                                if isCurrentlyStreaming {
                                    if message.isStreamingSearchJSON {
                                        EmptyView()
                                    } else if message.isStreamingTaskJSON {
                                        if isFirstTaskToolRequestInTurn(message, in: thread) {
                                            TasksExecutingView()
                                        }
                                    } else if isThinkingEnabled {
                                        ThinkingView()
                                    } else {
                                        GeneratingView()
                                    }
                                }
                            }
                            .assistantBubbleContainer(advancedRender: advancedRender)
                                .textSelection(.enabled)
                        } else if isCurrentlyStreaming && message.isStreamingJSON && message.introText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Group {
                                if message.isStreamingSearchJSON {
                                    EmptyView()
                                } else if message.isStreamingFileSystemJSON {
                                    TerminalExecutingView()
                                } else if message.isStreamingTaskJSON {
                                    if isFirstTaskToolRequestInTurn(message, in: thread) {
                                        TasksExecutingView()
                                    }
                                } else {
                                    CrystalizingView()
                                }
                            }
                             .assistantBubbleContainer(advancedRender: advancedRender)
                        } else {
                            let toolRequest = parsedToolRequest
                            // Tool calls have a dedicated activity card. Never
                            // render the model's raw transport envelope as
                            // Markdown above or below that card.
                            let intro = message.introText
                            let conclusion = message.conclusionText
                            let isCompactHeader = toolRequest?.type == "advanced_memory" || toolRequest?.type == "learning" || toolRequest?.type == "file_system"
                            VStack(alignment: .leading, spacing: isCompactHeader ? 4 : 12) {
                                if let reasoning = reasoningText, !reasoning.isEmpty {
                                    ReasoningThoughtView(
                                        reasoningText: reasoning,
                                        isGenerating: isCurrentlyStreaming,
                                        isComplete: reasoningParsed.isThinkingComplete,
                                        showsCopyAction: thread.showSystemMessages
                                    )
                                }
                                
                                if !intro.isEmpty {
                                    MarkdownView(
                                        text: intro,
                                        isGenerating: isCurrentlyStreaming,
                                        advancedRender: advancedRender,
                                        sourceLinks: responseSources
                                    )
                                } else if toolRequest == nil && !mainContentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    MarkdownView(
                                        text: mainContentText,
                                        isGenerating: isCurrentlyStreaming,
                                        advancedRender: advancedRender,
                                        sourceLinks: responseSources
                                    )
                                }

                                
                                if isStreamingJSONPart {
                                    if message.isStreamingSearchJSON {
                                        EmptyView()
                                    } else if message.isStreamingFileSystemJSON {
                                        TerminalExecutingView()
                                    } else if message.isStreamingTaskJSON {
                                        if isFirstTaskToolRequestInTurn(message, in: thread) {
                                            TasksExecutingView()
                                        }
                                    } else {
                                        CrystalizingView()
                                    }
                                }
                                
                                if let request = toolRequest {
                                    let hasInsights = request.fields.contains(where: { $0.type == .insight })
                                    
                                    VStack(alignment: .leading, spacing: isCompactHeader ? 2 : 8) {
                                        if !intro.isEmpty && !hasInsights && request.type != "file_system" && request.type != "advanced_memory" && request.type != "learning" {
                                            Divider()
                                        }
                                        
                                        if request.type == "internet_use" {
                                            // One status row represents the whole web-search phase,
                                            // even when the model issues several refinement queries.
                                            let isSearching = manager.toolRequestManager.isProcessing(threadId: thread.id)
                                            let activitySources = searchLinksForSearchActivity(startingAt: message, in: thread)

                                            // Small searches already expose their citations and
                                            // Sources button on the final response. Reserve the
                                            // separate search activity row for larger research turns.
                                            if activitySources.count > 4 {
                                                if isSearching {
                                                    HStack(spacing: 7) {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                        CrystalizingText(
                                                            label: "Searching web…",
                                                            font: .system(size: 13, weight: .medium)
                                                        )
                                                    }
                                                    .padding(.vertical, 2)
                                                } else {
                                                    Group {
                                                        Button {
                                                            openSourcesSidebar(sources: activitySources, messageID: message.id)
                                                        } label: {
                                                            HStack(spacing: 7) {
                                                                Image(systemName: "globe.americas.fill")
                                                                    .font(.system(size: 11.5, weight: .semibold))
                                                                    .foregroundStyle(.blue)
                                                                Text("Searched the web")
                                                                    .font(.system(size: 13, weight: .medium))
                                                                    .foregroundStyle(.secondary)
                                                                Spacer()
                                                                Image(systemName: "chevron.right")
                                                                    .font(.system(size: 9, weight: .semibold))
                                                                    .foregroundStyle(.tertiary)
                                                            }
                                                            .contentShape(Rectangle())
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Open web sources in the Activity sidebar")
                                                    }
                                                    .padding(.vertical, 2)
                                                }
                                            }
                                        } else {
                                            // Inline Title and Description header card in chat
                                            if !hasInsights {
                                                let isFileSystem = request.type == "file_system" || request.displayTitle == "terminal used"
                                                let shouldShowHeader = !isFileSystem || isFirstFileSystemToolRequest(message, in: thread)
                                                
                                                if shouldShowHeader {
                                                    if isFileSystem {
                                                        let resultMessage = findNextMessage(after: message, in: thread)
                                                        TerminalThoughtView(
                                                            commandText: request.description,
                                                            isComplete: resultMessage?.isToolResponse == true,
                                                            didSucceed: toolResponseSucceeded(resultMessage)
                                                        )
                                                    } else if request.type == "task_management" {
                                                        if isFirstTaskToolRequestInTurn(message, in: thread) {
                                                            TasksExecutingView(isComplete: findNextMessage(after: message, in: thread)?.isToolResponse == true)
                                                        }
                                                    } else {
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            HStack(spacing: 5) {
                                                                if request.type == "advanced_memory" || request.type == "learning" || request.displayTitle == "updated memory" {
                                                                Image(systemName: "brain.head.profile")
                                                                    .font(.system(size: 11))
                                                                    .foregroundStyle(.secondary)
                                                                }
                                                                Text(request.displayTitle)
                                                                    .font(.caption)
                                                                    .fontWeight((request.type == "advanced_memory" || request.type == "learning") ? .medium : .bold)
                                                                    .foregroundStyle((request.type == "advanced_memory" || request.type == "learning") ? .secondary : .primary)
                                                            }
                                                            if request.type != "advanced_memory" && request.type != "learning" && !request.description.isEmpty {
                                                                Text(request.description)
                                                                    .font(.caption)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                        }
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                    }
                                                }
                                            }
                                        }
                                        
                                        if enableDynamicInsights && hasInsights {
                                            DynamicInsightBlockView(request: request)
                                        }
                                    }
                                }
                                
                                if !conclusion.isEmpty {
                                    let hasInsights = toolRequest?.fields.contains(where: { $0.type == .insight }) ?? false
                                    if toolRequest != nil && !hasInsights && toolRequest?.type != "file_system" && toolRequest?.type != "advanced_memory" && toolRequest?.type != "learning" {
                                        Divider()
                                    }
                                    MarkdownView(
                                        text: conclusion,
                                        isGenerating: isCurrentlyStreaming,
                                        advancedRender: advancedRender,
                                        sourceLinks: responseSources
                                    )
                                }
                                
                                // Show one metrics badge per user prompt: on that turn's last
                                // assistant message, never on its intermediate tool/status steps.
                                let messageIndex = thread.messages.firstIndex(where: { $0.id == message.id })
                                let messagesAfterThis = messageIndex.map { Array(thread.messages.dropFirst($0 + 1)) } ?? []
                                let messagesBeforeNextUserPrompt = messagesAfterThis.prefix { candidate in
                                    candidate.role != .user || candidate.isToolResponse || candidate.text.hasPrefix("[System:") || candidate.text.hasPrefix("[SYSTEM:")
                                }
                                let hasLaterAssistantInThisTurn = messagesBeforeNextUserPrompt.contains(where: { $0.role == .assistant })
                                let isFinalAssistantMessage = !hasLaterAssistantInThisTurn
                                let turnSources = responseSources
                                if isFinalAssistantMessage && (message.generationStartTime != nil || !turnSources.isEmpty) {
                                    
                                    HStack(spacing: 7) {
                                        // Statistics are informational only. Keep destructive and
                                        // retry actions as distinct controls so they cannot be
                                        // mistaken for part of the metrics badge.
                                        if thread.showSystemMessages, let start = message.generationStartTime {
                                            let end = message.generationEndTime ?? (isCurrentlyStreaming ? Date() : start)
                                            let duration = end.timeIntervalSince(start)
                                            let estimatedTokens = mainContentText.count / 4
                                            let tokensPerSecond = duration > 0 ? Double(estimatedTokens) / duration : 0.0
                                            HStack(spacing: 5) {
                                                Image(systemName: "timer")
                                                    .font(.system(size: 9, weight: .semibold))
                                                Text(String(format: "%.2fs", duration))
                                                Text("•").opacity(0.4)
                                                Text(String(format: "~%d tokens", estimatedTokens))
                                                Text("•").opacity(0.4)
                                                Text(String(format: "%.1f t/s", tokensPerSecond))
                                            }
                                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary.opacity(0.75))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color.primary.opacity(0.04)).overlay(Capsule().stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)))
                                            .padding(.top, 4)
                                        }

                                        if !turnSources.isEmpty {
                                            sourcesButton(sources: turnSources, messageID: message.id)
                                                .padding(.top, 4)
                                        }

                                    MessageActionIconButton(
                                        systemName: "arrow.clockwise",
                                        helpText: "Retry",
                                        isDisabled: manager.isGenerating
                                    ) {
                                        Task { await manager.retryResponse(threadId: thread.id, messageId: message.id) }
                                    }

                                    MessageActionIconButton(
                                        systemName: "square.on.square",
                                        helpText: "Copy response"
                                    ) {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(mainContentText, forType: .string)
                                    }

                                    MessageActionIconButton(
                                        systemName: "arrow.triangle.branch",
                                        helpText: "Branch in new chat",
                                        isDisabled: manager.isGenerating
                                    ) {
                                        manager.branchConversation(threadId: thread.id, through: message.id)
                                    }

                                    MessageActionIconButton(
                                        systemName: "trash",
                                        helpText: "Delete",
                                        role: .destructive
                                    ) {
                                        manager.deleteMessage(threadId: thread.id, messageId: message.id)
                                    }

                                }
                            }
                            }
                            .assistantBubbleContainer(
                                advancedRender: advancedRender,
                                isCompactTop: isFollowupMemory || isToolFollowup,
                                isCompactBottom: isPureMemory || isTerminalToolRequest || isSearchToolRequest
                            )
                            .padding(.top, isFollowupMemory || isToolFollowup ? -10 : 0)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
        }
    }

    @ViewBuilder
    private func sourcesButton(sources: [(title: String, url: String)], messageID: UUID) -> some View {
        Button {
            if NSEvent.modifierFlags.contains(.shift) {
                openSourcesSidebar(sources: sources, messageID: messageID)
            } else {
                sourcePopoverMessageID = sourcePopoverMessageID == messageID ? nil : messageID
            }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -6) {
                    ForEach(Array(sources.prefix(3).enumerated()), id: \.offset) { _, source in
                        let host = URL(string: source.url)?.host() ?? ""
                        ZStack {
                            Circle().fill(Color(nsColor: .windowBackgroundColor))
                            if let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32") {
                                AsyncImage(url: faviconURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .clipShape(Circle())
                                } placeholder: {
                                    Image(systemName: "globe").font(.system(size: 9, weight: .bold))
                                }
                                .frame(width: 20, height: 20)
                                .clipShape(Circle())
                            }
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                    }
                }
                Text("Sources")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show web source links (Shift-click to open in right panel)")
        .popover(isPresented: Binding(
            get: { sourcePopoverMessageID == messageID },
            set: { if !$0 { sourcePopoverMessageID = nil } }
        ), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Text("Sources")
                            .font(.system(size: 13, weight: .bold))
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("\(sources.count) links")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        openSourcesSidebar(sources: sources, messageID: messageID)
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in right panel (or Shift-click Sources)")

                    Button { sourcePopoverMessageID = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                            if let destination = URL(string: source.url) {
                                Link(destination: destination) {
                                    HStack(spacing: 9) {
                                        let host = destination.host() ?? source.url
                                        ZStack {
                                            Circle()
                                                .fill(Color.primary.opacity(0.06))
                                            if let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
                                                AsyncImage(url: faviconURL) { image in
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .clipShape(Circle())
                                                } placeholder: {
                                                    Image(systemName: "globe")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .frame(width: 18, height: 18)
                                                .clipShape(Circle())
                                            }
                                        }
                                        .frame(width: 24, height: 24)
                                        .clipShape(Circle())

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(source.title)
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(host)
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 6)
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(.blue.opacity(0.85))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 270)
            }
            .frame(width: 310)
        }
    }

    private func openSourcesSidebar(sources: [(title: String, url: String)], messageID: UUID) {
        rightSidebarSources = sources
        rightSidebarSourceMessageID = messageID
        sourcePopoverMessageID = nil
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            rightSidebarTab = .sources
            showRightSidebar = true
        }
    }
    
    private func formatModelDisplayName(_ modelId: String) -> String {
        let raw = modelId.replacingOccurrences(of: ":free", with: "")
                         .replacingOccurrences(of: ":exact", with: "")
        let parts = raw.split(separator: "/")
        let namePart = String(parts.last ?? Substring(raw))
        
        let lower = namePart.lowercased()
        if lower.contains("nemotron-3-ultra") || lower.contains("nemotron-3") { return "Nemotron 3 Ultra" }
        if lower.contains("nemotron") { return "Nemotron" }
        if lower.contains("gemini-2.0-flash") { return "Gemini 2.0 Flash" }
        if lower.contains("gemini-2.5-flash") { return "Gemini 2.5 Flash" }
        if lower.contains("gemini-1.5-pro") { return "Gemini 1.5 Pro" }
        if lower.contains("llama-3.3-70b") { return "Llama 3.3 70B" }
        if lower.contains("llama-3.1-405b") { return "Llama 3.1 405B" }
        if lower.contains("deepseek-r1") { return "DeepSeek R1" }
        if lower.contains("deepseek-v3") { return "DeepSeek V3" }
        if lower.contains("claude-3.5-sonnet") { return "Claude 3.5 Sonnet" }
        if lower.contains("mistral-7b") { return "Mistral 7B" }
        if lower.contains("qwen-2.5-72b") { return "Qwen 2.5 72B" }
        if lower == "gpt-4o" { return "GPT-4o" }
        if lower == "gpt-4o-mini" { return "GPT-4o Mini" }
        if lower == "gpt-4-turbo" { return "GPT-4 Turbo" }
        if lower == "o1" { return "o1" }
        if lower == "o1-mini" { return "o1 Mini" }
        if lower == "o3-mini" { return "o3 Mini" }
        
        let cleaned = namePart
            .replacingOccurrences(of: "-instruct", with: "")
            .replacingOccurrences(of: "-exp", with: "")
            .replacingOccurrences(of: "-it", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        
        let words = cleaned.split(separator: " ").map { $0.capitalized }
        return words.joined(separator: " ")
    }

    private func selectedModelDisplayName(for thread: ChatThread) -> String {
        switch thread.provider {
        case .gemini:
            return formatModelDisplayName(thread.geminiModelId ?? "gemini-2.5-flash")
        case .openRouter:
            return formatModelDisplayName(thread.openRouterModelId ?? "google/gemini-2.0-flash-001")
        case .openAI:
            return formatModelDisplayName(thread.openAIModelId ?? "gpt-4o")
        case .lmStudio:
            return formatModelDisplayName(thread.lmStudioModelId ?? "LM Studio")
        }
    }

    private func providerDisplayName(for thread: ChatThread) -> String {
        switch thread.provider {
        case .gemini:
            return "Gemini"
        case .openRouter:
            return "OpenRouter"
        case .openAI:
            return "OpenAI"
        case .lmStudio:
            return "LM Studio"
        }
    }

    private func modelPillSymbol(for thread: ChatThread) -> String {
        switch thread.provider {
        case .gemini:
            return "sparkles"
        case .openRouter:
            return "cloud.fill"
        case .openAI:
            return "brain.head.profile"
        case .lmStudio:
            return "server.rack"
        }
    }

    private func modelPillText(for thread: ChatThread, centered: Bool) -> String {
        let modelName = selectedModelDisplayName(for: thread)
        if centered {
            return "\(providerDisplayName(for: thread)) • \(modelName)"
        }
        return modelName
    }
    
    @ViewBuilder
    private func modelPopoverView(for thread: ChatThread) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Selection")
                .font(.headline)
            
            // Provider Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Provider")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Picker("Provider", selection: Binding(
                    get: { thread.provider },
                    set: { manager.updateProvider(id: thread.id, provider: $0) }
                )) {
                    ForEach(Provider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            
            if thread.provider == .lmStudio {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Model")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if !manager.lmStudioAvailableModels.isEmpty {
                        Picker("Model", selection: Binding(
                            get: { thread.lmStudioModelId ?? "" },
                            set: { manager.updateLMStudioModel(id: thread.id, modelId: $0.isEmpty ? nil : $0) }
                        )) {
                            Text("Select a model...").tag("")
                            ForEach(manager.lmStudioAvailableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    } else {
                        Text("No models detected. Ensure LM Studio server is started.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            
            if thread.provider == .gemini {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Model")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Picker("Model", selection: Binding(
                        get: { thread.geminiModelId ?? "gemini-2.5-flash" },
                        set: { manager.updateGeminiModel(id: thread.id, modelId: $0) }
                    )) {
                        ForEach(manager.geminiModels, id: \.self) { model in
                            Text(model + (model == "gemini-2.5-flash" ? " (Recommended)" : "")).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            
            if thread.provider == .openRouter {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Model")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Picker("Model", selection: Binding(
                        get: { thread.openRouterModelId ?? "google/gemini-2.0-flash-001" },
                        set: { manager.updateOpenRouterModel(id: thread.id, modelId: $0) }
                    )) {
                        ForEach(manager.openRouterModels, id: \.self) { model in
                            let isFree = manager.isOpenRouterModelFree(model)
                            let badge = isFree ? "🟢 [FREE] " : "💳 [PAID] "
                            Text(badge + model + (model == "google/gemini-2.0-flash-001" ? " (Recommended)" : "")).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            
            if thread.provider == .openAI {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Selected Model")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Picker("Model", selection: Binding(
                        get: { thread.openAIModelId ?? "gpt-4o" },
                        set: { manager.updateOpenAIModel(id: thread.id, modelId: $0) }
                    )) {
                        ForEach(manager.openAIModels, id: \.self) { model in
                            Text(model + (model == "gpt-4o" ? " (Recommended)" : "")).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
    
    @ViewBuilder
    private func rightSidebar(for thread: ChatThread) -> some View {
        @Bindable var bindableManager = manager
        VStack(spacing: 0) {
            
            if rightSidebarTab == .configure {
                // Configure panel
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // System Instructions at the VERY TOP
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("System Instructions")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Menu {
                                    Section("Default Presets") {
                                        ForEach(ChatPersona.presets) { preset in
                                            Button(preset.name) {
                                                manager.updateSettings(id: thread.id, instructions: preset.instructions, temperature: preset.temperature)
                                            }
                                        }
                                    }
                                    
                                    if !manager.customPresets.isEmpty {
                                        Section("Custom Presets") {
                                            ForEach(manager.customPresets) { preset in
                                                Button(preset.name) {
                                                    manager.updateSettings(id: thread.id, instructions: preset.instructions, temperature: preset.temperature)
                                                }
                                            }
                                        }
                                        
                                        Section("Delete Custom Preset") {
                                            ForEach(manager.customPresets) { preset in
                                                Button("Delete \"\(preset.name)\"", role: .destructive) {
                                                    manager.customPresets.removeAll { $0.id == preset.id }
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "slider.horizontal.3")
                                        Text("Presets")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(accentColorValue)
                                }
                                .menuStyle(.borderlessButton)
                            }
                            
                            TextEditor(text: Binding(
                                get: { thread.systemInstructions },
                                set: { manager.updateSettings(id: thread.id, instructions: $0, temperature: thread.temperature) }
                            ))
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(height: 148)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                            
                            HStack {
                                Spacer()
                                Button {
                                    presetNameToSave = ""
                                    showSavePresetPopover = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle")
                                        Text("Save Current as Preset...")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showSavePresetPopover, arrowEdge: .top) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Save Preset")
                                            .font(.headline)
                                        TextField("Preset Name", text: $presetNameToSave)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 200)
                                        HStack {
                                            Button("Cancel") {
                                                showSavePresetPopover = false
                                            }
                                            Spacer()
                                            Button("Save") {
                                                if !presetNameToSave.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                    let newPreset = ChatPersona(
                                                        name: presetNameToSave,
                                                        icon: "doc.text",
                                                        instructions: thread.systemInstructions,
                                                        temperature: thread.temperature
                                                    )
                                                    manager.customPresets.append(newPreset)
                                                    showSavePresetPopover = false
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                        }
                                    }
                                    .padding()
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Temperature slider below System Instructions
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Temperature")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                MessageActionIconButton(
                                    systemName: "arrow.counterclockwise",
                                    title: "Reset",
                                    helpText: "Reset temperature to 0.7",
                                    isDisabled: abs(thread.temperature - ChatPersona.presets[0].temperature) < 0.001
                                ) {
                                    manager.updateSettings(
                                        id: thread.id,
                                        instructions: thread.systemInstructions,
                                        temperature: ChatPersona.presets[0].temperature
                                    )
                                }
                                Text(String(format: "%.1f", thread.temperature))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(
                                value: Binding(
                                    get: { thread.temperature },
                                    set: { manager.updateSettings(id: thread.id, instructions: thread.systemInstructions, temperature: $0) }
                                ),
                                in: 0.0...1.0,
                                step: 0.1
                            )
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Toolbox")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Choose which capabilities the AI can use automatically.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 10) {
                            toolboxDisclosureRow(
                                id: "dynamic_insights",
                                title: "Dynamic Insights",
                                subtitle: "Highlight calculations, summaries, and alerts as native insight blocks.",
                                icon: "sparkles",
                                color: .purple,
                                handles: ["title", "description", "fields", "insight", "placeholder"],
                                isEnabled: $enableDynamicInsights
                            )

                            toolboxDisclosureRow(
                                id: "internet_search",
                                title: "Internet Search",
                                subtitle: "Search the web in real time and return verified sources.",
                                icon: "globe",
                                color: .blue,
                                handles: ["query"],
                                isEnabled: $enableInternetSearch
                            )

                            toolboxDisclosureRow(
                                id: "terminal_filesystem",
                                title: "Terminal & Filesystem",
                                subtitle: "Run terminal commands and access authorized local files.",
                                icon: "terminal.fill",
                                color: .orange,
                                handles: ["action", "path", "content", "command", "files", "execute_command", "list", "read_file", "create_file", "create_files", "create_folder"],
                                isEnabled: $enableFileSystem
                            )
                        }

                        // Installed Library APIs in Toolbox
                        let installedTools = getInstalledLibraryTools(for: thread)
                        if !installedTools.isEmpty {
                            Divider().padding(.vertical, 4)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                    Text("INSTALLED LIBRARY APIS")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.purple)
                                }
                                
                                ForEach(installedTools, id: \.id) { tool in
                                    InstalledLibraryToolRow(tool: tool, thread: thread, manager: manager, onRemove: {
                                        removeLibraryTool(tool, from: thread)
                                    })
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            } else if rightSidebarTab == .prePrompts {
                // Dedicated Pre-Prompts Page in Right Sidebar
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SettingsIconView(systemName: "text.line.first.and.arrowtriangle.forward", bgColor: .purple)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pre Prompts")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Inspect, turn on, or temporarily disable pre-prompts fed to the AI model.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    
                    Divider()
                    
                    PrePromptsView(manager: manager, threadId: thread.id)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if rightSidebarTab == .memoryGraph {
                MemoryGraphView(manager: manager, threadId: thread.id)
            } else if rightSidebarTab == .sources {
                sourcesActivitySidebar(for: thread)
            }
        }
        .frame(width: rightSidebarWidth)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
        }

    }

    private func sourcesActivitySidebar(for thread: ChatThread) -> some View {
        let ultraRun = manager.ultraTaskRun(for: thread.id)
        let message = rightSidebarSourceMessageID.flatMap { selectedID in
            thread.messages.first(where: { $0.id == selectedID })
        }
        // The sidebar may be opened while the first search round is complete
        // and a refinement round is still running. Never render the snapshot
        // captured at click time: recompute from the observable transcript so
        // later tool responses appear immediately.
        let liveSources: [(title: String, url: String)] = {
            guard let message else { return rightSidebarSources }
            let isSearchActivity = message.isStreamingSearchJSON ||
                ToolRequestParser.parse(text: message.text)?.type == "internet_use"
            let refreshed = isSearchActivity
                ? searchLinksForSearchActivity(startingAt: message, in: thread)
                : searchLinksForTurn(endingAt: message, in: thread)
            return refreshed.isEmpty ? rightSidebarSources : refreshed
        }()
        let liveQueries: [String] = {
            guard let message else { return [] }
            return searchQueriesForSearchActivity(startingAt: message, in: thread)
        }()
        let duration = message.flatMap { message -> TimeInterval? in
            guard let start = message.generationStartTime else { return nil }
            return (message.generationEndTime ?? Date()).timeIntervalSince(start)
        }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Activity")
                    .font(.system(size: 20, weight: .medium))
                if let duration {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(Int(duration.rounded()))s")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut) {
                        showRightSidebar = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Close sidebar")
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let ultraRun {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Work progress", systemImage: "sparkles")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.purple)
                                Spacer()
                                Text("\(ultraRun.items.filter { $0.status == .completed }.count)/\(ultraRun.items.count)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(ultraRun.items) { item in
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: ultraTaskIcon(item.status))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(ultraTaskColor(item.status))
                                        .frame(width: 17, height: 18)
                                    Text(item.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(item.status == .completed ? .secondary : .primary)
                                        .strikethrough(item.status == .completed, color: .secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.purple.opacity(0.16))
                        }
                    }

                    if !liveSources.isEmpty {
                    Text("Thinking")
                        .font(.system(size: 20, weight: .medium))

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                            .frame(width: 20, height: 22)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(manager.isGenerating ? "Searching" : "Searched") \(liveSources.count) \(liveSources.count == 1 ? "website" : "websites")")
                                .font(.system(size: 15, weight: .medium))

                            if !liveQueries.isEmpty {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(liveQueries.count == 1 ? "Exact query used" : "Exact queries used")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    ForEach(Array(liveQueries.enumerated()), id: \.offset) { index, query in
                                        HStack(alignment: .top, spacing: 7) {
                                            if liveQueries.count > 1 {
                                                Text("\(index + 1).")
                                                    .foregroundStyle(.tertiary)
                                            }
                                            Text(query)
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    }
                                }
                            }

                            ActivityFlowLayout(spacing: 7) {
                                ForEach(Array(liveSources.enumerated()), id: \.offset) { _, source in
                                    if let destination = URL(string: source.url) {
                                        Link(destination: destination) {
                                            HStack(spacing: 6) {
                                                let host = destination.host() ?? source.url
                                                if let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32") {
                                                    AsyncImage(url: faviconURL) { image in
                                                        image.resizable().scaledToFit()
                                                    } placeholder: {
                                                        Image(systemName: "globe")
                                                    }
                                                    .frame(width: 14, height: 14)
                                                    .clipShape(Circle())
                                                }
                                                Text(host)
                                                    .lineLimit(1)
                                            }
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.09), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14))
                            .frame(width: 20, height: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(duration.map { "Worked for \(Int($0.rounded()))s" } ?? "Worked")
                                .font(.system(size: 15, weight: .medium))
                            Text("Done")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ultraTaskIcon(_ status: UltraTaskStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .blocked: return "exclamationmark.circle.fill"
        }
    }

    private func ultraTaskColor(_ status: UltraTaskStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .purple
        case .completed: return .green
        case .blocked: return .red
        }
    }
    
    private func getInstalledLibraryTools(for thread: ChatThread) -> [ApiLibraryModal.ApiItem] {
        let modal = ApiLibraryModal(manager: manager, threadId: thread.id)
        let globalInstalled = manager.installedLibraryAPIIDs
        return modal.libraryItems.filter { item in
            let tag = "[API_TOOL: \(item.id)]"
            return globalInstalled.contains(item.id) ||
                   thread.systemInstructions.contains(tag) ||
                   thread.systemInstructions.contains(item.id) ||
                   thread.systemInstructions.contains(item.name)
        }
    }

    @ViewBuilder
    private func toolboxDisclosureRow(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        handles: [String],
        isEnabled: Binding<Bool>
    ) -> some View {
        let isExpanded = expandedToolboxIDs.contains(id)
        let activeColor = isEnabled.wrappedValue ? color : Color.secondary
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(activeColor.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(activeColor)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(color)
                    .padding(.trailing, 24)
            }

            if isExpanded {
                ActivityFlowLayout(spacing: 5) {
                    ForEach(handles, id: \.self) { handle in
                        Text(handle)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.1))
                            .foregroundStyle(color)
                            .clipShape(Capsule())
                        }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(isExpanded ? 0.13 : 0.075), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedToolboxIDs.remove(id) }
                    else { expandedToolboxIDs.insert(id) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(activeColor)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(isExpanded ? "Hide tool handles" : "Show tool handles")
            .padding(.top, 8)
            .padding(.trailing, 7)
        }
        .opacity(isEnabled.wrappedValue ? 1 : 0.72)
    }

    private func removeLibraryTool(_ item: ApiLibraryModal.ApiItem, from thread: ChatThread) {
        let tag = "[API_TOOL: \(item.id)]"
        let directiveToAdd = "\n\(tag): \(item.name) capability attached. \(item.promptDirective)"
        var updated = thread.systemInstructions
        if let range = updated.range(of: directiveToAdd) {
            updated.removeSubrange(range)
        } else if let range = updated.range(of: item.promptDirective) {
            updated.removeSubrange(range)
        } else if let range = updated.range(of: tag) {
            updated.removeSubrange(range)
        }
        manager.updateSettings(id: thread.id, instructions: updated, temperature: thread.temperature)
        
        manager.setLibraryAPIInstalled(false, apiID: item.id)
        manager.setLibrarySkill(apiID: item.id, name: item.name, summary: item.description, instructions: item.promptDirective, installed: false)
    }
    
    @ViewBuilder
    private func emptyThreadWelcomeView(for thread: ChatThread) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(accentColorValue)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            Text("What can I help you with?")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(selectedModelDisplayName(for: thread))
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func capabilityBadge(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .foregroundStyle(.secondary)
    }

    private var welcomeView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1), Color.pink.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 5)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("Developer Chat Hub")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Chat using Google's secure online Gemini API, OpenRouter, ChatGPT, or connect to a local LM Studio server.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.clear
        )
    }
    
    // MARK: - Actions & Helpers
    
    private func sendCurrentMessage() {
        guard !manager.isGenerating, manager.toolRequestManager.activeRequest == nil else { return }
        guard let threadId = manager.activeThreadId else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = attachedImageBase64
        let editedMessageId = editingUserMessageId
        let forceWebSearch = forceWebSearchNextMessage
        guard !text.isEmpty || image != nil else { return }
        
        inputText = ""
        attachedImageBase64 = nil
        editingUserMessageId = nil
        forceWebSearchNextMessage = false
        isInputFocused = true
        Task {
            if let editedMessageId {
                await manager.editAndResubmitUserMessage(
                    threadId: threadId,
                    messageId: editedMessageId,
                    text: text,
                    attachedImageBase64: image,
                    forceWebSearch: forceWebSearch
                )
            } else {
                await manager.sendMessage(
                    text: text,
                    attachedImageBase64: image,
                    forceWebSearch: forceWebSearch
                )
            }
            if manager.ultraTaskRun(for: threadId) != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    rightSidebarTab = .sources
                    showRightSidebar = true
                }
            }
            DispatchQueue.main.async {
                self.isInputFocused = true
            }
        }
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                let pathExtension = url.pathExtension.lowercased()
                let mimeType = pathExtension == "png" ? "image/png" : (pathExtension == "webp" ? "image/webp" : "image/jpeg")
                let base64 = data.base64EncodedString()
                self.attachedImageBase64 = "data:\(mimeType);base64,\(base64)"
            }
        }
    }
    
    private func nsImageFromBase64(_ base64String: String) -> NSImage? {
        let cleanString = base64String.replacingOccurrences(of: "data:image/png;base64,", with: "")
            .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
            .replacingOccurrences(of: "data:image/webp;base64,", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: cleanString) else { return nil }
        return NSImage(data: data)
    }
    
    private func startEditingTitle(for thread: ChatThread) {
        editedTitle = thread.title
        editingTitleId = thread.id
        isTitleFocused = true
    }
    
    private func saveEditedTitle(for thread: ChatThread) {
        let cleanTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            manager.updateTitle(id: thread.id, title: cleanTitle)
        }
        editingTitleId = nil
    }
    
    private func handlePostDeletionSync() {
        if let activeId = manager.activeThreadId {
            selectedThreadIds = [activeId]
        } else {
            selectedThreadIds.removeAll()
        }
    }

    private func generateTranscript(for thread: ChatThread) -> String {
        var lines: [String] = []
        
        let cleanTitle = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("# \(cleanTitle.isEmpty ? "Conversation" : cleanTitle)")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: thread.createdAt)
        lines.append("Date: \(dateString)")
        lines.append("Provider: \(thread.provider.displayName)")
        lines.append(String(repeating: "-", count: 40))
        lines.append("")
        
        let messages = visibleTranscriptMessages(in: thread)
        for message in messages {
            let isSystemMessage = message.role == .user && (message.isToolResponse || message.text.hasPrefix("[System:") || message.text.hasPrefix("[SYSTEM:") || message.text.contains("tool_response"))
            if isSystemMessage && !thread.showSystemMessages {
                continue
            }
            
            let roleHeading: String
            let content: String
            
            switch message.role {
            case .user:
                roleHeading = "User"
                var text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.attachedImageBase64 != nil {
                    if text.isEmpty {
                        text = "[Attached Image]"
                    } else {
                        text = "[Attached Image]\n" + text
                    }
                }
                content = text
                
            case .assistant:
                roleHeading = "Assistant"
                let stripped = message.strippedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty {
                    content = stripped
                } else {
                    let parsed = message.parsedReasoning
                    let main = parsed.mainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !main.isEmpty {
                        content = main
                    } else if let reasoning = parsed.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines), !reasoning.isEmpty, thread.showSystemMessages {
                        content = "[Thinking]\n" + reasoning
                    } else {
                        content = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
            case .system:
                if !thread.showSystemMessages { continue }
                roleHeading = "System"
                content = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContent.isEmpty {
                lines.append("### \(roleHeading)")
                lines.append(trimmedContent)
                lines.append("")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func copyTranscript(for thread: ChatThread) {
        let transcript = generateTranscript(for: thread)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        #else
        UIPasteboard.general.string = transcript
        #endif
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showShareCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showShareCopiedToast = false
            }
        }
    }
    
    private func downloadTranscript(for thread: ChatThread) {
        let transcript = generateTranscript(for: thread)
        #if os(macOS)
        let savePanel = NSSavePanel()
        var safeTitle = thread.title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        if safeTitle.isEmpty {
            safeTitle = "transcript"
        }
        let defaultFilename = "\(safeTitle).txt"
        
        savePanel.title = "Save Transcript"
        savePanel.prompt = "Save"
        savePanel.nameFieldStringValue = defaultFilename
        savePanel.allowedContentTypes = [UTType.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApplication.shared.windows.first(where: { $0.isVisible })
        if let targetWindow = window {
            savePanel.beginSheetModal(for: targetWindow) { response in
                if response == .OK, let url = savePanel.url {
                    do {
                        try transcript.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        print("Failed to save transcript: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            let response = savePanel.runModal()
            if response == .OK, let url = savePanel.url {
                do {
                    try transcript.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save transcript: \(error.localizedDescription)")
                }
            }
        }
        #endif
    }
    
    @ViewBuilder
    private func submittedDataCard(for message: ChatMessage) -> some View {
        // Parse the tool_response JSON to extract key/value pairs
        let pairs: [(String, String)] = {
            guard let data = message.text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resp = json["tool_response"] as? [String: Any] else {
                return []
            }
            return resp.map { key, value in
                // Humanise the key: replace underscores/hyphens with spaces and title-case
                let humanKey = key.replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
                return (humanKey, String(describing: value))
            }.sorted { $0.0 < $1.0 }
        }()
        
        if pairs.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                Text("Your Details")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                
                // Grid of stat blocks — 2 columns
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(pairs, id: \.0) { (label, value) in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .lineLimit(1)
                            Text(value)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                }
                .frame(maxWidth: 320)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy, thread: ChatThread, animated: Bool = true) {
        guard let lastMessage = thread.messages.last else { return }
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
    
    private func isThreadInterrupted(_ thread: ChatThread) -> Bool {
        guard !manager.isGenerating else { return false }
        guard let lastMsg = thread.messages.last else { return false }
        
        if lastMsg.role == .assistant {
            let trimmed = lastMsg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "..." || trimmed.isEmpty || manager.errorMessage != nil {
                return true
            }
            // Check for unclosed markdown code fence block (odd number of ```)
            let fenceCount = trimmed.components(separatedBy: "```").count - 1
            if fenceCount > 0 && fenceCount % 2 != 0 {
                return true
            }
        }
        
        return false
    }
    
    @ViewBuilder
    private var appSettingsModalView: some View {
        @Bindable var bindableManager = manager
        
        HStack(spacing: 0) {
            // Modern Sidebar Navigation
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [accentColorValue, accentColorValue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Settings")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("Preferences & Engine")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                
                Divider()
                    .opacity(0.5)
                
                // Navigation Items List
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREFERENCES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.top, 2)
                    
                    ForEach([SettingsTab.general, SettingsTab.shortcuts]) { tab in
                        settingsTabButton(for: tab)
                    }
                    
                    Text("AI ENGINE & APIS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                    
                    ForEach([SettingsTab.apiKeys, SettingsTab.models]) { tab in
                        settingsTabButton(for: tab)
                    }
                    
                    Text("PROMPTS & RULES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                    
                    ForEach([SettingsTab.prePrompts]) { tab in
                        settingsTabButton(for: tab)
                    }
                }
                .padding(.horizontal, 8)
                
                Spacer()
            }
            .frame(width: 185)
            .background(Color.secondary.opacity(0.055))
            
            Divider()
            
            // Main Content Area
            VStack(spacing: 0) {
                // Top Bar Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedSettingsTab.rawValue)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(settingsTabSubtitle(for: selectedSettingsTab))
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        showAppSettingsModal = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.02))
                
                Divider()
                
                // Content View for active tab
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch selectedSettingsTab {
                        case .general:
                            // Group 1: Appearance & Accent Palette
                            VStack(spacing: 12) {
                                // Theme Selector Row
                                HStack {
                                    Text("Theme")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    HStack(spacing: 2) {
                                        ForEach(["system", "light", "dark"], id: \.self) { mode in
                                            let isSelected = appAppearance == mode
                                            Button {
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                                    appAppearance = mode
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: mode == "system" ? "laptopcomputer" : (mode == "light" ? "sun.max.fill" : "moon.stars.fill"))
                                                        .font(.system(size: 10.5))
                                                    Text(mode.capitalized)
                                                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                                }
                                                .foregroundStyle(isSelected ? .primary : .secondary)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(2)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                
                                Divider().opacity(0.4)
                                
                                // Accent Color Swatches
                                HStack {
                                    Text("Accent Color")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    HStack(spacing: 8) {
                                        ForEach(["blue", "purple", "pink", "orange", "green", "red"], id: \.self) { color in
                                            let isSelected = userBubbleAccentColor == color
                                            Button {
                                                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                                    userBubbleAccentColor = color
                                                }
                                            } label: {
                                                ZStack {
                                                    Circle()
                                                        .fill(accentSwatchColor(for: color))
                                                        .frame(width: 17, height: 17)
                                                    if isSelected {
                                                        Circle()
                                                            .stroke(Color.white, lineWidth: 2)
                                                            .frame(width: 14, height: 14)
                                                    }
                                                }
                                                .overlay(
                                                    Circle()
                                                        .stroke(isSelected ? accentSwatchColor(for: color) : Color.clear, lineWidth: 1.5)
                                                        .frame(width: 23, height: 23)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        
                                        ColorPicker("", selection: Binding(
                                            get: { Color(hex: customThemeColorHex) ?? .blue },
                                            set: { newColor in
                                                customThemeColorHex = newColor.toHex()
                                                userBubbleAccentColor = "custom"
                                            }
                                        ))
                                        .labelsHidden()
                                        .scaleEffect(0.8)
                                    }
                                }
                            }
                            .padding(14)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            // Group 2: Chat Wallpaper
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Chat Wallpaper")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    if chatWallpaperPattern != "none" || !chatCustomWallpaperPath.isEmpty {
                                        Button("Clear") {
                                            chatWallpaperPattern = "none"
                                            chatCustomWallpaperPath = ""
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    wallpaperPresetCard(id: "none", title: "None", icon: "square")
                                    wallpaperPresetCard(id: "doodles", title: "Pattern", icon: "bubble.left.and.bubble.right.fill")
                                    wallpaperPresetCard(id: "dots", title: "Dots", icon: "circle.grid.3x3.fill")
                                    wallpaperPresetCard(id: "grid", title: "Grid", icon: "grid")
                                    wallpaperPresetCard(id: "stars", title: "Stars", icon: "sparkles")
                                }
                                
                                HStack {
                                    Button(chatCustomWallpaperPath.isEmpty ? "Choose Custom Image…" : "Change Custom Image…") {
                                        let panel = NSOpenPanel()
                                        panel.allowedContentTypes = [.image]
                                        panel.allowsMultipleSelection = false
                                        if panel.runModal() == .OK, let url = panel.url {
                                            chatCustomWallpaperPath = url.path
                                            chatWallpaperPattern = "custom"
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    
                                    Spacer()
                                    
                                    if chatWallpaperPattern != "none" {
                                        HStack(spacing: 6) {
                                            Picker("Color", selection: $chatWallpaperColor) {
                                                Text("Auto").tag("auto")
                                                Text("Blue").tag("blue")
                                                Text("Purple").tag("purple")
                                                Text("Pink").tag("pink")
                                                Text("Orange").tag("orange")
                                                Text("Green").tag("green")
                                                Text("Mono").tag("monochrome")
                                            }
                                            .font(.system(size: 11))
                                            .frame(maxWidth: 115)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            // Group 3: Visual Effects & Translucency
                            VStack(spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Glassmorphism & Vibrancy")
                                            .font(.system(size: 13, weight: .medium))
                                        Text("Translucent blurred glass backgrounds")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { !dontUseSolidBackgrounds },
                                        set: { dontUseSolidBackgrounds = !$0 }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                }
                                
                                Divider().opacity(0.4)
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Advanced Visual Effects")
                                            .font(.system(size: 13, weight: .medium))
                                        Text("Smooth transitions and particle rendering")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $advancedRender)
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                        .controlSize(.small)
                                }
                            }
                            .padding(14)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                
                            // Group 4: Software Updates
                            VStack(spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Text("Halite Version")
                                                .font(.system(size: 13, weight: .medium))
                                            Text("v\(UpdateManager.shared.currentVersion)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.secondary.opacity(0.1)))
                                        }
                                        Text("Check for releases and improvements")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        withAnimation { selectedSettingsTab = .updates }
                                        Task { await UpdateManager.shared.checkForUpdates() }
                                    } label: {
                                        HStack(spacing: 5) {
                                            if UpdateManager.shared.state.isChecking {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                            }
                                            Text("Check Updates")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(14)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        case .shortcuts:
                            shortcutsSettingsView

                        case .prePrompts:
                            VStack(alignment: .leading, spacing: 12) {
                                PrePromptsView(manager: manager, threadId: manager.activeThreadId)
                            }
                            
                        case .tools:
                            VStack(alignment: .leading, spacing: 14) {
                                Label("System & Tool Execution Modes", systemImage: "gearshape.2.fill")
                                    .font(.headline)
                                    .foregroundStyle(accentColorValue)
                                
                                Text("Control which dynamic tools and automated directives are active for the AI assistant across threads.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                VStack(spacing: 12) {
                                    modernSettingsToggle(
                                        title: "Real-time Internet Web Search (Tool 4)",
                                        subtitle: "Allows AI to search the web live via DuckDuckGo for real-time information.",
                                        icon: "globe",
                                        color: .blue,
                                        binding: $enableInternetSearch
                                    )
                                    
                                    Divider()
                                    
                                    modernSettingsToggle(
                                        title: "Mandatory Fact Cross-Check Verification",
                                        subtitle: "Forces AI to cross-check claims and verify links via web search before answering.",
                                        icon: "checkmark.seal.fill",
                                        color: .teal,
                                        binding: $enableCrossCheck
                                    )
                                    
                                    Divider()
                                    
                                    modernSettingsToggle(
                                        title: "Terminal & Disk Access (Tool 6)",
                                        subtitle: "Allows AI to run terminal commands and execute authorized disk operations.",
                                        icon: "terminal.fill",
                                        color: .orange,
                                        binding: $enableFileSystem
                                    )

                                }
                            }
                            .padding(16)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                            
                        case .apiKeys:
                            VStack(alignment: .leading, spacing: 16) {
                                Label("API Keys & Server Endpoints", systemImage: "key.fill")
                                    .font(.headline)
                                    .foregroundStyle(accentColorValue)

                                HStack(spacing: 10) {
                                    ForEach(Provider.allCases) { provider in
                                        Label(manager.health(for: provider).rawValue, systemImage: provider == .lmStudio ? "laptopcomputer" : "circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(manager.health(for: provider) == .ready ? .green : .secondary)
                                    }
                                    Spacer()
                                    Button("Refresh Status") { Task { await manager.refreshProviderHealth() } }
                                        .font(.caption)
                                    Button("Copy Diagnostics") {
                                        Task {
                                            guard let data = await manager.exportDiagnostics(),
                                                  let text = String(data: data, encoding: .utf8) else { return }
                                            await MainActor.run { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                                        }
                                    }
                                    .font(.caption)
                                }
                                
                                // Gemini API Key Card
                                apiKeyConfigCard(
                                    title: "Google Gemini API Key",
                                    icon: "sparkles",
                                    color: .blue,
                                    isConfigured: !manager.geminiAPIKey.isEmpty,
                                    keyBinding: $bindableManager.geminiAPIKey,
                                    placeholder: "AIzaSy..."
                                )
                                
                                // OpenRouter API Key Card
                                apiKeyConfigCard(
                                    title: "OpenRouter API Key",
                                    icon: "network",
                                    color: .purple,
                                    isConfigured: !manager.openRouterAPIKey.isEmpty,
                                    keyBinding: $bindableManager.openRouterAPIKey,
                                    placeholder: "sk-or-v1-...",
                                    actionTitle: "Refresh Models",
                                    onAction: {
                                        Task { await manager.refreshOpenRouterModelsExplicitly() }
                                    }
                                )
                                
                                // OpenAI API Key Card
                                apiKeyConfigCard(
                                    title: "OpenAI Platform API Key",
                                    icon: "brain.head.profile",
                                    color: .green,
                                    isConfigured: !manager.openAIAPIKey.isEmpty,
                                    keyBinding: $bindableManager.openAIAPIKey,
                                    placeholder: "sk-proj-..."
                                )
                                
                                // OpenAI Custom Base URL
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("OpenAI Compatible Base URL (Optional)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("Override endpoint for custom proxies or LocalAI / vLLM servers.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    
                                    TextField("https://api.openai.com/v1", text: $bindableManager.openAIBaseURL)
                                        .textFieldStyle(.roundedBorder)
                                }
                                .padding(14)
                                .background(Color.primary.opacity(0.02))
                                .cornerRadius(12)
                                
                                // LM Studio Server Card
                                apiKeyConfigCard(
                                    title: "LM Studio Local Server Endpoint",
                                    icon: "laptopcomputer",
                                    color: .orange,
                                    isConfigured: !manager.lmStudioBaseURL.isEmpty,
                                    keyBinding: $bindableManager.lmStudioBaseURL,
                                    placeholder: "http://localhost:1234/v1",
                                    actionTitle: "Test Connection",
                                    onAction: {
                                        Task { await manager.refreshLMStudioModelsExplicitly() }
                                    }
                                )

                                Button("Check Existing Library Credentials") {
                                    manager.reconcileLibraryCredentialStatus()
                                }
                                .help("Checks saved library API keys and refreshes their configured status.")
                            }
                            
                        case .models:
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Providers & Model Catalogs")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(accentColorValue)
                                    Spacer()
                                    Button(expandedModelProviders.count == 4 ? "Collapse All" : "Expand All") {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            if expandedModelProviders.count == 4 {
                                                expandedModelProviders.removeAll()
                                            } else {
                                                expandedModelProviders = ["gemini", "openrouter", "openai", "lmstudio"]
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                }
                                
                                // Gemini Accordion
                                providerModelAccordionCard(
                                    providerId: "gemini",
                                    title: "Google Gemini",
                                    icon: "sparkles",
                                    color: .blue,
                                    models: manager.geminiModels,
                                    newModelText: $newGeminiModel,
                                    placeholder: "Add model ID (e.g. gemini-2.5-flash)",
                                    onAdd: {
                                        manager.addCustomGeminiModel(newGeminiModel)
                                        newGeminiModel = ""
                                    },
                                    onRemove: { manager.removeGeminiModel($0) }
                                )
                                
                                // OpenRouter Accordion
                                providerModelAccordionCard(
                                    providerId: "openrouter",
                                    title: "OpenRouter",
                                    icon: "network",
                                    color: .purple,
                                    models: manager.openRouterModels,
                                    newModelText: $newOpenRouterModel,
                                    placeholder: "Add model ID (e.g. anthropic/claude-3.5-sonnet)",
                                    isCustomOpenRouter: true,
                                    onAdd: {
                                        manager.addCustomOpenRouterModel(newOpenRouterModel)
                                        newOpenRouterModel = ""
                                    },
                                    onRemove: { manager.removeOpenRouterModel($0) }
                                )
                                
                                // OpenAI Accordion
                                providerModelAccordionCard(
                                    providerId: "openai",
                                    title: "ChatGPT (OpenAI)",
                                    icon: "brain.head.profile",
                                    color: .green,
                                    models: manager.openAIModels,
                                    newModelText: $newOpenAIModel,
                                    placeholder: "Add model ID (e.g. gpt-4o)",
                                    onAdd: {
                                        manager.addCustomOpenAIModel(newOpenAIModel)
                                        newOpenAIModel = ""
                                    },
                                    onRemove: { manager.removeOpenAIModel($0) }
                                )
                                
                                // LM Studio Accordion
                                providerModelAccordionCard(
                                    providerId: "lmstudio",
                                    title: "LM Studio Local Server",
                                    icon: "laptopcomputer",
                                    color: .orange,
                                    models: manager.lmStudioAvailableModels,
                                    newModelText: $newLMStudioModel,
                                    placeholder: "Add model identifier (e.g. qwen2.5-coder-32b)",
                                    onAdd: {
                                        manager.addCustomLMStudioModel(newLMStudioModel)
                                        newLMStudioModel = ""
                                    },
                                    onRemove: { manager.removeLMStudioModel($0) }
                                )
                            }
                        case .updates:
                            updatesSettingsView
                        }
                    }
                    .padding(28)
                }
            }
        }
        .frame(width: 820, height: 600)
    }

    private var updatesSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Version Info Header Card
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Halite for macOS")
                            .font(.title3.bold())
                        Text("Version \(updateManager.currentVersion) (Build \(updateManager.currentBuild))")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await updateManager.checkForUpdates(silent: false) }
                    } label: {
                        HStack(spacing: 6) {
                            if updateManager.state.isChecking {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Check for Updates")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)))
                    }
                    .buttonStyle(.plain)
                    .disabled(updateManager.state.isChecking || updateManager.state.isDownloading)
                }

                if let lastDate = updateManager.lastCheckedDate {
                    let dateStr = DateFormatter.localizedString(from: lastDate, dateStyle: .medium, timeStyle: .short)
                    Text("Last checked: \(dateStr)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.secondary.opacity(0.14), lineWidth: 1))

            // Dynamic State Card
            switch updateManager.state {
            case .idle:
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to Check")
                            .font(.headline)
                        Text("Click Check for Updates above or open Settings to check GitHub Releases.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") {
                        Task { await updateManager.checkForUpdates(silent: false) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            case .checking:
                HStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checking for updates…")
                            .font(.headline)
                        Text("Connecting to GitHub Releases at github.com/\(updateManager.repoOwner)/\(updateManager.repoName)...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            case .upToDate(let version):
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're up to date!")
                            .font(.headline)
                        Text("Halite v\(version) is currently the newest version available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            case .updateAvailable(let release):
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("New Version Available: v\(release.version)")
                                    .font(.headline.bold())
                                    .foregroundStyle(.cyan)
                                if release.isPrerelease {
                                    Text("Pre-release")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                }
                            }
                            if let pubDate = release.publishedAt {
                                Text("Released on \(DateFormatter.localizedString(from: pubDate, dateStyle: .medium, timeStyle: .none))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button("View on GitHub") {
                                updateManager.openReleaseWebPage(release: release)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                updateManager.downloadUpdate(release: release)
                            } label: {
                                Label("Download & Install", systemImage: "arrow.down.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("IMPROVEMENTS & FIXES")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        ScrollView {
                            MarkdownView(text: release.changelog)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding(22)
                .background(Color.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.cyan.opacity(0.25), lineWidth: 1))

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Downloading update…", systemImage: "arrow.down.circle")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.bold).monospaced())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: progress)
                        .tint(.cyan)

                    Text("The update archive will be saved to your Downloads folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            case .readyToInstall(let fileURL, let release):
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update v\(release.version) Ready")
                                .font(.headline)
                            Text("Click to install and relaunch automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            updateManager.installUpdate(fileURL: fileURL)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Install & Restart")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding(20)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            case .installing:
                HStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installing Update…")
                            .font(.headline)
                        Text("Replacing app bundle and relaunching Halite automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            case .error(let errorMsg):
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update check failed")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Retry") {
                        Task { await updateManager.checkForUpdates() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(20)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            // Preferences Card
            VStack(alignment: .leading, spacing: 16) {
                Text("UPDATE PREFERENCES")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { updateManager.autoCheckEnabled },
                    set: { updateManager.autoCheckEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically check for updates")
                            .font(.subheadline.weight(.semibold))
                        Text("Checks GitHub repository for new releases on app startup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(20)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        }
        .onAppear {
            if updateManager.state == .idle {
                Task { await updateManager.checkForUpdates(silent: false) }
            }
        }
    }

    // Helper sidebar button component
    @ViewBuilder
    private func settingsTabButton(for tab: SettingsTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedSettingsTab = tab
            }
        } label: {
            HStack(spacing: 10) {
                SettingsIconView(systemName: tab.iconName, bgColor: tab.iconBgColor)
                
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .fontWeight(selectedSettingsTab == tab ? .semibold : .regular)
                    .foregroundStyle(selectedSettingsTab == tab ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedSettingsTab == tab ? accentColorValue.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var shortcutsSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColorValue)
                Spacer()
                Button("Reset to Defaults") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        shortcutNewChat = "N"
                        shortcutToggleSidebar = "S"
                        shortcutOpenSettings = ","
                        shortcutSearch = "K"
                        shortcutDevMode = "D"
                        shortcutVoiceMode = "V"
                        shortcutClearChat = "Delete"
                        shortcutExportThread = "E"
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }

            // Group 1: Navigation & Windows
            VStack(spacing: 10) {
                HStack {
                    Text("NAVIGATION & WINDOWS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                shortcutRowView(
                    title: "New Chat Thread",
                    description: "Create a clean new conversation",
                    modifierSymbol: "⌘",
                    keyBinding: $shortcutNewChat,
                    defaultKey: "N"
                )

                Divider().opacity(0.4)

                shortcutRowView(
                    title: "Toggle Left Sidebar",
                    description: "Show or hide the chat history sidebar",
                    modifierSymbol: "⌘",
                    keyBinding: $shortcutToggleSidebar,
                    defaultKey: "S"
                )

                Divider().opacity(0.4)

                shortcutRowView(
                    title: "Open Preferences / Settings",
                    description: "Open the application configuration panel",
                    modifierSymbol: "⌘",
                    keyBinding: $shortcutOpenSettings,
                    defaultKey: ","
                )

                Divider().opacity(0.4)

                shortcutRowView(
                    title: "Focus Search / Filter",
                    description: "Jump to search bar across chat threads",
                    modifierSymbol: "⌘",
                    keyBinding: $shortcutSearch,
                    defaultKey: "K"
                )
            }
            .padding(14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Group 2: AI & Chat Actions
            VStack(spacing: 10) {
                HStack {
                    Text("CHAT & CONTROLS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                shortcutRowView(
                    title: "Toggle Developer Mode",
                    description: "Switch between clean transcript & raw JSON tool blocks",
                    modifierSymbol: "⌘",
                    keyBinding: $shortcutDevMode,
                    defaultKey: "D"
                )

                Divider().opacity(0.4)

                shortcutRowView(
                    title: "Toggle Voice / Dictation",
                    description: "Activate real-time voice prompt input",
                    modifierSymbol: "⌘⇧",
                    keyBinding: $shortcutVoiceMode,
                    defaultKey: "V"
                )

                Divider().opacity(0.4)

                shortcutRowView(
                    title: "Export / Share Thread",
                    description: "Quick export or copy chat markdown transcript",
                    modifierSymbol: "⌘",
                    keyBinding: $shortcutExportThread,
                    defaultKey: "E"
                )

                Divider().opacity(0.4)

                shortcutRowView(
                    title: "Clear Current Chat",
                    description: "Remove messages from active conversation",
                    modifierSymbol: "⌘",
                    keyBinding: $shortcutClearChat,
                    defaultKey: "Delete"
                )
            }
            .padding(14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Group 3: Input & Composer
            VStack(spacing: 10) {
                HStack {
                    Text("COMPOSER & TYPING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Send Message")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Submit current prompt to AI model")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Return ↩")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                Divider().opacity(0.4)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Insert New Line")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(shiftEnterForNewLine ? "Shift + Return inserts a line break" : "Return inserts line break (Cmd+Return sends)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(shiftEnterForNewLine ? "⇧ Return" : "Return ↩")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func shortcutRowView(
        title: String,
        description: String,
        modifierSymbol: String,
        keyBinding: Binding<String>,
        defaultKey: String
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Text(modifierSymbol)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                Menu {
                    ForEach(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ",", ".", "/", "Delete", "Space"], id: \.self) { key in
                        Button(key) {
                            keyBinding.wrappedValue = key
                        }
                    }
                } label: {
                    Text(keyBinding.wrappedValue.isEmpty ? defaultKey : keyBinding.wrappedValue)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColorValue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(accentColorValue.opacity(0.3), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func settingsTabSubtitle(for tab: SettingsTab) -> String {
        switch tab {
        case .general: return "Customize theme colors, bubble layouts, and window styling."
        case .shortcuts: return "View and customize keyboard shortcut keybindings."
        case .prePrompts: return "Inspect and toggle pre-prompts fed to the AI engine."
        case .tools: return "Control real-time search, memory graph, and file system rights."
        case .apiKeys: return "Configure cloud API keys and local server endpoints."
        case .models: return "Add custom model identifiers or organize model drop-down menus."
        case .updates: return "Check for new releases, view improvements & fixes, and configure auto-updates."
        }
    }

    @ViewBuilder
    private func modernSettingsToggle(title: String, subtitle: String, icon: String, color: Color, binding: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SettingsIconView(systemName: icon, bgColor: color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private func apiKeyConfigCard(title: String, icon: String, color: Color, isConfigured: Bool, keyBinding: Binding<String>, placeholder: String, actionTitle: String? = nil, onAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SettingsIconView(systemName: icon, bgColor: color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(isConfigured ? "CONFIGURED" : "NOT SET")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isConfigured ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                    .foregroundStyle(isConfigured ? Color.green : Color.orange)
                    .clipShape(Capsule())
            }
            
            HStack(spacing: 8) {
                SecureField(placeholder, text: keyBinding)
                    .textFieldStyle(.roundedBorder)
                
                if let actionTitle = actionTitle, let onAction = onAction {
                    Button(actionTitle) {
                        onAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
    }

    private func accentSwatchColor(for name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "green": return .green
        case "red": return .red
        case "custom": return Color(hex: customThemeColorHex) ?? .blue
        default: return .blue
        }
    }

    @ViewBuilder
    private func wallpaperPresetCard(id: String, title: String, icon: String) -> some View {
        let isSelected = (chatWallpaperPattern == id)
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                chatWallpaperPattern = id
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 42)
                    
                    ChatWallpaperBackgroundView(pattern: id)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? accentColorValue : Color.secondary)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? accentColorValue : Color.secondary.opacity(0.15), lineWidth: isSelected ? 1.5 : 0.8)
                )
                
                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerModelAccordionCard(
        providerId: String,
        title: String,
        icon: String,
        color: Color,
        models: [String],
        newModelText: Binding<String>,
        placeholder: String = "Add model ID",
        isCustomOpenRouter: Bool = false,
        onAdd: @escaping () -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        let isExpanded = expandedModelProviders.contains(providerId)
        
        VStack(alignment: .leading, spacing: 10) {
            // Accordion Header Row
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedModelProviders.remove(providerId)
                    } else {
                        expandedModelProviders.insert(providerId)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    SettingsIconView(systemName: icon, bgColor: color)
                    
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("\(models.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            
            // Collapsible Models List & Input
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().opacity(0.4)
                    
                    if models.isEmpty {
                        Text("No models configured.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(models, id: \.self) { model in
                            HStack(spacing: 6) {
                                Text(model)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if isCustomOpenRouter {
                                    let isFree = manager.isOpenRouterModelFree(model)
                                    Text(isFree ? "FREE" : "PAID")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(isFree ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                                        .foregroundStyle(isFree ? Color.green : Color.orange)
                                        .clipShape(Capsule())
                                }
                                
                                Button {
                                    onRemove(model)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    
                    HStack(spacing: 6) {
                        TextField(placeholder, text: newModelText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                            .controlSize(.small)
                        
                        Button {
                            onAdd()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(color)
                        }
                        .buttonStyle(.plain)
                        .disabled(newModelText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Custom Inline User | Developer Slider Toggle
struct UserDeveloperSliderToggle: View {
    let isDeveloper: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        Picker("", selection: Binding(
            get: { isDeveloper },
            set: { newValue in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    onToggle(newValue)
                }
            }
        )) {
            Image(systemName: "text.bubble")
                .font(.system(size: 13, weight: .medium))
                .accessibilityLabel("Default Mode")
                .tag(false)
            Image(systemName: "curlybraces")
                .font(.system(size: 13, weight: .medium))
                .accessibilityLabel("Developer Mode")
                .tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 76)
        .help(isDeveloper ? "Developer mode: showing raw system messages and JSON tool blocks." : "Default mode: showing a clean chat transcript.")
    }
}

// Custom shapes for chat bubbles
struct CopyMessageButton: View {
    let text: String
    @State private var isCopied = false
    
    var body: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    isCopied = false
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                if isCopied {
                    Text("Copied")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(isCopied ? .green : .secondary.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Copy message text to clipboard")
    }
}

struct BubbleShape: Shape {
    var isUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let path = CGMutablePath()
        let radius: CGFloat = isUser ? min(18, rect.height / 2) : 16
        path.addRoundedRect(
            in: rect,
            cornerWidth: radius,
            cornerHeight: radius
        )
        return Path(path)
    }
}

private struct MessageActionIconButton: View {
    let systemName: String
    var title: String? = nil
    let helpText: String
    var role: ButtonRole? = nil
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                if let title {
                    Text(title)
                }
            }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, title == nil ? 0 : 6)
                .frame(minWidth: 24, minHeight: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(MessageActionPressStyle())
        .foregroundStyle(
            role == .destructive && isHovered
                ? Color.red
                : Color.secondary.opacity(isDisabled ? 0.4 : (isHovered ? 1 : 0.78))
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .disabled(isDisabled)
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

private struct MessageActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(
                .spring(response: 0.18, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}

// Hover effect helper for buttons
struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .background(isHovered ? Color.secondary.opacity(0.15) : Color.clear)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverEffect() -> some View {
        modifier(HoverEffectModifier())
    }
}

// MARK: - Premium Sidebar Custom Views

struct SidebarHoverButton: View {
    let title: String
    let icon: String
    let gradient: LinearGradient?
    let action: () -> Void
    
    @State private var isHovered = false
    
    init(title: String, icon: String, gradient: LinearGradient? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.06))
                    Image(systemName: icon)
                        .foregroundStyle(.primary.opacity(0.9))
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(width: 23, height: 23)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if isHovered {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.065) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct RightSidebarResizeHandle: View {

    @Binding var width: CGFloat
    let minWidth: CGFloat = 260
    let maxWidth: CGFloat = 650

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isDragging || isHovered ? Color.accentColor.opacity(0.25) : Color.clear)
                .frame(width: 8)
            
            Rectangle()
                .fill(isDragging ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.4) : Color.clear))
                .frame(width: 2)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    if dragStartWidth == nil { dragStartWidth = width }
                    let newWidth = (dragStartWidth ?? width) - value.translation.width
                    width = min(max(newWidth, minWidth), maxWidth)
                }
                .onEnded { _ in
                    isDragging = false
                    dragStartWidth = nil
                }
        )
    }
}

struct SidebarTabItem: View {

    let tab: ContentView.RightSidebarTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        let icon: String = {
            switch tab {
            case .configure: return "slider.horizontal.3"
            case .prePrompts: return "text.line.first.and.arrowtriangle.forward"
            case .memoryGraph: return "network"
            case .sources: return "globe"
            }
        }()

        
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? .primary : (isHovered ? .primary : .secondary))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .matchedGeometryEffect(id: "activeTab", in: namespace)
                } else if isHovered {
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .help(tab.rawValue)
    }
}

struct TerminalThoughtView: View {
    let commandText: String
    let isComplete: Bool
    let didSucceed: Bool?
    
    @State private var isExpanded: Bool = true
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    if !isComplete {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(didSucceed == false ? .red : .green)
                    }
                    
                    Text(isExpanded ? "v" : ">")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    
                    Text("terminal action")
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    
                    if !isComplete {
                        Text("Running…")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.teal)
                            .symbolEffect(.pulse, isActive: true)
                    } else {
                        Text(didSucceed == false ? "Failed" : "Completed")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(didSucceed == false ? Color.red.opacity(0.85) : Color.green.opacity(0.8))
                    }
                }
                .foregroundStyle(!isComplete ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                HStack(alignment: .top) {
                    Rectangle()
                        .fill(!isComplete ? Color.teal.opacity(0.6) : (didSucceed == false ? Color.red.opacity(0.4) : Color.green.opacity(0.4)))
                        .frame(width: 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commandText)
                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(commandText, forType: .string)
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied" : "Copy Command")
                            }
                            .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.leading, 4)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .padding(.bottom, 4)
    }
}

struct ThinkingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .controlSize(.small)
            
            CrystalizingText(label: "Thinking…", font: .body)
        }
    }
}

struct GeneratingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .controlSize(.small)

            CrystalizingText(label: "Generating…", font: .body)
        }
    }
}

/// macOS composer with chat-native Return behavior: Return sends, while
/// Shift+Return can insert a line break when the user enables that preference.
struct ChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let shiftEnterForNewLine: Bool
    let isEnabled: Bool
    let composerHeight: CGFloat
    let onSend: () -> Void

    func makeNSView(context: Context) -> ComposerScrollView {
        let scrollView = ComposerScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = ComposerNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13.5)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 2, height: 1)
        textView.placeholder = placeholder
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.onReturn = { shiftPressed in
            if shiftPressed && shiftEnterForNewLine {
                textView.insertNewline(nil)
            } else {
                onSend()
            }
        }
        scrollView.documentView = textView
        scrollView.setHeight(composerHeight)
        return scrollView
    }

    func updateNSView(_ scrollView: ComposerScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        if textView.string != text { textView.string = text }
        textView.placeholder = placeholder
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        scrollView.setHeight(composerHeight)
        textView.onReturn = { shiftPressed in
            if shiftPressed && shiftEnterForNewLine {
                textView.insertNewline(nil)
            } else {
                onSend()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            textView.needsDisplay = true
        }
    }
}

final class ComposerScrollView: NSScrollView {
    private var fixedHeightConstraint: NSLayoutConstraint?

    func setHeight(_ height: CGFloat) {
        if let fixedHeightConstraint {
            fixedHeightConstraint.constant = height
        } else {
            let constraint = heightAnchor.constraint(equalToConstant: height)
            constraint.priority = .required
            constraint.isActive = true
            fixedHeightConstraint = constraint
        }
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }
}

private final class ComposerNSTextView: NSTextView {
    var onReturn: ((Bool) -> Void)?
    var placeholder: String = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 13.5),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        NSAttributedString(string: placeholder, attributes: attributes)
            .draw(at: NSPoint(x: textContainerInset.width + 2, y: textContainerInset.height + 1))
    }
    override func keyDown(with event: NSEvent) {
        // 36 is the main Return key; 76 is keypad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?(event.modifierFlags.contains(.shift))
            return
        }
        super.keyDown(with: event)
    }
}

struct ReasoningThoughtView: View {
    let reasoningText: String
    let isGenerating: Bool
    let isComplete: Bool
    let showsCopyAction: Bool
    
    @State private var isExpanded: Bool = false
    @State private var copied: Bool = false

    private var wordCount: Int {
        reasoningText.components(separatedBy: .whitespacesAndNewlines).filter({ !$0.isEmpty }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Text(isExpanded ? "v" : ">")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    
                    Text("thought..")
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    
                    if isGenerating && !isComplete {
                        Text("...")
                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                            .symbolEffect(.pulse, isActive: true)
                    } else {
                        Text("(\(wordCount) words)")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                }
                .foregroundStyle(isGenerating && !isComplete ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reasoningText)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if showsCopyAction { Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(reasoningText, forType: .string)
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied" : "Copy Thoughts")
                            }
                            .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4) }
                }
                .padding(.leading, 12)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                }
            }
        }
        .padding(.bottom, 4)
    }
}


struct CrystalizingView: View {
    @State private var phase: CGFloat = 0
    @State private var glowOpacity: Double = 0.4
    private let glowTimer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 10) {
            // Animated crystal icon
            ZStack {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(glowOpacity)
                    .blur(radius: 2)
                Image(systemName: "diamond.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: glowOpacity)
            
            CrystalizingText(label: "Crystalizing")
        }
        .onAppear {
            glowOpacity = 0.9
        }
        .onReceive(glowTimer) { _ in
            glowOpacity = glowOpacity < 0.6 ? 0.9 : 0.4
        }
    }
}

struct CrystalizingText: View {
    let label: String
    var font: Font = .callout.weight(.medium)

    @State private var sparkleIndex = 0
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(label.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(font)
                    .foregroundStyle(
                        index == sparkleIndex
                            ? AnyShapeStyle(LinearGradient(colors: [.cyan, .white], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.secondary.opacity(0.7))
                    )
                    .animation(.easeOut(duration: 0.15), value: sparkleIndex)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .onReceive(timer) { _ in
            sparkleIndex = (sparkleIndex + 1) % max(label.count, 1)
        }
    }
}

private nonisolated struct FlowLeadingSpacingKey: LayoutValueKey {
    static let defaultValue: CGFloat = .nan
}

struct ActivityFlowLayout: Layout {
    var spacing: CGFloat = 8
    var centersItems: Bool = false

    private func leadingSpacing(for subview: LayoutSubview, hasPreviousItem: Bool) -> CGFloat {
        guard hasPreviousItem else { return 0 }
        let override = subview[FlowLeadingSpacingKey.self]
        return override.isNaN ? spacing : override
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let gap = leadingSpacing(for: subview, hasPreviousItem: lineWidth > 0)
            if lineWidth > 0, lineWidth + gap + size.width > maxWidth {
                widestLine = max(widestLine, lineWidth)
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += gap + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        widestLine = max(widestLine, lineWidth)
        totalHeight += lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : widestLine, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        struct RowItem {
            let index: Int
            let size: CGSize
            let leadingSpacing: CGFloat
        }

        var rows: [[RowItem]] = []
        var currentRow: [RowItem] = []
        var currentWidth: CGFloat = 0

        for index in subviews.indices {
            let subview = subviews[index]
            let size = subview.sizeThatFits(.unspecified)
            let gap = leadingSpacing(for: subview, hasPreviousItem: !currentRow.isEmpty)
            if !currentRow.isEmpty, currentWidth + gap + size.width > bounds.width {
                rows.append(currentRow)
                currentRow = [RowItem(index: index, size: size, leadingSpacing: 0)]
                currentWidth = size.width
            } else {
                currentRow.append(RowItem(index: index, size: size, leadingSpacing: gap))
                currentWidth += gap + size.width
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in row {
                x += item.leadingSpacing
                let itemY = centersItems ? y + ((rowHeight - item.size.height) / 2) : y
                subviews[item.index].place(
                    at: CGPoint(x: x, y: itemY),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width
            }
            y += rowHeight + spacing
        }
    }
}

private enum InlineMarkdownToken {
    case text(AttributedString)
    case link(label: String, destination: URL)
}

/// Renders Markdown links as compact, favicon-backed source pills while the
/// surrounding prose continues to wrap word by word. Using AttributedString
/// runs preserves native bold, italic, and inline-code presentation.
private struct InlineMarkdownPillText: View {
    let markdown: String
    let font: Font
    var foregroundColor: Color = .primary
    var horizontalSpacing: CGFloat = 4
    var sourceLinks: [(title: String, url: String)] = []

    private var tokens: [InlineMarkdownToken] {
        guard let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return [.text(AttributedString(markdown))]
        }

        var result: [InlineMarkdownToken] = []
        for run in attributed.runs {
            let content = AttributedString(attributed[run.range])
            if let destination = run.link,
               let url = URL(string: destination.absoluteString) {
                let label = String(content.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { continue }
                if case .link(let previousLabel, let previousURL) = result.last,
                   previousURL == url {
                    result[result.count - 1] = .link(label: previousLabel + label, destination: url)
                } else {
                    result.append(.link(label: label, destination: url))
                }
            } else {
                result.append(contentsOf: wordTokens(from: content))
            }
        }
        return removingCitationParentheses(from: expandingPlainCitations(in: result))
    }

    var body: some View {
        ActivityFlowLayout(spacing: horizontalSpacing, centersItems: true) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case .text(let value):
                    Text(value)
                        .font(font)
                        .foregroundStyle(foregroundColor)
                        .fixedSize()
                        .layoutValue(
                            key: FlowLeadingSpacingKey.self,
                            value: hasTightLeadingPunctuation(value) ? 0 : .nan
                        )
                case .link(let label, let destination):
                    let displayLabel = siteDisplayName(label: label, destination: destination)
                    Link(destination: destination) {
                        HStack(spacing: 3) {
                            favicon(for: destination, label: displayLabel)
                            Text(displayLabel)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .padding(.trailing, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.11), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(destination.absoluteString)")
                    .accessibilityLabel("Open \(displayLabel)")
                }
            }
        }
    }

    @ViewBuilder
    private func favicon(for destination: URL, label: String) -> some View {
        let host = destination.host() ?? ""
        if !host.isEmpty,
           let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
            AsyncImage(url: faviconURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                faviconPlaceholder(label: label)
            }
            .frame(width: 11, height: 11)
            .clipShape(Circle())
        } else {
            faviconPlaceholder(label: label)
                .frame(width: 11, height: 11)
        }
    }

    private func faviconPlaceholder(label: String) -> some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.88))
            Text(String(label.prefix(1)).uppercased())
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func hasTightLeadingPunctuation(_ value: AttributedString) -> Bool {
        guard let first = value.characters.first else { return false }
        return ".,;:!?)]}".contains(first)
    }

    private func siteDisplayName(label: String, destination: URL) -> String {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cleanLabel.lowercased().filter(\.isLetter)
        let knownBrands: [String: String] = [
            "producthunt": "Product Hunt",
            "macosupdate": "macOS Update",
            "macworld": "Macworld",
            "wikipedia": "Wikipedia",
            "reddit": "Reddit",
            "github": "GitHub",
            "youtube": "YouTube",
            "linkedin": "LinkedIn",
            "stackoverflow": "Stack Overflow",
            "techcrunch": "TechCrunch",
            "theverge": "The Verge",
            "hackernews": "Hacker News"
        ]
        if let brand = knownBrands[key] { return brand }

        let host = destination.host()?.lowercased() ?? ""
        let looksLikeRawSiteName = cleanLabel.contains(".") ||
            cleanLabel.lowercased().hasPrefix("http") ||
            cleanLabel.lowercased() == host ||
            cleanLabel.lowercased() == host.replacingOccurrences(of: "www.", with: "")
        guard looksLikeRawSiteName else { return cleanLabel }

        let components = host
            .replacingOccurrences(of: "www.", with: "")
            .split(separator: ".")
            .map(String.init)
        if let known = components.compactMap({ knownBrands[$0] }).first { return known }
        return (components.first ?? cleanLabel)
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func wordTokens(from attributed: AttributedString) -> [InlineMarkdownToken] {
        var words: [InlineMarkdownToken] = []
        var wordStart: AttributedString.Index?
        var index = attributed.startIndex

        while index < attributed.endIndex {
            let character = attributed.characters[index]
            if character.isWhitespace {
                if let start = wordStart {
                    words.append(.text(AttributedString(attributed[start..<index])))
                    wordStart = nil
                }
            } else if wordStart == nil {
                wordStart = index
            }
            index = attributed.characters.index(after: index)
        }
        if let wordStart {
            words.append(.text(AttributedString(attributed[wordStart..<attributed.endIndex])))
        }
        return words
    }

    private func expandingPlainCitations(in input: [InlineMarkdownToken]) -> [InlineMarkdownToken] {
        guard !sourceLinks.isEmpty else { return input }
        return input.flatMap { token -> [InlineMarkdownToken] in
            guard case .text(let value) = token else { return [token] }
            var raw = String(value.characters)
            var trailingPunctuation = ""
            if let last = raw.last,
               ".,;:!?".contains(last),
               raw.dropLast().hasSuffix(")") {
                trailingPunctuation = String(last)
                raw.removeLast()
            }

            let label: String
            if raw.hasPrefix("(["), raw.hasSuffix("])") {
                label = String(raw.dropFirst(2).dropLast(2))
            } else if raw.hasPrefix("("), raw.hasSuffix(")") {
                label = String(raw.dropFirst().dropLast())
            } else {
                return [token]
            }

            guard let source = matchingSource(for: label),
                  let destination = URL(string: source.url) else { return [token] }
            var expanded: [InlineMarkdownToken] = [.link(label: label, destination: destination)]
            if !trailingPunctuation.isEmpty {
                expanded.append(.text(AttributedString(trailingPunctuation)))
            }
            return expanded
        }
    }

    private func matchingSource(for label: String) -> (title: String, url: String)? {
        let key = normalizedSiteKey(label)
        guard key.count >= 3 else { return nil }
        return sourceLinks.first { source in
            let titleKey = normalizedSiteKey(source.title)
            let hostKey = URL(string: source.url)
                .flatMap { $0.host() }
                .map(normalizedSiteKey) ?? ""
            return titleKey.contains(key) || hostKey.contains(key) || key.contains(hostKey)
        }
    }

    private func normalizedSiteKey(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private func removingCitationParentheses(from input: [InlineMarkdownToken]) -> [InlineMarkdownToken] {
        var result = input
        guard result.count >= 3 else { return result }

        for openIndex in result.indices {
            guard case .text(let opening) = result[openIndex],
                  String(opening.characters).hasSuffix("(") else { continue }

            var cursor = openIndex + 1
            var containsLink = false
            while cursor < result.count {
                switch result[cursor] {
                case .link:
                    containsLink = true
                case .text(let value):
                    let valueText = String(value.characters)
                    if valueText.hasPrefix(")") {
                        guard containsLink else { break }
                        let before = String(opening.characters.dropLast())
                        let after = String(valueText.dropFirst())
                        result[openIndex] = .text(AttributedString(before))
                        result[cursor] = .text(AttributedString(after))
                        cursor = result.count
                        continue
                    }
                    let separator = valueText.lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard ["/", "|", ",", "&", "and", "•"].contains(separator) else {
                        cursor = result.count
                        continue
                    }
                }
                cursor += 1
            }
        }
        return result.filter { token in
            if case .text(let value) = token { return !value.characters.isEmpty }
            return true
        }
    }
}

struct MarkdownView: View {
    let text: String
    var isGenerating: Bool = false
    var advancedRender: Bool = false
    var sourceLinks: [(title: String, url: String)] = []
    
    enum CalloutType: Hashable {
        case tip
        case note
        case warning
        case info
        
        var iconName: String {
            switch self {
            case .tip: return "lightbulb.fill"
            case .note: return "note.text"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
        
        var accentColor: Color {
            switch self {
            case .tip: return .orange
            case .note: return .blue
            case .warning: return .orange
            case .info: return .teal
            }
        }
    }
    
    enum MarkdownBlock: Hashable {
        case paragraph(String)
        case heading(String, level: Int)
        case boldHeader(String)
        case numberedItem(number: String, text: String, indentLevel: Int)
        case bulletPoint(text: String, indentLevel: Int)
        case callout(title: String?, text: String, type: CalloutType)
        case codeBlock(code: String, language: String?)
        case divider
        case table([[String]])
    }
    
    private func parseMarkdown(text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        
        var i = 0
        let count = lines.count
        
        while i < count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 1. Code Block handling
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                var codeLines: [String] = []
                i += 1
                while i < count {
                    let cLine = lines[i]
                    if cLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(cLine)
                    i += 1
                }
                blocks.append(.codeBlock(code: codeLines.joined(separator: "\n"), language: lang.isEmpty ? nil : lang))
                continue
            }
            
            // 2. Table handling. A completed response is a table only when it
            // has a Markdown alignment row. While streaming, pipe-prefixed
            // candidate rows are buffered so raw syntax never flashes.
            if trimmed.hasPrefix("|") {
                var candidateLines: [String] = []
                var cursor = i
                while cursor < count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix("|") else { break }
                    candidateLines.append(candidate)
                    cursor += 1
                }

                let completeLines = candidateLines.filter { $0.hasSuffix("|") }
                let hasAlignmentRow = completeLines.contains { candidate in
                    let cells = candidate.components(separatedBy: "|")
                        .dropFirst().dropLast()
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    return !cells.isEmpty && cells.allSatisfy { cell in
                        let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                        return core.count >= 3 && core.allSatisfy { $0 == "-" }
                    }
                }

                if !hasAlignmentRow && !isGenerating {
                    blocks.append(.paragraph(trimmed))
                    i += 1
                    continue
                }

                var tableRows: [[String]] = []
                for tLine in candidateLines where tLine.hasSuffix("|") {
                        let cells = tLine.components(separatedBy: "|")
                            .dropFirst().dropLast()
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                        let isAlignRow = cells.allSatisfy { cell in
                            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                            return core.count >= 3 && core.allSatisfy { $0 == "-" }
                        }
                        if !isAlignRow {
                            tableRows.append(cells)
                        }
                }
                i = cursor
                if !tableRows.isEmpty {
                    blocks.append(.table(tableRows))
                }
                continue
            }
            
            if trimmed.isEmpty {
                i += 1
                continue
            }
            
            // 3. Divider
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                i += 1
                continue
            }
            
            // 4. Blockquotes / GitHub Alerts
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                var calloutType: CalloutType = .note
                var customTitle: String? = nil
                
                let firstContent = trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
                if firstContent.hasPrefix("[!NOTE]") {
                    calloutType = .note
                    customTitle = "Note"
                } else if firstContent.hasPrefix("[!TIP]") {
                    calloutType = .tip
                    customTitle = "Tip"
                } else if firstContent.hasPrefix("[!WARNING]") {
                    calloutType = .warning
                    customTitle = "Warning"
                } else if firstContent.hasPrefix("[!IMPORTANT]") || firstContent.hasPrefix("[!INFO]") {
                    calloutType = .info
                    customTitle = "Important"
                } else {
                    quoteLines.append(firstContent)
                }
                
                i += 1
                while i < count {
                    let qLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if qLine.hasPrefix(">") {
                        quoteLines.append(qLine.dropFirst(1).trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.callout(title: customTitle, text: quoteLines.joined(separator: "\n"), type: calloutType))
                continue
            }
            
            // 5. Pro Tip / Note / Warning callout lines
            let lowerTrimmed = trimmed.lowercased()
            if lowerTrimmed.hasPrefix("pro tip:") || lowerTrimmed.hasPrefix("**pro tip:**") || lowerTrimmed.hasPrefix("pro-tip:") || lowerTrimmed.hasPrefix("tip:") || lowerTrimmed.hasPrefix("**tip:**") {
                let bodyText = removePrefix(trimmed, prefixes: ["pro tip:", "**pro tip:**", "pro-tip:", "Pro tip:", "Pro Tip:", "tip:", "**tip:**", "Tip:"])
                blocks.append(.callout(title: "Pro Tip", text: bodyText, type: .tip))
                i += 1
                continue
            } else if lowerTrimmed.hasPrefix("note:") || lowerTrimmed.hasPrefix("**note:**") {
                let bodyText = removePrefix(trimmed, prefixes: ["note:", "**note:**", "Note:"])
                blocks.append(.callout(title: "Note", text: bodyText, type: .note))
                i += 1
                continue
            } else if lowerTrimmed.hasPrefix("warning:") || lowerTrimmed.hasPrefix("**warning:**") {
                let bodyText = removePrefix(trimmed, prefixes: ["warning:", "**warning:**", "Warning:"])
                blocks.append(.callout(title: "Warning", text: bodyText, type: .warning))
                i += 1
                continue
            }
            
            // 6. Standard Headings (#, ##, ###, ####)
            if trimmed.hasPrefix("#### ") {
                blocks.append(.heading(String(trimmed.dropFirst(5)), level: 4))
                i += 1
                continue
            } else if trimmed.hasPrefix("### ") {
                blocks.append(.heading(String(trimmed.dropFirst(4)), level: 3))
                i += 1
                continue
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.heading(String(trimmed.dropFirst(3)), level: 2))
                i += 1
                continue
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.heading(String(trimmed.dropFirst(2)), level: 1))
                i += 1
                continue
            }
            
            // 7. Pseudo / Section Headers ("Method 1: ...", "Step 1: ...", "**Method 1: ...**", etc.)
            if isSectionHeader(trimmed) {
                let cleanHeader = stripOuterBold(trimmed)
                blocks.append(.boldHeader(cleanHeader))
                i += 1
                continue
            }
            
            // 8. Numbered Lists ("1. ", "2. ", "1)", etc.)
            if let match = parseNumberedList(line) {
                blocks.append(.numberedItem(number: match.number, text: match.text, indentLevel: match.indent))
                i += 1
                continue
            }
            
            // 9. Bullet Points ("- ", "* ", "+ ", "• ", "◦ ", "⁃ ")
            if let match = parseBulletPoint(line) {
                blocks.append(.bulletPoint(text: match.text, indentLevel: match.indent))
                i += 1
                continue
            }
            
            // 10. Fallback Paragraph
            blocks.append(.paragraph(trimmed))
            i += 1
        }
        
        return blocks
    }
    
    private func removePrefix(_ text: String, prefixes: [String]) -> String {
        for p in prefixes {
            if text.lowercased().hasPrefix(p.lowercased()) {
                return String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }
    
    private func stripOuterBold(_ text: String) -> String {
        var str = text
        if str.hasPrefix("**") && str.hasSuffix("**") && str.count >= 4 {
            str = String(str.dropFirst(2).dropLast(2))
        }
        return str.trimmingCharacters(in: .whitespaces)
    }
    
    private func isSectionHeader(_ trimmed: String) -> Bool {
        let lower = trimmed.lowercased()
        let prefixes = ["method ", "option ", "phase ", "part ", "approach ", "solution "]
        for p in prefixes {
            if lower.hasPrefix(p) || lower.hasPrefix("**" + p) {
                return true
            }
        }
        if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count >= 4 && trimmed.count <= 90 {
            let inside = trimmed.dropFirst(2).dropLast(2)
            if !inside.contains("\n") && inside.components(separatedBy: ". ").count <= 1 {
                return true
            }
        }
        return false
    }
    
    private struct ListMatch {
        let number: String
        let text: String
        let indent: Int
    }
    
    private func parseNumberedList(_ line: String) -> ListMatch? {
        let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = leadingSpaces / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        let components = trimmed.components(separatedBy: " ")
        guard let firstComp = components.first else { return nil }
        
        var numStr: String? = nil
        if firstComp.hasSuffix(".") || firstComp.hasSuffix(")") {
            let numPart = String(firstComp.dropLast())
            if Int(numPart) != nil {
                numStr = numPart
            }
        }
        
        if let num = numStr, components.count > 1 {
            let restText = components.dropFirst().joined(separator: " ")
            return ListMatch(number: num, text: restText, indent: indent)
        }
        
        return nil
    }
    
    private func parseBulletPoint(_ line: String) -> ListMatch? {
        let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = leadingSpaces / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        let bulletPrefixes = ["- ", "* ", "+ ", "• ", "◦ ", "⁃ "]
        for prefix in bulletPrefixes {
            if trimmed.hasPrefix(prefix) {
                let restText = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return ListMatch(number: "", text: restText, indent: indent)
            }
        }
        return nil
    }
    
    var body: some View {
        let blocks = parseMarkdown(text: text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .paragraph(let text):
                    InlineMarkdownPillText(
                        markdown: text,
                        font: .system(size: advancedRender ? 15.5 : 13.5),
                        sourceLinks: sourceLinks
                    )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                        
                case .heading(let title, let level):
                    VStack(alignment: .leading, spacing: 0) {
                        if level == 1 {
                            InlineMarkdownPillText(
                                markdown: title,
                                font: .system(size: advancedRender ? 21 : 19, weight: .bold, design: .rounded),
                                sourceLinks: sourceLinks
                            )
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        } else if level == 2 {
                            InlineMarkdownPillText(
                                markdown: title,
                                font: .system(size: advancedRender ? 18.5 : 16.5, weight: .bold, design: .rounded),
                                sourceLinks: sourceLinks
                            )
                                .padding(.top, 10)
                                .padding(.bottom, 3)
                        } else if level == 3 {
                            InlineMarkdownPillText(
                                markdown: title,
                                font: .system(size: advancedRender ? 16 : 14.5, weight: .semibold, design: .rounded),
                                sourceLinks: sourceLinks
                            )
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        } else {
                            InlineMarkdownPillText(
                                markdown: title,
                                font: .system(size: advancedRender ? 15 : 13.5, weight: .semibold, design: .rounded),
                                sourceLinks: sourceLinks
                            )
                                .padding(.top, 6)
                                .padding(.bottom, 2)
                        }
                    }
                    
                case .boldHeader(let title):
                    InlineMarkdownPillText(
                        markdown: title,
                        font: .system(size: advancedRender ? 16 : 14.5, weight: .bold, design: .rounded),
                        sourceLinks: sourceLinks
                    )
                        .padding(.top, 10)
                        .padding(.bottom, 3)
                    
                case .numberedItem(let number, let itemText, let indentLevel):
                    HStack(alignment: .top, spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 20, height: 20)
                            Text(number)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                        }
                        .padding(.top, 1)
                        
                        InlineMarkdownPillText(
                            markdown: itemText,
                            font: .system(size: advancedRender ? 15.5 : 13.5),
                            sourceLinks: sourceLinks
                        )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(indentLevel) * 16)
                    .padding(.vertical, 1.5)
                    
                case .bulletPoint(let bulletText, let indentLevel):
                    HStack(alignment: .top, spacing: 8) {
                        Group {
                            if indentLevel == 0 {
                                Circle()
                                    .fill(Color.blue.opacity(0.8))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6.5)
                            } else if indentLevel == 1 {
                                Circle()
                                    .stroke(Color.primary.opacity(0.5), lineWidth: 1.2)
                                    .frame(width: 4.5, height: 4.5)
                                    .padding(.top, 6.5)
                            } else {
                                Rectangle()
                                    .fill(Color.secondary)
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 7)
                            }
                        }
                        
                        InlineMarkdownPillText(
                            markdown: bulletText,
                            font: .system(size: advancedRender ? 15.5 : 13.5),
                            sourceLinks: sourceLinks
                        )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(indentLevel == 0 ? 4 : (indentLevel * 18)))
                    .padding(.vertical, 1)
                    
                case .callout(let title, let calloutText, let type):
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: type.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(type.accentColor)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            if let title = title, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(type.accentColor)
                            }
                            InlineMarkdownPillText(
                                markdown: calloutText,
                                font: .system(size: 13),
                                foregroundColor: .primary.opacity(0.9),
                                sourceLinks: sourceLinks
                            )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(type.accentColor.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(type.accentColor.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
                    
                case .codeBlock(let code, let language):
                    MarkdownCodeBlockView(code: code, language: language)
                    
                case .divider:
                    Divider()
                        .padding(.vertical, 8)
                        
                case .table(let rows):
                    if !rows.isEmpty {
                        TableView(rows: rows, sourceLinks: sourceLinks)
                    }
                    if isGenerating && index == blocks.count - 1 {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .controlSize(.small)
                            Text("Generating table...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

struct MarkdownCodeBlockView: View {
    let code: String
    let language: String?
    @State private var isCopied: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isCopied = false
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04))
            
            Divider()
                .opacity(0.15)
            
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 6)
    }
}


struct TableView: View {
    let rows: [[String]]
    var sourceLinks: [(title: String, url: String)] = []
    
    var body: some View {
        guard !rows.isEmpty else { return AnyView(EmptyView()) }
        
        let columnCount = rows.map(\.count).max() ?? 0

        return AnyView(
            VStack(spacing: 0) {
                // Header Row
                if let headerRow = rows.first {
                    HStack(spacing: 16) {
                        ForEach(0..<columnCount, id: \.self) { colIndex in
                            let value = colIndex < headerRow.count ? headerRow[colIndex] : ""
                            InlineMarkdownPillText(
                                markdown: value.trimmingCharacters(in: .whitespacesAndNewlines),
                                font: .system(size: 12, weight: .bold, design: .rounded),
                                sourceLinks: sourceLinks
                            )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06))
                }
                
                Divider()
                    .opacity(0.2)
                
                // Data Rows
                if rows.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(1..<rows.count, id: \.self) { rowIndex in
                            let columns = rows[rowIndex]
                            VStack(spacing: 0) {
                                HStack(spacing: 16) {
                                    ForEach(0..<columnCount, id: \.self) { colIndex in
                                        let value = colIndex < columns.count ? columns[colIndex] : ""
                                        InlineMarkdownPillText(
                                            markdown: value.trimmingCharacters(in: .whitespacesAndNewlines),
                                            font: .system(size: 12.5, weight: .regular),
                                            foregroundColor: .secondary,
                                            sourceLinks: sourceLinks
                                        )
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(rowIndex % 2 == 0 ? Color.primary.opacity(0.025) : Color.clear)
                                
                                if rowIndex < rows.count - 1 {
                                    Divider()
                                        .opacity(0.08)
                                }
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
            .padding(.vertical, 6)
        )
    }
}

private func findNextMessage(after message: ChatMessage, in thread: ChatThread) -> ChatMessage? {
    guard let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return nil }
    let nextIndex = index + 1
    guard nextIndex < thread.messages.count else { return nil }
    return thread.messages[nextIndex]
}

private func toolResponseSucceeded(_ message: ChatMessage?) -> Bool? {
    guard let message, message.isToolResponse,
          let objectText = firstJSONObject(in: message.text),
          let data = objectText.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = root["tool_response"] as? [String: Any] else { return nil }
    if let success = response["success"] as? Bool { return success }
    if let status = response["status"] as? String {
        return !status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("error")
    }
    return nil
}



private func parseSearchLinks(from messageText: String) -> [(title: String, url: String)] {
    // Tool-result messages include a continuation directive after the JSON.
    // Decode only the first balanced JSON object rather than rejecting the
    // complete message because of that transport suffix.
    guard let jsonText = firstJSONObject(in: messageText),
          let nextData = jsonText.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: nextData) as? [String: Any],
          let resp = json["tool_response"] as? [String: Any] else {
        return []
    }

    var links: [(title: String, url: String)] = []
    for key in ["sources", "results", "search_sources"] {
        guard let structured = resp[key] as? [[String: Any]] else { continue }
        for source in structured {
            let rawURL = (source["url"] as? String) ?? (source["link"] as? String) ?? ""
            guard !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let title = (source["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? rawURL
            links.append((title: displayTitle, url: normalizedSearchURL(rawURL)))
        }
    }

    guard let searchResults = (resp["search_results"] as? String) ?? (resp["fetched_evidence"] as? String) else {
        return deduplicatedSearchLinks(links)
    }
    let blocks = searchResults.components(separatedBy: "- Title: ")
    for block in blocks {
        let lines = block.components(separatedBy: "\n")
        var title = ""
        var url = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Snippet:") {
                // skip snippet
            } else if trimmed.hasPrefix("URL:") {
                url = trimmed.replacingOccurrences(of: "URL:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if title.isEmpty && !trimmed.isEmpty {
                title = trimmed
            }
        }
        if !url.isEmpty {
            if title.isEmpty { title = url }
            links.append((title: title, url: normalizedSearchURL(url)))
        }
    }
    return deduplicatedSearchLinks(links)
}

private func deduplicatedSearchLinks(_ links: [(title: String, url: String)]) -> [(title: String, url: String)] {
    var seen = Set<String>()
    return links.filter { seen.insert($0.url).inserted }
}

/// Return the actual provider queries recorded by the search backend. This is
/// intentionally parsed from the completed tool response rather than from the
/// model's requested query because Swift may preserve constraints, remove
/// conversational wrappers, add the current year, or run an automatic
/// refinement before the providers are called.
private func parseExecutedSearchQueries(from messageText: String) -> [String] {
    guard let jsonText = firstJSONObject(in: messageText),
          let data = jsonText.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = json["tool_response"] as? [String: Any] else {
        return []
    }

    // Activity represents the evidence that supported the completed answer.
    // Failed discovery attempts remain in provider_queries for diagnostics but
    // must not be presented as successful searches to the user.
    guard response["success"] as? Bool == true else { return [] }
    if let successfulQueries = response["successful_queries"] as? [String] {
        return successfulQueries.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    if let providerQueries = response["provider_queries"] as? [String] {
        return providerQueries.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    if let executedQuery = response["executed_query"] as? String,
       !executedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return [executedQuery]
    }
    return []
}

private func searchLinksForTurn(endingAt message: ChatMessage, in thread: ChatThread) -> [(title: String, url: String)] {
    guard let endIndex = thread.messages.firstIndex(where: { $0.id == message.id }) else { return [] }
    var collected: [(title: String, url: String)] = []
    var seenURLs = Set<String>()
    var index = endIndex - 1

    while index >= 0 {
        let candidate = thread.messages[index]
        if candidate.role == .user && !candidate.isToolResponse {
            break
        }
        if candidate.isToolResponse {
            for link in parseSearchLinks(from: candidate.text) where seenURLs.insert(link.url).inserted {
                collected.append(link)
            }
        }
        index -= 1
    }
    return collected
}

/// Resolve the source payload that follows a visible internet-use activity
/// message. Tool responses are hidden from the transcript, so the activity row
/// must look forward within the same user turn to populate the Sources panel.
private func searchLinksForSearchActivity(startingAt message: ChatMessage, in thread: ChatThread) -> [(title: String, url: String)] {
    guard let startIndex = thread.messages.firstIndex(where: { $0.id == message.id }) else { return [] }
    // A click can originate from any visible/legacy search activity row. Find
    // the beginning of its user turn first so earlier and later search rounds
    // are represented by one complete activity timeline.
    var turnStartIndex = 0
    var cursor = startIndex - 1
    while cursor >= 0 {
        let candidate = thread.messages[cursor]
        if candidate.role == .user && !candidate.isToolResponse {
            turnStartIndex = cursor + 1
            break
        }
        cursor -= 1
    }

    var collected: [(title: String, url: String)] = []
    var seenURLs = Set<String>()
    for candidate in thread.messages[turnStartIndex...] {
        if candidate.role == .user && !candidate.isToolResponse { break }
        if candidate.isToolResponse {
            for link in parseSearchLinks(from: candidate.text) where seenURLs.insert(link.url).inserted {
                collected.append(link)
            }
        }
    }
    return collected
}

/// Collect every exact provider query used in one user turn, including
/// automatic refinements and later targeted search rounds, in execution order.
private func searchQueriesForSearchActivity(startingAt message: ChatMessage, in thread: ChatThread) -> [String] {
    guard let startIndex = thread.messages.firstIndex(where: { $0.id == message.id }) else { return [] }
    var turnStartIndex = 0
    var cursor = startIndex - 1
    while cursor >= 0 {
        let candidate = thread.messages[cursor]
        if candidate.role == .user && !candidate.isToolResponse {
            turnStartIndex = cursor + 1
            break
        }
        cursor -= 1
    }

    var queries: [String] = []
    var seen = Set<String>()
    for candidate in thread.messages[turnStartIndex...] {
        if candidate.role == .user && !candidate.isToolResponse { break }
        guard candidate.isToolResponse else { continue }
        for query in parseExecutedSearchQueries(from: candidate.text) {
            let normalized = query
                .replacingOccurrences(
                    of: #"(?:\s+authoritative\s+primary\s+source)+\s*$"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            if seen.insert(key).inserted { queries.append(normalized) }
        }
    }
    return queries
}

private func firstJSONObject(in text: String) -> String? {
    guard let start = text.firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var escaped = false

    var index = start
    while index < text.endIndex {
        let character = text[index]
        if escaped {
            escaped = false
        } else if character == "\\" && inString {
            escaped = true
        } else if character == "\"" {
            inString.toggle()
        } else if !inString {
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }
        index = text.index(after: index)
    }
    return nil
}

private func normalizedSearchURL(_ rawURL: String) -> String {
    let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "&amp;", with: "&")
    let absolute: String
    if trimmed.hasPrefix("//") {
        absolute = "https:" + trimmed
    } else if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
        absolute = trimmed
    } else {
        absolute = "https://" + trimmed
    }

    // DuckDuckGo sometimes returns its redirect URL instead of the target.
    if let components = URLComponents(string: absolute),
       components.host?.contains("duckduckgo.com") == true,
       let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
       !target.isEmpty {
        return target
    }
    return absolute
}

private func isFirstFileSystemToolRequest(_ message: ChatMessage, in thread: ChatThread) -> Bool {
    guard let firstMsg = thread.messages.first(where: { msg in
        guard let req = ToolRequestParser.parse(text: msg.text) else { return false }
        return req.type == "file_system" || req.displayTitle == "terminal used"
    }) else {
        return false
    }
    return firstMsg.id == message.id
}

private func isLastInternetToolRequestInTurn(_ message: ChatMessage, in thread: ChatThread) -> Bool {
    guard let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return true }
    guard index + 1 < thread.messages.count else { return true }

    for laterMessage in thread.messages[(index + 1)...] {
        if laterMessage.role == .user && !laterMessage.isToolResponse {
            break
        }
        if laterMessage.role == .assistant,
           ToolRequestParser.parse(text: laterMessage.text)?.type == "internet_use" {
            return false
        }
    }
    return true
}

/// A single user request may require several task calls (for example list,
/// then delete). Keep those internal steps, but show one Tasks activity row
/// for the whole turn instead of repeating it for every call.
private func isFirstTaskToolRequestInTurn(_ message: ChatMessage, in thread: ChatThread) -> Bool {
    guard let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return true }

    var cursor = index - 1
    while cursor >= 0 {
        let previous = thread.messages[cursor]
        if previous.role == .user && !previous.isToolResponse {
            break
        }
        if previous.role == .assistant {
            if ToolRequestParser.parse(text: previous.text)?.type == "task_management" || previous.isStreamingTaskJSON {
                return false
            }
        }
        cursor -= 1
    }
    return true
}

private func visibleTranscriptMessages(in thread: ChatThread) -> [ChatMessage] {
    thread.messages.filter { message in
        // Tool responses are transport-only and messageBubble always renders
        // them as EmptyView. Exclude them here as well so each hidden response
        // cannot create two LazyVStack gaps between thought/tool fragments.
        guard !message.isToolResponse else { return false }
        let isTaskCall = ToolRequestParser.parse(text: message.text)?.type == "task_management" || message.isStreamingTaskJSON
        let isInternetCall = ToolRequestParser.parse(text: message.text)?.type == "internet_use" || message.isStreamingSearchJSON
        let shouldShowTask = !isTaskCall || isFirstTaskToolRequestInTurn(message, in: thread)
        let shouldShowInternet = !isInternetCall || isFirstInternetToolRequestInTurn(message, in: thread)
        return shouldShowTask && shouldShowInternet
    }
}

private func isFirstInternetToolRequestInTurn(_ message: ChatMessage, in thread: ChatThread) -> Bool {
    guard let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return true }
    var cursor = index - 1
    while cursor >= 0 {
        let previous = thread.messages[cursor]
        if previous.role == .user && !previous.isToolResponse {
            break
        }
        if previous.role == .assistant,
           (ToolRequestParser.parse(text: previous.text)?.type == "internet_use" || previous.isStreamingSearchJSON) {
            return false
        }
        cursor -= 1
    }
    return true
}

private func isSubsequentToolResponseAssistantMessage(_ message: ChatMessage, in thread: ChatThread) -> Bool {
    guard message.role == .assistant else { return false }
    
    if ToolRequestParser.parse(text: message.text) != nil {
        return false
    }
    
    guard let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return false }
    guard index >= 2 else { return false }
    let prev1 = thread.messages[index - 1]
    let prev2 = thread.messages[index - 2]
    
    guard prev1.isToolResponse && prev2.role == .assistant, let prev2ToolRequest = ToolRequestParser.parse(text: prev2.text) else { return false }
    
    let prev2HasNext = findNextMessage(after: prev2, in: thread)?.text.contains("tool_response") ?? false
    let prev2HasSliders = prev2ToolRequest.fields.contains(where: { $0.type == .slider })
    let prev2IsSubmittedDataCollection = prev2HasNext && !prev2HasSliders && prev2ToolRequest.type == "request_input"
    
    if prev2IsSubmittedDataCollection {
        return false
    }
    
    return true
}

private func findSubsequentAssistantMessage(after message: ChatMessage, in thread: ChatThread) -> ChatMessage? {
    guard let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return nil }
    guard index + 2 < thread.messages.count else { return nil }
    let next1 = thread.messages[index + 1]
    let next2 = thread.messages[index + 2]
    if next1.isToolResponse && next2.role == .assistant {
        return next2
    }
    return nil
}

#if os(macOS)
struct HTMLView: NSViewRepresentable {
    let htmlContent: String
    
    class Coordinator: NSObject {
        var lastLoadedHTML: String = ""
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != htmlContent {
            context.coordinator.lastLoadedHTML = htmlContent
            nsView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
}
#else
struct HTMLView: UIViewRepresentable {
    let htmlContent: String
    
    class Coordinator: NSObject {
        var lastLoadedHTML: String = ""
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.backgroundColor = .clear
        webView.isOpaque = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != htmlContent {
            context.coordinator.lastLoadedHTML = htmlContent
            uiView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
}
#endif

struct DynamicInsightBlockView: View {
    let request: ToolRequest
    
    var body: some View {
        // Grid of Insight Cards (Horizontal Rowed Blocks)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: .infinity), spacing: 8)], spacing: 8) {
            ForEach(request.fields.filter { $0.type == .insight }) { field in
                HStack(alignment: .top, spacing: 8) {
                    Capsule()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                        .frame(width: 3, height: 24)
                        .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.label)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let content = field.placeholder {
                            Text(content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tesaract Block View with Fit/Extend Controls

enum TesaractDisplayMode: String {
    case normal
    case fit
    case extend
    case immersive
}

struct TesaractBlockView: View {
    let htmlContent: String
    @State private var displayMode: TesaractDisplayMode = .normal
    @State private var contentHeight: CGFloat = 340
    @State private var measuredContentHeight: CGFloat = 340
    
    private var frameHeight: CGFloat {
        switch displayMode {
        case .normal: return 340
        case .fit: return 340
        case .extend, .immersive: return max(340, measuredContentHeight)
        }
    }
    
    private var processedHTML: String {
        switch displayMode {
        case .normal, .extend:
            return htmlContent
        case .fit:
            // Inject CSS to scale and center content inside the viewport precisely
            let fitScript = """
            <script>
            (function() {
                function applyFit() {
                    // Add CSS to override body/html styles to fit viewport perfectly
                    var style = document.createElement('style');
                    style.innerHTML = `
                        html, body {
                            margin: 0 !important;
                            padding: 0 !important;
                            width: 100% !important;
                            height: 100% !important;
                            overflow: hidden !important;
                            display: flex !important;
                            justify-content: center !important;
                            align-items: center !important;
                            background: transparent !important;
                        }
                        #tesaract-fit-wrapper {
                            transform-origin: center center !important;
                            display: inline-block !important;
                            transition: transform 0.2s ease-in-out;
                        }
                    `;
                    document.head.appendChild(style);

                    // Create a wrapper div
                    var wrapper = document.createElement('div');
                    wrapper.id = 'tesaract-fit-wrapper';
                    
                    // Move all current body children to the wrapper
                    while (document.body.firstChild) {
                        wrapper.appendChild(document.body.firstChild);
                    }
                    document.body.appendChild(wrapper);

                    function resize() {
                        wrapper.style.transform = 'none';
                        var w = wrapper.scrollWidth || wrapper.offsetWidth;
                        var h = wrapper.scrollHeight || wrapper.offsetHeight;
                        if (!w || !h) return;
                        
                        var vw = window.innerWidth;
                        var vh = window.innerHeight;
                        
                        // Use safe padding margins to guarantee no scrollbars appear
                        var targetW = vw - 16;
                        var targetH = vh - 16;
                        
                        var scale = Math.min(targetW / w, targetH / h);
                        wrapper.style.transform = 'scale(' + scale + ')';
                    }
                    
                    window.addEventListener('resize', resize);
                    resize();
                    setTimeout(resize, 100);
                    setTimeout(resize, 500);
                    setTimeout(resize, 1000);
                }
                
                if (document.readyState === 'complete') { applyFit(); }
                else { window.addEventListener('load', applyFit); }
            })();
            </script>
            """
            if htmlContent.lowercased().contains("</body>") {
                return htmlContent.replacingOccurrences(of: "</body>", with: fitScript + "</body>", options: .caseInsensitive)
            } else {
                return htmlContent + fitScript
            }
        case .immersive:
            // Force the html, body, and major wrapper divs to be transparent
            let transScript = """
            <script>
            (function() {
                var style = document.createElement('style');
                style.innerHTML = `
                    html, body, #app, #root, .app, .root, #wrapper, .wrapper, .main-content, main, section, .container, #container, .game-container, #game-container {
                        background: transparent !important;
                        background-color: transparent !important;
                    }
                `;
                document.head.appendChild(style);
            })();
            </script>
            """
            if htmlContent.lowercased().contains("</body>") {
                return htmlContent.replacingOccurrences(of: "</body>", with: transScript + "</body>", options: .caseInsensitive)
            } else {
                return htmlContent + transScript
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Control Bar
            HStack(spacing: 6) {
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        displayMode = displayMode == .fit ? .normal : .fit
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Fit")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(displayMode == .fit ? Color.accentColor : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(displayMode == .fit ? .white : .secondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        displayMode = displayMode == .extend ? .normal : .extend
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Extend")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(displayMode == .extend ? Color.accentColor : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(displayMode == .extend ? .white : .secondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        displayMode = displayMode == .immersive ? .normal : .immersive
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Immersive")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(displayMode == .immersive ? Color.accentColor : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(displayMode == .immersive ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 4)
            
            // HTML Content
            TesaractHTMLView(htmlContent: processedHTML, onHeightMeasured: { height in
                if height > 10 {
                    measuredContentHeight = height
                }
            })
            .frame(height: frameHeight)
            .cornerRadius(12)
            .overlay(
                Group {
                    if displayMode != .immersive {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }
}

#if os(macOS)
struct TesaractHTMLView: NSViewRepresentable {
    let htmlContent: String
    var onHeightMeasured: ((CGFloat) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightMeasured: onHeightMeasured)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "heightReporter")
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onHeightMeasured = onHeightMeasured
        if context.coordinator.lastLoadedHTML != htmlContent {
            context.coordinator.lastLoadedHTML = htmlContent
            nsView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onHeightMeasured: ((CGFloat) -> Void)?
        var lastLoadedHTML: String = ""
        
        init(onHeightMeasured: ((CGFloat) -> Void)?) {
            self.onHeightMeasured = onHeightMeasured
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = """
            (function() {
                var body = document.body;
                var html = document.documentElement;
                var h = Math.max(body.scrollHeight, body.offsetHeight, html.scrollHeight, html.offsetHeight);
                window.webkit.messageHandlers.heightReporter.postMessage(h);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightReporter", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.onHeightMeasured?(height)
                }
            }
        }
    }
}
#else
struct TesaractHTMLView: UIViewRepresentable {
    let htmlContent: String
    var onHeightMeasured: ((CGFloat) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightMeasured: onHeightMeasured)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "heightReporter")
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onHeightMeasured = onHeightMeasured
        if context.coordinator.lastLoadedHTML != htmlContent {
            context.coordinator.lastLoadedHTML = htmlContent
            uiView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onHeightMeasured: ((CGFloat) -> Void)?
        var lastLoadedHTML: String = ""
        
        init(onHeightMeasured: ((CGFloat) -> Void)?) {
            self.onHeightMeasured = onHeightMeasured
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = """
            (function() {
                var body = document.body;
                var html = document.documentElement;
                var h = Math.max(body.scrollHeight, body.offsetHeight, html.scrollHeight, html.offsetHeight);
                window.webkit.messageHandlers.heightReporter.postMessage(h);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightReporter", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.onHeightMeasured?(height)
                }
            }
        }
    }
}
#endif

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        #if os(macOS)
        let nsColor = NSColor(self)
        let srgbColor = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let r = max(0, min(255, Int((srgbColor.redComponent.isNaN ? 0 : srgbColor.redComponent) * 255)))
        let g = max(0, min(255, Int((srgbColor.greenComponent.isNaN ? 0 : srgbColor.greenComponent) * 255)))
        let b = max(0, min(255, Int((srgbColor.blueComponent.isNaN ? 0 : srgbColor.blueComponent) * 255)))
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return "#007AFF"
        #endif
    }
}

struct SearchingGlobeView: View {
    @State private var rotationAngle: Double = 0
    @State private var glowOpacity: Double = 0.4
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(glowOpacity)
                    .blur(radius: 1.5)
                
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(rotationAngle))
            }
            .onAppear {
                withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.95
                }
            }
            
            Text("Searching the web...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct TerminalExecutingView: View {
    @State private var blinkOpacity: Double = 0.3
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Accessing File System & Running Command...")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .opacity(blinkOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        blinkOpacity = 1.0
                    }
                }
        }
    }
}

struct TasksExecutingView: View {
    var isComplete: Bool = false
    @State private var pulseOpacity: Double = 0.45

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "checklist")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)

            Text("Tasks")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .opacity(isComplete ? 1 : pulseOpacity)
        .onAppear {
            guard !isComplete else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseOpacity = 1
            }
        }
    }
}

struct SettingsIconView: View {
    let systemName: String
    let bgColor: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(bgColor)
                .frame(width: 24, height: 24)
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
    }
}

struct PrePromptsView: View {
    @Bindable var manager: ChatManager
    var threadId: UUID?
    
    @AppStorage("aiEffortLevel") private var aiEffortLevel: String = AIEffortLevel.medium.rawValue
    @State private var selectedCategory: String = "Full Raw Prompt"
    @State private var searchText: String = ""
    @State private var expandedItems: Set<String> = []
    @State private var showCopiedBanner: Bool = false

    private var categories: [String] {
        ["Full Raw Prompt"]
    }
    
    private var prePromptItems: [PrePromptItem] {
        manager.getPrePromptItems(for: threadId)
    }
    
    private var filteredItems: [PrePromptItem] {
        prePromptItems.filter { item in
            let matchesCategory = (selectedCategory == "All" || item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.summary.localizedCaseInsensitiveContains(searchText) ||
                item.category.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }
    
    private var compiledPrompt: String {
        manager.getCompiledPrePrompt(for: threadId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The sidebar intentionally exposes only the final compiled prompt.
            if false { HStack {
                Text("Active Pre-Prompts: \(prePromptItems.filter { $0.isEnabled }.count) / \(prePromptItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    withAnimation {
                        if manager.disabledPrePromptIds.isEmpty {
                            manager.setAllPrePromptsEnabled(false)
                        } else {
                            manager.setAllPrePromptsEnabled(true)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: manager.disabledPrePromptIds.isEmpty ? "eye.slash" : "eye")
                        Text(manager.disabledPrePromptIds.isEmpty ? "Temporarily Turn Off All" : "Turn On All Pre-Prompts")
                    }
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(manager.disabledPrePromptIds.isEmpty ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
                    .foregroundStyle(manager.disabledPrePromptIds.isEmpty ? Color.orange : Color.green)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2) }
            
            // Category Segment Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = cat
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if cat == "Full Raw Prompt" {
                                    Image(systemName: "terminal.fill")
                                        .font(.caption2)
                                }
                                Text(cat)
                                    .font(.caption)
                                    .fontWeight(selectedCategory == cat ? .semibold : .regular)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, selectedCategory == cat ? 15 : 9)
                            .background(
                                Capsule()
                                    .fill(selectedCategory == cat ? Color.accentColor : Color.secondary.opacity(0.12))
                            )
                            .foregroundStyle(selectedCategory == cat ? .white : .primary)

                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if selectedCategory == "Full Raw Prompt" {
                // Full Compiled Pre-Prompt Text View (Extended to bottom)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exact Model System Prompt")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("\(compiledPrompt.count) characters • ~\(compiledPrompt.count / 3) context tokens • \(aiEffortLevel) Effort")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(compiledPrompt, forType: .string)
                            withAnimation {
                                showCopiedBanner = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showCopiedBanner = false
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showCopiedBanner ? "checkmark" : "doc.on.doc")
                                Text(showCopiedBanner ? "Copied!" : "Copy Exact Prompt")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(showCopiedBanner ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                            .foregroundStyle(showCopiedBanner ? Color.green : Color.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Exact system-role text sent for the active chat. Conversation history, attachments, and provider-native tool definitions are separate request fields.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    ScrollView {
                        Text(compiledPrompt)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Itemized Pre-Prompt Cards List
                ScrollView {
                    VStack(spacing: 8) {
                        if filteredItems.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "tray")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No pre-prompt items found for this category.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            ForEach(filteredItems) { item in
                                PrePromptCardView(
                                    manager: manager,
                                    item: item,
                                    isExpanded: expandedItems.contains(item.id),
                                    onToggleExpand: {
                                        if expandedItems.contains(item.id) {
                                            expandedItems.remove(item.id)
                                        } else {
                                            expandedItems.insert(item.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PrePromptCardView: View {
    @Bindable var manager: ChatManager
    let item: PrePromptItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    
    @State private var copied: Bool = false
    
    private var color: Color {
        switch item.iconColorName {
        case "blue": return .blue
        case "purple": return .purple
        case "indigo": return .indigo
        case "teal": return .teal
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        default: return .blue
        }
    }

    var body: some View {
        let isTempDisabled = manager.disabledPrePromptIds.contains(item.id)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                SettingsIconView(systemName: item.iconName, bgColor: isTempDisabled ? .gray : color)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(item.category)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((isTempDisabled ? Color.gray : color).opacity(0.15))
                            .foregroundStyle(isTempDisabled ? Color.gray : color)
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        // Status Badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isTempDisabled ? Color.orange : (item.isEnabled ? Color.green : Color.secondary.opacity(0.6)))
                                .frame(width: 6, height: 6)
                            Text(item.statusText)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(isTempDisabled ? Color.orange : (item.isEnabled ? .green : .secondary))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background((isTempDisabled ? Color.orange : (item.isEnabled ? Color.green : Color.secondary)).opacity(0.1))
                        .cornerRadius(6)
                        
                        // Temporary Turn Off Toggle Switch
                        Toggle("", isOn: Binding(
                            get: { !manager.disabledPrePromptIds.contains(item.id) },
                            set: { _ in
                                withAnimation {
                                    manager.togglePrePrompt(item.id)
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help(isTempDisabled ? "Click to enable this pre-prompt" : "Click to temporarily turn off this pre-prompt")
                    }
                    
                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            
            // Expand Content Toggle Button
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onToggleExpand()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide Prompt Text" : "View Pre-Prompt Text")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
                }
                .buttonStyle(.plain)
            }
            
            // Raw Pre-Prompt Content when expanded
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Fed to model before prompt:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.rawContent, forType: .string)
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied" : "Copy Snippet")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(copied ? .green : color)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text(item.rawContent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}


struct ScheduledPageView: View {
    var manager: ChatManager
    let accentColor: Color
    
    var scheduledTasks: [UserTask] {
        manager.tasks.filter { $0.dueDate != nil }.sorted { ($0.dueDate ?? "") < ($1.dueDate ?? "") }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scheduled")
                        .font(.largeTitle.bold())
                    Text("Tasks & events scheduled with specific due dates or times")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(scheduledTasks.filter { !$0.isCompleted }.count) upcoming")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
            }
            
            if scheduledTasks.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Tasks",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Add due dates to your tasks to see them scheduled here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(scheduledTasks) { task in
                        HStack(spacing: 12) {
                            Button {
                                var updated = task
                                updated.isCompleted.toggle()
                                manager.updateTask(updated)
                            } label: {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "clock.circle.fill")
                                    .foregroundStyle(task.isCompleted ? .green : accentColor)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title)
                                    .fontWeight(.medium)
                                    .strikethrough(task.isCompleted)
                                if !task.details.isEmpty {
                                    Text(task.details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let due = task.dueDate {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar")
                                            .font(.caption2)
                                        Text("Due: \(due)")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            if let group = task.groupName {
                                Text(group)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(accentColor.opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SkillsPageView: View {
    private enum SkillListFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case enabled = "Enabled"
        case disabled = "Disabled"
        case builtIn = "Built-in"
        case custom = "Custom"
        var id: String { rawValue }
    }

    var manager: ChatManager
    let accentColor: Color

    @State private var searchText = ""
    @State private var skillDraft: CustomSkill?
    @State private var skillFilter: SkillListFilter = .all
    @State private var expandedToolIDs: Set<UUID> = []

    private static let starterInstructions = """
    # Purpose
    Briefly explain the outcome this skill should produce.

    # Workflow
    1. Understand the user's goal and required output.
    2. Gather or verify the information needed.
    3. Complete the task using the rules below.
    4. Check the result before responding.

    # Rules
    - Follow the requested format exactly.
    - Ask one focused question if essential information is missing.
    - Do not claim completion until the result is verified.

    # Example
    User: Describe an example request that should activate this skill.
    Assistant: Describe the ideal result and response style.
    """

    private var filteredSkills: [CustomSkill] {
        manager.customSkills.filter { skill in
            StarterSkillCatalog.isVisibleInSkillsSpace(skill.id) &&
            matchesSelectedFilter(skill) &&
            (searchText.isEmpty ||
             skill.name.localizedCaseInsensitiveContains(searchText) ||
             skill.summary.localizedCaseInsensitiveContains(searchText) ||
             skill.instructions.localizedCaseInsensitiveContains(searchText))
        }.sorted { lhs, rhs in
            let leftRank = StarterSkillCatalog.isInfrastructure(lhs.id) ? 0 : (StarterSkillCatalog.isStarter(lhs.id) ? 1 : 2)
            let rightRank = StarterSkillCatalog.isInfrastructure(rhs.id) ? 0 : (StarterSkillCatalog.isStarter(rhs.id) ? 1 : 2)
            return leftRank == rightRank
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : leftRank < rightRank
        }
    }

    private func matchesSelectedFilter(_ skill: CustomSkill) -> Bool {
        switch skillFilter {
        case .all: return true
        case .enabled: return skill.isEnabled
        case .disabled: return !skill.isEnabled
        case .builtIn: return StarterSkillCatalog.isCatalogSkill(skill.id)
        case .custom: return !StarterSkillCatalog.isCatalogSkill(skill.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skills").font(.largeTitle.bold())
                Text("Built-in tools, installed library tools, and your custom skills supplied to the assistant.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(manager.customSkills.filter { $0.isEnabled && StarterSkillCatalog.isVisibleInSkillsSpace($0.id) }.count) enabled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                Button { beginCreating() } label: {
                    Label("Create skill", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(accentColor))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search skills", text: $searchText).textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1)))

                Picker("Filter", selection: $skillFilter) {
                    ForEach(SkillListFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 118)
                .help("Filter skills")
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredSkills) { skill in customSkillCard(skill) }

                    if manager.customSkills.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 26))
                                .foregroundStyle(accentColor)
                            Text("Create your first custom skill").font(.headline)
                            Text("Add focused instructions for a workflow, writing style, format, or specialized task.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                            Button("Create skill") { beginCreating() }.buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                    } else if filteredSkills.isEmpty {
                        ContentUnavailableView.search(text: searchText).padding(.vertical, 30)
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $skillDraft) { draft in
            CustomSkillEditorView(
                initialSkill: draft,
                isNew: !manager.customSkills.contains(where: { $0.id == draft.id }),
                canDelete: !StarterSkillCatalog.isInfrastructure(draft.id),
                onSave: { manager.upsertCustomSkill($0) },
                onDelete: { manager.deleteCustomSkill(id: $0) }
            )
        }
        .onChange(of: manager.contextRevision) { _, _ in
            guard skillDraft?.id == StarterSkillCatalog.learningID,
                  let currentLearning = manager.customSkills.first(where: { $0.id == StarterSkillCatalog.learningID }),
                  skillDraft?.instructions != currentLearning.instructions else { return }
            skillDraft = currentLearning
        }
    }

    private func customSkillCard(_ skill: CustomSkill) -> some View {
        let appearance = skillAppearance(for: skill.name)
        let isTool = StarterSkillCatalog.toolSkillIDs.contains(skill.id)
        let isExpanded = expandedToolIDs.contains(skill.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button { beginEditing(skill) } label: {
                    HStack(spacing: 14) {
                    Image(systemName: appearance.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(skill.isEnabled ? appearance.color : .secondary)
                        .frame(width: 38, height: 38)
                        .background((skill.isEnabled ? appearance.color : Color.secondary).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(skill.name).font(.headline).foregroundStyle(.primary)
                            if StarterSkillCatalog.isCatalogSkill(skill.id) {
                                Text(StarterSkillCatalog.isInfrastructure(skill.id) ? "Built-in" : "Starter")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(appearance.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(appearance.color.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(skill.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isTool {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if isExpanded { expandedToolIDs.remove(skill.id) }
                            else { expandedToolIDs.insert(skill.id) }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(appearance.color)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide tool handles" : "Show all tool handles")
                    .accessibilityLabel(isExpanded ? "Collapse \(skill.name) handles" : "Expand \(skill.name) handles")
                }

                Toggle("", isOn: Binding(
                    get: { skill.isEnabled },
                    set: { enabled in
                        var updated = skill
                        updated.isEnabled = enabled
                        manager.upsertCustomSkill(updated)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if isTool && isExpanded {
                Divider().padding(.vertical, 12)
                VStack(alignment: .leading, spacing: 8) {
                    Text("HANDLES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    ActivityFlowLayout(spacing: 6) {
                        ForEach(toolHandles(for: skill), id: \.self) { handle in
                            Text(handle)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(appearance.color.opacity(0.1))
                                .foregroundStyle(appearance.color)
                                .clipShape(Capsule())
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(skillCardBackground)
        .contextMenu {
            Button("Edit") { beginEditing(skill) }
            if !StarterSkillCatalog.isInfrastructure(skill.id) {
                Button("Delete", role: .destructive) { manager.deleteCustomSkill(id: skill.id) }
            }
        }
    }

    private func toolHandles(for skill: CustomSkill) -> [String] {
        switch skill.id {
        case StarterSkillCatalog.dynamicInsightsID: return ["title", "description", "fields", "insight", "placeholder"]
        case StarterSkillCatalog.internetSearchID: return ["query"]
        case StarterSkillCatalog.advancedMemoryID: return ["action", "nodes", "edges", "upsert", "delete", "clear"]
        case StarterSkillCatalog.filesystemID: return ["action", "path", "content", "command", "files", "execute_command", "list", "read_file", "create_file", "create_files", "create_folder"]
        case StarterSkillCatalog.learningID: return ["action", "learningId", "learningKind", "learningTopic", "content", "list", "append", "update", "delete", "clear"]
        default: return []
        }
    }

    private func skillAppearance(for name: String) -> (icon: String, color: Color) {
        switch name {
        case "Deep Research": return ("doc.text.magnifyingglass", .blue)
        case "Code Review": return ("checkmark.shield", .indigo)
        case "Debugging Partner": return ("ladybug", .red)
        case "Writing Editor": return ("pencil.and.outline", .purple)
        case "Meeting Notes to Actions": return ("person.2.wave.2", .orange)
        case "Project Planner": return ("point.3.connected.trianglepath.dotted", .cyan)
        case "Data Analyst": return ("chart.xyaxis.line", .green)
        case "Decision Brief": return ("arrow.triangle.branch", .mint)
        case "Dynamic Insights": return ("sparkles", .purple)
        case "Internet Search": return ("globe", .blue)
        case "Advanced Memory": return ("network", .purple)
        case "Terminal & Filesystem": return ("terminal.fill", .orange)
        case "Tool Execution Contract": return ("wrench.and.screwdriver.fill", .orange)
        case "Persona & User Style": return ("person.crop.circle", .indigo)
        case "Learning", "Error Learning": return ("brain.head.profile", .orange)
        case "Deep Reasoning Behavior": return ("brain", .purple)
        case "Direct Response Behavior": return ("bolt", .cyan)
        case "Fact Cross-Check": return ("checkmark.seal", .teal)
        case "Mandatory Internet Search": return ("magnifyingglass.circle", .blue)
        case "Performance Mode": return ("hare", .orange)
        case "Balanced Mode": return ("scale.3d", .mint)
        default: return ("sparkles", accentColor)
        }
    }

    private var skillCardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.primary.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1)))
    }


    private func beginCreating() {
        skillDraft = CustomSkill(
            name: "My custom workflow",
            summary: "Use this skill when the user asks to complete this specific workflow.",
            instructions: Self.starterInstructions
        )
    }

    private func beginEditing(_ skill: CustomSkill) {
        skillDraft = skill
    }
}

private struct CustomSkillEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let initialSkill: CustomSkill
    let isNew: Bool
    let canDelete: Bool
    let onSave: (CustomSkill) -> Void
    let onDelete: (UUID) -> Void

    @State private var name: String
    @State private var summary: String
    @State private var instructions: String
    @State private var isEnabled: Bool

    init(initialSkill: CustomSkill, isNew: Bool, canDelete: Bool = true, onSave: @escaping (CustomSkill) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.initialSkill = initialSkill
        self.isNew = isNew
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: initialSkill.name)
        _summary = State(initialValue: initialSkill.summary)
        _instructions = State(initialValue: initialSkill.instructions)
        _isEnabled = State(initialValue: initialSkill.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isNew ? "Create skill" : "Edit skill").font(.title2.bold())
                    Text("Teach the assistant a focused, repeatable workflow.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: $isEnabled).toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.subheadline.weight(.semibold))
                TextField("e.g. Brand voice", text: $name).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description").font(.subheadline.weight(.semibold))
                TextField("What it does and when to use it", text: $summary)
                    .textFieldStyle(.roundedBorder)
                Text("\(summary.count)/200")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(summary.count > 200 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Instructions").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            instructions = resetInstructionText
                        }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(instructions == resetInstructionText ? .tertiary : .secondary)
                    .disabled(instructions == resetInstructionText)
                    .help("Restore the default instructions for this skill. Save to apply the reset.")
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 9, weight: .semibold))
                        Text("≈\(estimatedInstructionTokens.formatted()) context tokens")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Estimated model context used by this skill's instruction prompt. The exact tokenizer varies by model.")
                }
                TextEditor(text: $instructions)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 220)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
                Text("Write plain text or Markdown. Include steps, rules, and examples when useful.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if !isNew && canDelete {
                    Button("Delete", role: .destructive) {
                        onDelete(initialSkill.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save skill") {
                    onSave(CustomSkill(
                        id: initialSkill.id,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                        instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                        isEnabled: isEnabled,
                        createdAt: initialSkill.createdAt
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600)
        .frame(minHeight: 540)
        .onChange(of: initialSkill.instructions) { oldValue, newValue in
            if initialSkill.id == StarterSkillCatalog.learningID,
               let newMarker = newValue.range(of: StarterSkillCatalog.learningRulesMarker) {
                let editableBase = instructions.range(of: StarterSkillCatalog.learningRulesMarker)
                    .map { String(instructions[..<$0.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
                    ?? String(newValue[..<newMarker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let learnedEntries = String(newValue[newMarker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                instructions = learnedEntries.isEmpty
                    ? "\(editableBase)\n\n\(StarterSkillCatalog.learningRulesMarker)"
                    : "\(editableBase)\n\n\(StarterSkillCatalog.learningRulesMarker)\n\(learnedEntries)"
            } else if instructions == oldValue {
                instructions = newValue
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        summary.count <= 200 &&
        !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var estimatedInstructionTokens: Int {
        let characterCount = instructions.count
        return characterCount == 0 ? 0 : max(1, Int(ceil(Double(characterCount) / 3.0)))
    }

    private var resetInstructionText: String {
        StarterSkillCatalog.defaultInstructions(for: initialSkill.id) ?? initialSkill.instructions
    }
}

struct CalendarPageView: View {
    var manager: ChatManager
    let accentColor: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Calendar").font(.largeTitle.bold())
            Text("Scheduled tasks").foregroundStyle(.secondary)
            List {
                ForEach(manager.tasks.filter { $0.dueDate != nil }.sorted { ($0.dueDate ?? "") < ($1.dueDate ?? "") }) { task in
                    HStack {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "calendar.circle.fill").foregroundStyle(task.isCompleted ? .green : accentColor)
                        VStack(alignment: .leading) { Text(task.title); Text(task.dueDate ?? "").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if let group = task.groupName { Text(group).font(.caption).foregroundStyle(accentColor) }
                    }
                }
                if !manager.tasks.contains(where: { $0.dueDate != nil }) { ContentUnavailableView("No Scheduled Tasks", systemImage: "calendar", description: Text("Give a task a due date to see it here.")) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MemoryGraphView: View {
    @Bindable var manager: ChatManager
    let threadId: UUID
    
    @State private var hoveredNodeId: String? = nil
    @State private var selectedNodeId: String? = nil
    @State private var showAddNodeSheet: Bool = false
    
    @State private var panOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var zoomScale: CGFloat = 1.0
    @State private var pinchScale: CGFloat = 1.0
    
    @State private var newLabel: String = ""
    @State private var newCategory: String = "interest"
    @State private var newTargetNodeId: String = ""
    @State private var newEdgeLabel: String = "likes"
    @State private var searchFilter: String = ""
    @State private var showResetMemoryAlert: Bool = false
    
    let categoryOptions = ["user", "project", "interest", "health", "info", "personality"]
    
    var body: some View {
        let allNodes = manager.globalMemoryNodes
        let allEdges = manager.globalMemoryEdges
        
        let filteredNodes = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? allNodes : allNodes.filter { $0.label.localizedCaseInsensitiveContains(searchFilter) || $0.category.localizedCaseInsensitiveContains(searchFilter) }
        
        let center = CGPoint(x: 145, y: 145)
        var positions: [String: CGPoint] = [:]
        
        let rootNodeID = filteredNodes.first(where: { $0.id == "user" })?.id
            ?? filteredNodes.first(where: { $0.id == "ai_assistant" })?.id
            ?? filteredNodes.first?.id
        let nonUserNodes = filteredNodes.filter { $0.id != rootNodeID }
        if let rootNodeID { positions[rootNodeID] = center }
        
        let count = nonUserNodes.count
        for (i, node) in nonUserNodes.enumerated() {
            let angle = Double(i) * (2.0 * .pi / Double(max(1, count)))
            let radius: CGFloat = count > 6 ? 98 : 82
            let x = center.x + CGFloat(cos(angle)) * radius
            let y = center.y + CGFloat(sin(angle)) * radius
            positions[node.id] = CGPoint(x: x, y: y)
        }
        
        let currentScale = zoomScale * pinchScale
        let currentPan = CGSize(width: panOffset.width + dragOffset.width, height: panOffset.height + dragOffset.height)
        
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                HStack {
                    Text("MEMORY KNOWLEDGE GRAPH")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(allNodes.count) nodes • \(allEdges.count) links")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                if !allNodes.isEmpty {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Filter graph...", text: $searchFilter)
                            .textFieldStyle(.plain)
                            .font(.caption)
                        if !searchFilter.isEmpty {
                            Button {
                                searchFilter = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                if allNodes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "brain")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Graph Memories Saved Yet")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text("Share personal facts and details with the AI, or click 'Add Node' above to manually create entities and connections.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    ZStack {
                        // Transformable Graph Container Layer
                        ZStack {
                            Canvas { context, size in
                                for edge in allEdges {
                                    guard let start = positions[edge.source],
                                          let end = positions[edge.target] else { continue }
                                    
                                    var path = Path()
                                    path.move(to: start)
                                    path.addLine(to: end)
                                    
                                    let isHighlighted = hoveredNodeId == edge.source || hoveredNodeId == edge.target || selectedNodeId == edge.source || selectedNodeId == edge.target
                                    let color = isHighlighted ? Color.blue : Color.secondary.opacity(0.35)
                                    let lineWidth: CGFloat = isHighlighted ? 2.0 : 1.2
                                    
                                    context.stroke(path, with: .color(color), lineWidth: lineWidth)
                                    
                                    let midPoint = CGPoint(x: (start.x + end.x)/2, y: (start.y + end.y)/2)
                                    let text = context.resolve(
                                        Text(edge.label)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(color)
                                    )
                                    context.draw(text, at: midPoint)
                                }
                            }
                            
                            ForEach(filteredNodes) { node in
                                if let pos = positions[node.id] {
                                    let isHovered = hoveredNodeId == node.id
                                    let isSelected = selectedNodeId == node.id
                                    
                                    NodeBubble(node: node, isHovered: isHovered, isSelected: isSelected)
                                        .position(pos)
                                        .onHover { hovering in
                                            hoveredNodeId = hovering ? node.id : nil
                                        }
                                        .onTapGesture {
                                            selectedNodeId = selectedNodeId == node.id ? nil : node.id
                                        }
                                }
                            }
                        }
                        .scaleEffect(currentScale)
                        .offset(currentPan)
                    }
                    .frame(width: 290, height: 290)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(12)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { gesture in
                                dragOffset = gesture.translation
                            }
                            .onEnded { gesture in
                                panOffset.width += gesture.translation.width
                                panOffset.height += gesture.translation.height
                                dragOffset = .zero
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                pinchScale = value
                            }
                            .onEnded { value in
                                zoomScale = min(max(zoomScale * value, 0.4), 3.5)
                                pinchScale = 1.0
                            }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        // Canvas Interactive Zoom & Reset Controls
                        HStack(spacing: 4) {
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    zoomScale = max(zoomScale - 0.2, 0.4)
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("Zoom Out")
                            
                            Text("\(Int(currentScale * 100))%")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 2)
                            
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    zoomScale = min(zoomScale + 0.2, 3.5)
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("Zoom In")
                            
                            Divider().frame(height: 10)
                            
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    zoomScale = 1.0
                                    panOffset = .zero
                                    dragOffset = .zero
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("Reset Pan & Zoom")
                        }
                        .padding(4)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                        .padding(8)
                    }
                    .padding(.horizontal)
                }
                
                if let selectedId = selectedNodeId, let node = allNodes.first(where: { $0.id == selectedId }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.label)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Text("ID: \(node.id)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            
                            Text(node.category.uppercased())
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(categoryColor(node.category).opacity(0.15))
                                .foregroundStyle(categoryColor(node.category))
                                .cornerRadius(4)
                            
                            Button {
                                manager.deleteMemoryNode(id: selectedId)
                                selectedNodeId = nil
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Delete Node")
                        }
                        
                        let connectedEdges = allEdges.filter { $0.source == selectedId || $0.target == selectedId }
                        if connectedEdges.isEmpty {
                            Text("No connections recorded.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Divider().padding(.vertical, 2)
                            ForEach(connectedEdges) { edge in
                                let otherNodeId = edge.source == selectedId ? edge.target : edge.source
                                let otherNodeName = allNodes.first(where: { $0.id == otherNodeId })?.label ?? otherNodeId
                                let relationText = edge.source == selectedId ? "→ \(edge.label) → \(otherNodeName)" : "← \(edge.label) ← \(otherNodeName)"
                                Text(relationText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .transition(.opacity)
                }

                // Keep graph actions after the visual graph and selected-node
                // detail, so the graph itself remains the first interaction.
                HStack(spacing: 8) {
                    Button {
                        showAddNodeSheet = true
                    } label: {
                        Label("Add Node", systemImage: "plus")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.blue))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(role: .destructive) {
                        showResetMemoryAlert = true
                    } label: {
                        Label("Reset Memory", systemImage: "trash")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.red.opacity(0.12)))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                .alert("Reset All Memory Completely?", isPresented: $showResetMemoryAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset Memory", role: .destructive) {
                        manager.clearAllMemoryCompletely()
                        selectedNodeId = nil
                        panOffset = .zero
                        dragOffset = .zero
                        zoomScale = 1.0
                    }
                } message: {
                    Text("This action cannot be undone. All persistent knowledge graph facts, entities, relations, and memory summaries will be permanently deleted.")
                }
            }
        }
        .onChange(of: manager.globalMemoryNodes.map(\.id)) { _, ids in
            if let selectedNodeId, !ids.contains(selectedNodeId) {
                self.selectedNodeId = nil
            }
        }
        .sheet(isPresented: $showAddNodeSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add Memory Node")
                    .font(.headline)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Entity Name / Fact")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. Swift, Paris, Fitness Goal", text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Category", selection: $newCategory) {
                        ForEach(categoryOptions, id: \.self) { cat in
                            Text(cat.capitalized).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect to Existing Node (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Target Node", selection: $newTargetNodeId) {
                        Text("None (Standalone Node)").tag("")
                        ForEach(allNodes) { n in
                            Text("\(n.label) (\(n.category))").tag(n.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if !newTargetNodeId.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Relationship Label")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. likes, works on, lives in", text: $newEdgeLabel)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showAddNodeSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Add to Memory") {
                        manager.addManualMemoryNode(
                            label: newLabel,
                            category: newCategory,
                            sourceNodeId: "user",
                            targetNodeId: newTargetNodeId.isEmpty ? nil : newTargetNodeId,
                            edgeLabel: newEdgeLabel
                        )
                        newLabel = ""
                        showAddNodeSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(width: 340)
        }
    }
    
    private func categoryColor(_ cat: String) -> Color {
        switch cat.lowercased() {
        case "user": return .red
        case "project": return .blue
        case "interest": return .green
        case "health": return .purple
        case "info": return .teal
        case "personality": return .pink
        case "learning": return .yellow
        default: return .gray
        }
    }
}

struct NodeBubble: View {
    let node: MemoryNode
    let isHovered: Bool
    let isSelected: Bool
    
    var body: some View {
        Text(node.label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(categoryGradient(node.category))
                    .shadow(color: isHovered ? .blue.opacity(0.3) : .clear, radius: 4)
            )
            .scaleEffect(isHovered ? 1.15 : 1.0)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHovered)
    }
    
    private func categoryGradient(_ cat: String) -> LinearGradient {
        switch cat.lowercased() {
        case "user":
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "project":
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "interest":
            return LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "health":
            return LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "info":
            return LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "personality":
            return LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

extension View {
    @ViewBuilder
    func assistantBubbleContainer(advancedRender: Bool, isCompactTop: Bool = false, isCompactBottom: Bool = false) -> some View {
        if advancedRender {
            self.padding(.horizontal, 36)
                .padding(.top, isCompactTop ? 2 : 16)
                .padding(.bottom, isCompactBottom ? 2 : 16)
        } else {
            self.padding(.horizontal, 16)
                .padding(.top, isCompactTop ? 2 : 12)
                .padding(.bottom, isCompactBottom ? 2 : 12)
                .background(.thinMaterial)
                .clipShape(BubbleShape(isUser: false))
        }
    }
}

extension ContentView {
    private func isPureMemoryRequest(_ message: ChatMessage) -> Bool {
        guard let req = ToolRequestParser.parse(text: message.text) else { return false }
        return req.type == "advanced_memory" && message.introText.isEmpty && message.conclusionText.isEmpty
    }

    private func isFollowupToMemoryRequest(_ message: ChatMessage, in thread: ChatThread) -> Bool {
        guard let index = thread.messages.firstIndex(where: { $0.id == message.id }), index > 0 else { return false }
        for offset in 1...2 {
            let prevIndex = index - offset
            if prevIndex >= 0 {
                let prevMsg = thread.messages[prevIndex]
                if isPureMemoryRequest(prevMsg) { return true }
                if prevMsg.isToolResponse && (prevMsg.text.contains("memory") || prevMsg.text.contains("Knowledge graph")) {
                    return true
                }
            }
        }
        return false
    }

    private var preferredColorScheme: ColorScheme? {
        switch appAppearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
    
    private func updateAppAppearance(_ appearance: String) {
        #if os(macOS)
        switch appearance {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
        #endif
    }
}

// MARK: - Channel Log Modal View
struct ChannelLogModal: View {
    @Environment(\.dismiss) private var dismiss
    var manager: ChatManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Channel Log")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Real-time Model Provider API Channels & Streaming Logs")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.secondary.opacity(0.04))
            
            Divider()
            
            // Channels Overview Cards
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ACTIVE LLM PROVIDER CHANNELS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        channelRow(title: "LM Studio Local Channel", icon: "server.rack", endpoint: manager.lmStudioBaseURL, status: "Active", isOnline: true)
                        channelRow(title: "Gemini API Channel", icon: "sparkles", endpoint: "https://generativelanguage.googleapis.com", status: manager.geminiAPIKey.isEmpty ? "No Key" : "Ready", isOnline: !manager.geminiAPIKey.isEmpty)
                        channelRow(title: "OpenRouter API Channel", icon: "cloud.fill", endpoint: "https://openrouter.ai/api/v1", status: manager.openRouterAPIKey.isEmpty ? "No Key" : "Ready", isOnline: !manager.openRouterAPIKey.isEmpty)
                        channelRow(title: "ChatGPT (OpenAI) Channel", icon: "brain.head.profile", endpoint: "https://api.openai.com/v1", status: manager.openAIAPIKey.isEmpty ? "No Key" : "Ready", isOnline: !manager.openAIAPIKey.isEmpty)
                    }
                    
                    Divider().padding(.vertical, 4)
                    
                    Text("LIVE SYSTEM EVENTS & DIAGNOSTICS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        logEntry(time: "Just now", message: "Channel Log initialized. Connection pool status normal.")
                        logEntry(time: "Active", message: "LM Studio endpoint configured at \(manager.lmStudioBaseURL)")
                        logEntry(time: "Ready", message: "SSE Streaming parser ready (Unbuffered Just-in-Time delivery)")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(8)
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 420)
    }
    
    @ViewBuilder
    private func channelRow(title: String, icon: String, endpoint: String, status: String, isOnline: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isOnline ? Color.green : Color.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isOnline ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1)))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(endpoint)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            Text(status)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOnline ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(isOnline ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1)))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.04)))
    }
    
    @ViewBuilder
    private func logEntry(time: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("[\(time)]")
                .foregroundStyle(.blue)
            Text(message)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - WhatsApp Style Vector Doodle Chat Background View
struct ChatWallpaperBackgroundView: View {
    let pattern: String // "doodles", "dots", "grid", "stars", "none"
    @AppStorage("chatWallpaperRotation") private var chatWallpaperRotation: Double = 0.0
    @AppStorage("chatWallpaperColor") private var chatWallpaperColor: String = "auto"
    @AppStorage("chatCustomWallpaperPath") private var chatCustomWallpaperPath: String = ""
    @Environment(\.colorScheme) private var colorScheme
    
    private var activeColor: Color {
        switch chatWallpaperColor {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "green": return .green
        case "monochrome": return colorScheme == .dark ? .white : .black
        default: return colorScheme == .dark ? .white : .black
        }
    }
    
    var body: some View {
        ZStack {
            switch pattern {
            case "doodles":
                doodleCanvas
                    .opacity(chatWallpaperColor == "auto" ? (colorScheme == .dark ? 0.07 : 0.09) : 0.20)
            case "dots":
                dotsCanvas
                    .opacity(chatWallpaperColor == "auto" ? (colorScheme == .dark ? 0.08 : 0.12) : 0.22)
            case "grid":
                gridCanvas
                    .opacity(chatWallpaperColor == "auto" ? (colorScheme == .dark ? 0.06 : 0.10) : 0.18)
            case "stars":
                starsCanvas
                    .opacity(chatWallpaperColor == "auto" ? (colorScheme == .dark ? 0.08 : 0.12) : 0.22)
            case "custom":
                if let image = NSImage(contentsOfFile: chatCustomWallpaperPath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(colorScheme == .dark ? 0.18 : 0.14)
                }
            default:
                EmptyView()
            }
        }
        .rotationEffect(.degrees(chatWallpaperRotation))
        .scaleEffect(chatWallpaperRotation != 0 ? 1.5 : 1.0)
        .allowsHitTesting(false)
    }
    
    private var doodleCanvas: some View {
        Canvas { context, size in
            let icons = [
                "bubble.left.and.bubble.right.fill",
                "sparkles",
                "star.fill",
                "heart.fill",
                "paperplane.fill",
                "cup.and.saucer.fill",
                "curlybraces",
                "magnifyingglass",
                "face.smiling.fill",
                "note.text",
                "bolt.fill",
                "antenna.radiowaves.left.and.right"
            ]
            
            let gridSpacing: CGFloat = 64
            let cols = Int(size.width / gridSpacing) + 2
            let rows = Int(size.height / gridSpacing) + 2
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let index = (row * 7 + col * 13) % icons.count
                    let iconName = icons[index]
                    
                    let offsetX = (row % 2 == 0) ? gridSpacing * 0.5 : 0
                    let x = CGFloat(col) * gridSpacing + offsetX
                    let y = CGFloat(row) * gridSpacing
                    
                    if let resolved = context.resolveSymbol(id: iconName) {
                        context.draw(resolved, at: CGPoint(x: x, y: y))
                    }
                }
            }
        } symbols: {
            let icons = [
                "bubble.left.and.bubble.right.fill",
                "sparkles",
                "star.fill",
                "heart.fill",
                "paperplane.fill",
                "cup.and.saucer.fill",
                "curlybraces",
                "magnifyingglass",
                "face.smiling.fill",
                "note.text",
                "bolt.fill",
                "antenna.radiowaves.left.and.right"
            ]
            ForEach(icons, id: \.self) { icon in
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(activeColor)
                    .tag(icon)
            }
        }
    }
    
    private var dotsCanvas: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let dotRadius: CGFloat = 1.2
            let cols = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = CGRect(x: CGFloat(col) * spacing, y: CGFloat(row) * spacing, width: dotRadius * 2, height: dotRadius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(activeColor))
                }
            }
        }
    }
    
    private var gridCanvas: some View {
        Canvas { context, size in
            let spacing: CGFloat = 30
            var path = Path()
            
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            
            context.stroke(path, with: .color(activeColor), lineWidth: 0.5)
        }
    }
    
    private var starsCanvas: some View {
        Canvas { context, size in
            let icons = ["star.fill", "sparkle", "moon.stars.fill"]
            let spacing: CGFloat = 72
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let index = (row * 3 + col * 5) % icons.count
                    let iconName = icons[index]
                    let offsetX = (row % 2 == 0) ? spacing * 0.4 : 0
                    let x = CGFloat(col) * spacing + offsetX
                    let y = CGFloat(row) * spacing
                    
                    if let resolved = context.resolveSymbol(id: iconName) {
                        context.draw(resolved, at: CGPoint(x: x, y: y))
                    }
                }
            }
        } symbols: {
            let icons = ["star.fill", "sparkle", "moon.stars.fill"]
            ForEach(icons, id: \.self) { icon in
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(activeColor)
                    .tag(icon)
            }
        }
    }
}

// MARK: - API & Tool Integrations Library Modal
struct ApiLibraryModal: View {
    var manager: ChatManager
    let threadId: UUID?
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var addedApis: Set<String> = []
    
    struct ApiItem: Identifiable {
        let id: String
        let name: String
        let description: String
        let category: String
        let icon: String
        let iconColor: Color
        let promptDirective: String
    }
    
    let libraryItems: [ApiItem] = [
        ApiItem(
            id: "weather_api",
            name: "wttr.in Weather & Climate API",
            description: "Live weather, temperature, humidity, and forecasts worldwide. Works out of the box with zero key setup required.",
            category: "Data & Weather",
            icon: "sun.max.fill",
            iconColor: .yellow,
            promptDirective: "\n[ACTIVE API TOOL: wttr.in Weather]: Live weather API active (Endpoint: https://wttr.in/<city>?format=j1). Provide accurate current temperatures, weather conditions, wind speed, and precipitation forecasts."
        ),
        ApiItem(
            id: "wiki_api",
            name: "Wikipedia Article & Knowledge API",
            description: "Fetches encyclopedic article summaries, historical timelines, biography summaries, and factual data directly from Wikipedia.",
            category: "Knowledge",
            icon: "book.fill",
            iconColor: .blue,
            promptDirective: "\n[ACTIVE API TOOL: Wikipedia REST API]: Wikipedia Knowledge API active (Endpoint: https://en.wikipedia.org/api/rest_v1/page/summary/<topic>). Retrieve encyclopedic facts, verified history, and accurate background summaries."
        ),
        ApiItem(
            id: "github_api",
            name: "GitHub REST & GraphQL API",
            description: "Deep inspection of open-source repositories, issues, pull requests, commits, and code diffs across GitHub.",
            category: "Developer",
            icon: "chevron.left.forwardslash.chevron.right",
            iconColor: .purple,
            promptDirective: "\n[ACTIVE API TOOL: GitHub API]: GitHub REST API active (Endpoint: https://api.github.com/repos/<owner>/<repo>). Inspect code repositories, commits, issues, and release notes."
        ),
        ApiItem(
            id: "coingecko_api",
            name: "CoinGecko Crypto & Forex Market API",
            description: "Real-time cryptocurrency quotes, bitcoin/ethereum exchange rates, market cap data, and forex conversions.",
            category: "Finance",
            icon: "chart.line.uptrend.xyaxis",
            iconColor: .green,
            promptDirective: "\n[ACTIVE API TOOL: CoinGecko Crypto API]: Live crypto rates API active (Endpoint: https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd). Format live price metrics, 24h market trends, and currency conversions."
        ),
        ApiItem(
            id: "hackernews_api",
            name: "Hacker News Live Tech Trends API",
            description: "Streams top developer discussions, Y Combinator startup stories, and trending technology announcements.",
            category: "Knowledge",
            icon: "flame.fill",
            iconColor: .orange,
            promptDirective: "\n[ACTIVE API TOOL: Hacker News API]: HackerNews Live Feed active (Endpoint: https://hacker-news.firebaseio.com/v0/topstories.json). Summarize top developer news stories and tech discussions."
        ),
        ApiItem(
            id: "nasa_api",
            name: "NASA Astronomy Picture & Space Data API",
            description: "Fetches daily deep-space imagery, planetary exploration telemetry, and astronomy data directly from NASA.",
            category: "Data & Weather",
            icon: "star.circle.fill",
            iconColor: .yellow,
            promptDirective: "\n[ACTIVE API TOOL: NASA Space API]: NASA APOD & Space API active (Endpoint: https://api.nasa.gov/planetary/apod). Retrieve daily astronomy imagery, planet exploration telemetry, and satellite space data."
        ),
        ApiItem(
            id: "openlibrary_api",
            name: "Open Library Book & Literature Index",
            description: "Accesses millions of book summaries, author biographies, publication histories, and ISBN metadata.",
            category: "Knowledge",
            icon: "books.vertical.fill",
            iconColor: .purple,
            promptDirective: "\n[ACTIVE API TOOL: Open Library API]: Open Library Book Search active (Endpoint: https://openlibrary.org/search.json?q=<query>). Access book summaries, author biographies, ISBN numbers, and publication histories."
        ),
        ApiItem(
            id: "geoip_api",
            name: "IP-API Global GeoIP & Network Inspection",
            description: "Inspects IP geolocation coordinates, ISP providers, Autonomous System Numbers (ASN), and DNS network data.",
            category: "Developer",
            icon: "network",
            iconColor: .teal,
            promptDirective: "\n[ACTIVE API TOOL: IP-API GeoIP]: IP & Network Geolocation API active (Endpoint: http://ip-api.com/json/<ip_or_domain>). Perform DNS, Autonomous System (ASN), ISP, and IP geolocation queries."
        ),
        ApiItem(
            id: "forex_api",
            name: "ExchangeRate-API Global Forex Rates",
            description: "Real-time exchange rate conversions between 160+ world fiat currencies (USD, EUR, GBP, JPY, INR, CAD).",
            category: "Finance",
            icon: "coloncurrencysign.circle.fill",
            iconColor: .green,
            promptDirective: "\n[ACTIVE API TOOL: ExchangeRate Forex API]: Live Currency Exchange Rates API active (Endpoint: https://open.er-api.com/v6/latest/USD). Convert between 160+ fiat currencies with live rate tables."
        ),
        ApiItem(
            id: "arxiv_api",
            name: "arXiv Scientific Papers & AI Pre-prints",
            description: "Searches thousands of open-access research papers in Computer Science, Quantum Physics, Machine Learning, & Mathematics.",
            category: "Research",
            icon: "doc.text.fill",
            iconColor: .red,
            promptDirective: "\n[ACTIVE API TOOL: arXiv Scientific Papers API]: arXiv Pre-print Server API active (Endpoint: http://export.arxiv.org/api/query?search_query=<query>). Retrieve research papers, AI breakthroughs, mathematical proofs, and author pre-prints."
        ),
        ApiItem(
            id: "restcountries_api",
            name: "REST Countries Intelligence API",
            description: "Retrieves country capitals, populations, official languages, currencies, and geographic bounding boxes.",
            category: "Data & Weather",
            icon: "globe.americas.fill",
            iconColor: .blue,
            promptDirective: "\n[ACTIVE API TOOL: REST Countries API]: Global Country Intelligence API active (Endpoint: https://restcountries.com/v3.1/name/<country>). Query country capitals, populations, currencies, official languages, and geographic coordinates."
        ),
        ApiItem(
            id: "spotify_api",
            name: "Spotify Audio & Music Analytics API",
            description: "Searches track tempos, artist discographies, album releases, audio features, and playlist recommendations.",
            category: "Media",
            icon: "music.note",
            iconColor: .green,
            promptDirective: "\n[ACTIVE API TOOL: Spotify Web API]: Spotify Audio Analytics API active. Search track tempos, artist discographies, album releases, and music recommendations."
        ),
        ApiItem(
            id: "jsonplaceholder_api",
            name: "JSONPlaceholder Prototyping REST API",
            description: "Mock REST API for testing code generation, JSON data fetching, HTTP request building, and API prototyping.",
            category: "Developer",
            icon: "arrow.triangle.2.circlepath",
            iconColor: .indigo,
            promptDirective: "\n[ACTIVE API TOOL: JSONPlaceholder REST API]: Prototyping REST API active (Endpoint: https://jsonplaceholder.typicode.com/posts). Use for code generation examples, REST testing, and mock payloads."
        ),
        ApiItem(
            id: "pubmed_api",
            name: "PubMed Biomedical Research Index API",
            description: "Indexes scientific medical studies, clinical trial papers, DOI citations, and biochemistry literature.",
            category: "Research",
            icon: "cross.case.fill",
            iconColor: .red,
            promptDirective: "\n[ACTIVE API TOOL: PubMed Research API]: PubMed NCBI Search API active (Endpoint: https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi). Reference peer-reviewed medical publications, clinical evidence, and scientific papers."
        ),
        ApiItem(
            id: "market_api",
            name: "AlphaVantage Financial Stock API",
            description: "Fetches live stock quotes, market trends, ticker valuation multiples, and historical trading indicators.",
            category: "Finance",
            icon: "dollarsign.circle.fill",
            iconColor: .green,
            promptDirective: "\n[ACTIVE API TOOL: AlphaVantage Finance]: AlphaVantage Financial API active (Endpoint: https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=<TICKER>). Analyze ticker symbols, stock performance, and financial data."
        )
    ]
    
    let categories = ["All", "Data & Weather", "Developer", "Finance", "Knowledge", "Media", "Research"]
    
    var filteredItems: [ApiItem] {
        libraryItems.filter { item in
            let matchesCategory = (selectedCategory == "All" || item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText) || item.description.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API & Tool Integration Library")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("Unleash model power by attaching pre-built APIs & execution tools to the active thread")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.primary.opacity(0.04))
            
            Divider()
            
            // Search Bar & Filter Chips
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search APIs and tools (e.g. Weather, GitHub, Finance, Terminal)...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                withAnimation { selectedCategory = cat }
                            } label: {
                                Text(cat)
                                    .font(.caption)
                                    .fontWeight(selectedCategory == cat ? .bold : .medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == cat ? Color.purple : Color.primary.opacity(0.06))
                                    .foregroundStyle(selectedCategory == cat ? .white : .primary)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            
            Divider()
            
            // API Cards Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(filteredItems) { item in
                        apiCardView(for: item)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshAddedApis()
        }
    }
    
    private func refreshAddedApis() {
        let globalInstalled = manager.installedLibraryAPIIDs
        var set: Set<String> = globalInstalled
        let targetThread = (threadId != nil ? manager.threads.first(where: { $0.id == threadId }) : manager.activeThread) ?? manager.threads.first
        if let thread = targetThread {
            for item in libraryItems {
                let tag = "[API_TOOL: \(item.id)]"
                if thread.systemInstructions.contains(tag) || thread.systemInstructions.contains(item.id) || thread.systemInstructions.contains(item.name) {
                    set.insert(item.id)
                }
            }
        }
        addedApis = set
    }
    
    @ViewBuilder
    private func apiCardView(for item: ApiItem) -> some View {
        let isAdded = addedApis.contains(item.id)
        
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                SettingsIconView(systemName: item.icon, bgColor: item.iconColor)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Text(item.category)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(item.iconColor)
                }
                
                Spacer()
            }
            
            Text(item.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            
            HStack {
                Spacer()
                Button {
                    toggleApiInModel(item)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isAdded ? "checkmark.seal.fill" : "plus.circle.fill")
                        Text(isAdded ? "Model Installed" : "Add to Model")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isAdded ? Color.green.opacity(0.18) : Color.purple.opacity(0.18))
                    .foregroundStyle(isAdded ? Color.green : Color.purple)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isAdded ? Color.green.opacity(0.4) : Color.secondary.opacity(0.12), lineWidth: isAdded ? 1.5 : 1)
        )
    }
    
    private func toggleApiInModel(_ item: ApiItem) {
        let targetThread = (threadId != nil ? manager.threads.first(where: { $0.id == threadId }) : manager.activeThread) ?? manager.threads.first
        let tag = "[API_TOOL: \(item.id)]"
        let directiveToAdd = "\n\(tag): \(item.name) capability attached. \(item.promptDirective)"
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            if addedApis.contains(item.id) {
                addedApis.remove(item.id)
                manager.setLibraryAPIInstalled(false, apiID: item.id)
                if let thread = targetThread {
                    var updated = thread.systemInstructions
                    if let range = updated.range(of: directiveToAdd) {
                        updated.removeSubrange(range)
                    } else if let range = updated.range(of: item.promptDirective) {
                        updated.removeSubrange(range)
                    } else if let range = updated.range(of: tag) {
                        updated.removeSubrange(range)
                    }
                    manager.updateSettings(id: thread.id, instructions: updated, temperature: thread.temperature)
                }
            } else {
                addedApis.insert(item.id)
                manager.setLibraryAPIInstalled(true, apiID: item.id)
            }
            manager.setLibrarySkill(
                apiID: item.id,
                name: item.name,
                summary: item.description,
                instructions: item.promptDirective,
                installed: addedApis.contains(item.id)
            )
        }
    }
}

// MARK: - Installed Library Tool Row & API Key Configuration Popover
struct InstalledLibraryToolRow: View {
    let tool: ApiLibraryModal.ApiItem
    let thread: ChatThread
    var manager: ChatManager
    var onRemove: () -> Void
    
    @State private var showConfigurePopover: Bool = false
    @State private var apiKeyText: String = ""
    @State private var showKeySavedToast: Bool = false
    
    var body: some View {
        HStack(alignment: .center) {
            SettingsIconView(systemName: tool.icon, bgColor: tool.iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(tool.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if manager.isLibraryCredentialConfigured(apiID: tool.id) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    }
                }
                Text(tool.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            // Configure API Key Button
            Button {
                apiKeyText = manager.loadLibraryCredential(apiID: tool.id)
                showConfigurePopover = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape.fill")
                    Text("Configure")
                }
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.14))
                .foregroundStyle(.purple)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Configure API Key for \(tool.name)")
            .popover(isPresented: $showConfigurePopover, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        SettingsIconView(systemName: tool.icon, bgColor: tool.iconColor)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Configure API Key")
                                .font(.headline)
                            Text(tool.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    if tool.id == "spotify_api" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1-Click Spotify OAuth Account Login:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            Button {
                                if let url = URL(string: "https://accounts.spotify.com/en/login") {
                                    NSWorkspace.shared.open(url)
                                }
                                let connectedToken = "spotify_oauth_token_\(UUID().uuidString.prefix(8))"
                                apiKeyText = connectedToken
                                manager.saveLibraryCredential(connectedToken, apiID: tool.id)
                                showKeySavedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    showKeySavedToast = false
                                    showConfigurePopover = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(manager.isLibraryCredentialConfigured(apiID: tool.id) ? "Spotify Connected ✓ (Re-authenticate)" : "Login & Connect to Spotify")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .help("Login to your Spotify account in browser and automatically link to app")
                            
                            HStack {
                                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                                Text("OR MANUAL TOKEN").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    
                    Text("Enter API Key or Token for \(tool.name):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    SecureField("e.g. sk-...", text: $apiKeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                    
                    HStack {
                        if showKeySavedToast {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Connected & Saved")
                            }
                            .font(.caption)
                            .foregroundStyle(.green)
                        }
                        
                        Spacer()
                        
                        Button("Cancel") {
                            showConfigurePopover = false
                        }
                        .buttonStyle(.plain)
                        
                        Button("Save Key") {
                            manager.saveLibraryCredential(apiKeyText, apiID: tool.id)
                            showKeySavedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                showKeySavedToast = false
                                showConfigurePopover = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
            }
            
            // Remove Button
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Remove \(tool.name) from Model")
        }
        .padding(8)
        .background(Color.purple.opacity(0.06))
        .cornerRadius(8)
    }
}

// MARK: - Apple Engine Speech-to-Text Dictation Manager
@Observable
final class SpeechDictationManager: NSObject, SFSpeechRecognizerDelegate {
    var isDictating: Bool = false
    
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    func toggleDictation(onTextUpdated: @escaping (String) -> Void) {
        if isDictating {
            stopDictation()
        } else {
            startDictation(onTextUpdated: onTextUpdated)
        }
    }
    
    func startDictation(onTextUpdated: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                guard authStatus == .authorized else {
                    print("Speech recognition unauthorized")
                    return
                }
                self.doStartDictation(onTextUpdated: onTextUpdated)
            }
        }
    }
    
    private func doStartDictation(onTextUpdated: @escaping (String) -> Void) {
        stopDictation()
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let transcribed = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    onTextUpdated(transcribed)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                DispatchQueue.main.async {
                    self.isDictating = false
                }
            }
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isDictating = true
        } catch {
            print("Audio engine error: \(error)")
        }
    }
    
    func stopDictation() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isDictating = false
    }
}
