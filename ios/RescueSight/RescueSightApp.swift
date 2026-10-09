//
//  RescueSightApp.swift
//  RescueSight
//
//  Where the app starts: the tab bar (Map, Incidents).
//

import SwiftUI

@main
struct RescueSightApp: App {
    /// The display choice (Match iPhone / Light / Night mode), saved on the device.
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                // Apply the saved choice at launch and whenever it changes.
                .onChange(of: appearance, initial: true) { appearance.apply() }
                .task { appearance.apply() }
        }
    }
}
