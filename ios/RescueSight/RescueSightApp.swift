//
//  RescueSightApp.swift
//  RescueSight
//
//  Where the app starts. It opens straight onto the incident map.
//  (The Incidents and About tabs are added in later steps.)
//

import SwiftUI

@main
struct RescueSightApp: App {
    /// The display choice (Match iPhone / Light / Night mode), saved on the device.
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            IncidentMapView()
                // Apply the saved choice at launch and whenever it changes.
                .onChange(of: appearance, initial: true) { appearance.apply() }
                .task { appearance.apply() }
        }
    }
}
