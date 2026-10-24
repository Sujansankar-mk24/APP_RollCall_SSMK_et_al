//
//  Appearance.swift
//  RollCall
//
//  The display option: follow the iPhone's setting, or always use light or
//  dark ("night") mode. Dark mode is easier on the eyes at night and also
//  switches the map to its night style.
//
//  The choice is saved with @AppStorage, so it's remembered after the app
//  closes. It's picked from the gear's menu (SettingsButton.swift).
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
