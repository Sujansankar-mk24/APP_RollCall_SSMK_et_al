//
//  Appearance.swift
//  RescueSight
//
//  The display option: follow the iPhone's setting, or always use light or
//  dark ("night") mode. Dark mode is easier on the eyes at night and also
//  switches the map to its night style.
//
//  The choice is saved with @AppStorage, so it's remembered after the app closes.
//

import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    /// The key used to save the choice on the device.
    static let storageKey = "appearanceMode"

    var title: String {
        switch self {
        case .system: "Match iPhone"
        case .light: "Light"
        case .dark: "Night mode"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Apply the choice to every window of the app (including sheets and the map).
    /// Setting the window's style works more reliably than SwiftUI's
    /// preferredColorScheme when switching back to "Match iPhone".
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

/// The same display choices as a plain toolbar menu (used on the Incidents tab).
struct AppearanceToolbarMenu: View {
    @AppStorage(AppearanceMode.storageKey) private var mode: AppearanceMode = .system

    var body: some View {
        Menu {
            Picker("Display", selection: $mode) {
                ForEach(AppearanceMode.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            Image(systemName: mode.symbol)
        }
        .accessibilityLabel("Display")
        .accessibilityValue(mode.title)
    }
}

/// The round button on the map that opens the display menu.
struct AppearanceButton: View {
    @AppStorage(AppearanceMode.storageKey) private var mode: AppearanceMode = .system

    var body: some View {
        Menu {
            Picker("Display", selection: $mode) {
                ForEach(AppearanceMode.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            Image(systemName: mode.symbol)
                .font(.title3.weight(.medium))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Color.accentColor)
        .floatingSurface(cornerRadius: 24)
        .accessibilityLabel("Display")
        .accessibilityValue(mode.title)
    }
}
