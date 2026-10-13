//
//  RootView.swift
//  RollCall
//
//  If an account is saved on this phone, the app opens straight to the tab
//  bar; otherwise it shows the sign-in screen.
//
//  The tab bar along the bottom:
//    Map        incidents on a map; report one with a photo or video
//    Incidents  the same incidents as a priority list for responders
//    Roll Call  your household and the neighbors you check on
//    Community  your neighborhood (not shown to responders)
//    About      what RollCall is, how privacy works, your account
//  Map and Incidents share one IncidentStore, so they always show the same data.
//  Every tab except the Map uses the roll-call sheet look (Design/Sheet.swift).
//

import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .sheetPage()
            case .signedOut:
                SignInView()
            case .offline(let error):
                // There's a saved account, but the server can't be reached.
                VStack(spacing: Spacing.l) {
                    SheetMessage(error: error, action: { Task { await auth.restore() } })
                    Button("Sign out") { Task { await auth.signOut() } }
                        .buttonStyle(InkButtonStyle(prominent: false))
                }
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheetPage()
            case .signedIn(let me):
                MainTabView(me: me)
            }
        }
        .animation(.snappy(duration: 0.3), value: auth.state)
        .task { await auth.restore() }
    }
}

struct MainTabView: View {
    let me: Me
    @State private var store = IncidentStore()
    @State private var selection: RootTab = DebugLaunchOptions.startTab

    enum RootTab: String, Hashable {
        case map, incidents, rollCall, community, about
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
                .sheetBrand()
                .tabItem { Label("Roll Call", systemImage: "person.crop.circle.badge.checkmark") }
                .tag(RootTab.rollCall)

            if !me.isResponder {
                CommunityTabView()
                    .sheetBrand()
                    .tabItem { Label("Community", systemImage: "house.and.flag.fill") }
                    .badge(me.community?.status == .pending ? 1 : 0)
                    .tag(RootTab.community)
            }

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
                .tag(RootTab.about)
        }
    }
}
