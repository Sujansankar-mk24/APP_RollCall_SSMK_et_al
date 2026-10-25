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

/// The app's color theme (Settings > Display): the color of the main buttons,
/// the chosen tab chips and switches on every page except the Map. Each one
/// is shown with its color next to it, so it's easy to see what you'll get.
enum AppTheme: String, CaseIterable, Identifiable {
    case classic, ocean, forest, sunset, teal, graphite

    var id: Self { self }
    static let storageKey = "appTheme"

    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classic"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .sunset: "Sunset"
        case .teal: "Lagoon"
        case .graphite: "Graphite"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .classic: "Black and white, like a printed sheet"
        case .ocean: "Calm blue"
        case .forest: "Deep green"
        case .sunset: "Warm orange"
        case .teal: "Fresh blue-green"
        case .graphite: "Soft gray"
        }
    }

    /// The main color. Classic is black in light mode and white in dark mode.
    var color: Color {
        switch self {
        case .classic: .ink
        case .ocean: Color(red: 0.12, green: 0.42, blue: 0.90)
        case .forest: Color(red: 0.11, green: 0.52, blue: 0.31)
        case .sunset: Color(red: 0.88, green: 0.40, blue: 0.08)
        case .teal: Color(red: 0.0, green: 0.52, blue: 0.56)
        case .graphite: Color(red: 0.36, green: 0.38, blue: 0.42)
        }
    }

    /// Text drawn on top of the main color.
    var onColor: Color { self == .classic ? .paper : .white }
}

extension EnvironmentValues {
    /// The color of text on a filled main button (white, or the page color for Classic).
    @Entry var onBrand: Color = .white
}

/// The chosen theme, shared by the whole app. It's @Observable, so every
/// view that reads it redraws when the theme changes.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.storageKey) }
    }

    private init() {
        theme = UserDefaults.standard.string(forKey: AppTheme.storageKey).flatMap(AppTheme.init) ?? .classic
    }
}

extension AppTheme {
    /// The color for the Map's buttons and highlights. Classic keeps the
    /// map's own blue (black buttons would get lost on a map).
    var mapColor: Color { self == .classic ? .accentColor : color }
    /// A very light wash of the theme color for page backgrounds.
    var pageWash: Color { self == .classic ? .clear : color.opacity(0.07) }
    /// Small labels and headings take the theme color too (Classic stays gray).
    var labelColor: Color { self == .classic ? .secondary : color }
}

extension Color {
    /// The theme's color for the Map and the report form (blue for Classic).
    static var themeAccent: Color { ThemeStore.shared.theme.mapColor }
}

/// Applies the chosen color theme to a whole screen.
struct ThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        let theme = ThemeStore.shared.theme
        return content
            .environment(\.brand, theme.color)
            .environment(\.onBrand, theme.onColor)
            .tint(theme.color)
    }
}
