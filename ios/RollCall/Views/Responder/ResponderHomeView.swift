//
//  ResponderHomeView.swift
//  RollCall
//
//  A responder's home. With no active emergency, it shows only the map:
//  household details stay private until an emergency is declared, and then
//  only for homes inside its zone. (Events arrive in step 2; the dashboard
//  with households, scores and routes in step 5.)
//

import MapKit
import SwiftUI

struct ResponderHomeView: View {
    @State private var position: MapCameraPosition = .region(AppConfig.homeRegion)

    var body: some View {
        NavigationStack {
            Map(position: $position)
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Stamp(text: String(localized: "Responder view"), systemImage: "cross.case.fill", tilt: 0)
                        Text("No active emergency")
                            .font(.sheetHeading)
                        Text("To protect residents' privacy, households appear only during an active emergency, and only the homes inside its zone.")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .sheetBox(emphasis: true)
                    .padding(Spacing.l)
                    // The map runs under the tab bar; keep this panel above it.
                    .padding(.bottom, SlidingTabBar<MainTabView.RootTab>.height)
                    .accessibilityElement(children: .combine)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { AccountButton() }
                    ToolbarItem(placement: .topBarTrailing) { AppearanceToolbarMenu() }
                }
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
