//
//  appleintApp.swift
//  appleint
//
//  Created by Vijay on 10/07/26.
//

import SwiftUI

@main
struct appleintApp: App {
    @State private var manager: ChatManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAppearance") private var appAppearance: String = "system"

    init() {
        _manager = State(initialValue: AppBootstrapper.makeChatManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(manager)
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { manager.flushThreadPersistence() }
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
