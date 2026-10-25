//
//  SettingsButton.swift
//  RollCall
//
//  The gear in the corner of every main screen. It opens a small menu:
//    Your profile     who's signed in, their roll call and community, Sign out
//    About RollCall   what the app does and how privacy works
//    Display          light, dark or match the iPhone, and the color theme
//

import SwiftUI

struct SettingsButton: View {
    /// Blue on the map, ink on the paper pages, like the buttons around it.
    @Environment(\.brand) private var brand
    @State private var showsProfile = false
    @State private var showsAbout = false
    @State private var showsDisplay = false

    var body: some View {
        Menu {
            Button("Your profile", systemImage: "person.crop.circle") { showsProfile = true }
            Button("About RollCall", systemImage: "info.circle") { showsAbout = true }
            Button("Display", systemImage: "paintpalette") { showsDisplay = true }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3.weight(.medium))
                .foregroundStyle(brand)
                .frame(width: minimumTapSize, height: minimumTapSize)
                .flatSurface(cornerRadius: minimumTapSize / 2)
                .contentShape(Circle())
        }
        .accessibilityLabel("Settings")
        .accessibilityHint("Your profile, about RollCall, and display")
        .accessibilityIdentifier("settingsButton")
        .sheet(isPresented: $showsProfile) {
            ProfileView().sheetBrand()
        }
        .sheet(isPresented: $showsAbout) {
            AboutView()
        }
        .sheet(isPresented: $showsDisplay) {
            DisplaySettingsView()
        }
    }
}

/// "Jordan Tatum" -> "JT", for the little avatar squares.
func initials(_ name: String) -> String {
    name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
}
