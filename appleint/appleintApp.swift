//
//  appleintApp.swift
//  appleint
//
//  Created by Vijay on 10/07/26.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce Halite title on main application menu
        if let menu = NSApp.mainMenu?.items.first {
            menu.title = "Halite"
            menu.submenu?.title = "Halite"
        }
    }
}

@main
struct appleintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var manager: ChatManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAppearance") private var appAppearance: String = "system"

    init() {
        _manager = State(initialValue: AppBootstrapper.makeChatManager())
    }

    var body: some Scene {
        WindowGroup("Halite") {
            ContentView()
                .environment(manager)
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { manager.flushThreadPersistence() }
                }
        }
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About Halite") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "Halite"
                        ]
                    )
                }
            }
        }
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
}
