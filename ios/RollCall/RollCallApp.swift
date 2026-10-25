//
//  RollCallApp.swift
//  RollCall
//
//  Where the app starts: the tab bar (see RootView.swift).
//

import SwiftUI

@main
struct RollCallApp: App {
    /// Who is signed in (the sign-in token is saved in the Keychain).
    @State private var auth = AuthStore()
    /// The display choice (Match iPhone / Light / Night mode), saved on the device.
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        DebugLaunchOptions.resetIntroIfRequested()   // debug builds only (UI tests)
        AlertsManager.shared.setUp()                   // notification buttons ("I'm safe", "I need help")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                // Apply the saved display choice at launch and whenever it changes.
                .onChange(of: appearance, initial: true) { appearance.apply() }
                .task { appearance.apply() }
                // Leaving the app: "How are you?" shows again next time it's opened.
                .onChange(of: scenePhase) { if scenePhase == .background { AlertsManager.shared.answeredThisVisit = false } }
        }
    }
}
