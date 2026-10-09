//
//  RootView.swift
//  RescueSight
//
//  The tab bar: Map and Incidents. (An About tab is added in the next step.)
//  Both tabs share one IncidentStore, so they always show the same data.
//

import SwiftUI

struct RootView: View {
    @State private var store = IncidentStore()
    @State private var selection: RootTab = DebugLaunchOptions.startsOnIncidentsTab ? .incidents : .map

    enum RootTab: Hashable {
        case map, incidents
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
        }
    }
}

#Preview {
    RootView()
}
