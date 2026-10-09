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
    var body: some Scene {
        WindowGroup {
            IncidentMapView()
        }
    }
}
