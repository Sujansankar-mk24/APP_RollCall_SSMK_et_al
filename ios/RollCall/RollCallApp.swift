//
//  RollCallApp.swift
//  RollCall
//
//  Where the app starts: the tab bar (see RootView.swift).
//

import SwiftUI

@main
struct RollCallApp: App {
    /// Who the app is acting as (saved on the device).
    @State private var session = AppSession()
    /// The display choice (Match iPhone / Light / Night mode), saved on the device.
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                // Apply the saved display choice at launch and whenever it changes.
                .onChange(of: appearance, initial: true) { appearance.apply() }
                .task { appearance.apply() }
        }
    }
}
