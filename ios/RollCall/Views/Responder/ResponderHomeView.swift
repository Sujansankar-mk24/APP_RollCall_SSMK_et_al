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
                        Label("No active emergency", systemImage: "shield.lefthalf.filled")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text("To protect residents' privacy, households appear only during an active emergency, and only the homes inside its zone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .floatingSurface(cornerRadius: Radius.panel)
                    .padding(Spacing.l)
                    .accessibilityElement(children: .combine)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { RoleButton(name: String(localized: "Responder")) }
                    ToolbarItem(placement: .topBarTrailing) { AppearanceToolbarMenu() }
                }
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
