//
//  RootView.swift
//  RollCall
//
//  The tab bar along the bottom of the app:
//    Map        incidents on a map; report one with a photo or video
//    Incidents  the same incidents as a priority list for responders
//    Roll Call  households check in during an emergency (resident, buddy, responder)
//    About      what RollCall is, how privacy works, and "call 911"
//  Map and Incidents share one IncidentStore, so they always show the same data.
//

import SwiftUI

struct RootView: View {
    @State private var store = IncidentStore()
    @State private var selection: RootTab = DebugLaunchOptions.startTab

    enum RootTab: String, Hashable {
        case map, incidents, rollCall, about
    }

    var body: some View {
        TabView(selection: $selection) {
            IncidentMapView(store: store)
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(RootTab.map)

            IncidentsView(store: store)
                .tabItem { Label("Incidents", systemImage: "list.bullet.rectangle.fill") }
                .badge(store.needsAttentionCount)   // active, high-priority incidents
                .tag(RootTab.incidents)

            RollCallTabView()
                .tabItem { Label("Roll Call", systemImage: "person.crop.circle.badge.checkmark") }
                .tag(RootTab.rollCall)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
                .tag(RootTab.about)
        }
    }
}

#Preview {
    RootView()
        .environment(AppSession())
}
