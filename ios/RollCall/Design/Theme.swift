//
//  Theme.swift
//  RollCall
//
//  Design tokens: spacing, corner radii and the floating-panel look are
//  defined once here, so every screen looks consistent. Views use these
//  names (like Spacing.m) instead of typing numbers.
//
//  Colors carry meaning, so they are used for meaning only:
//    red = active emergency / needs help, amber = on the way / no answer yet,
//    gray = resolved, green = safe.
//  The brand/accent color (blue) is for buttons and selection, never status.
//  Status colors always come with an icon and a word, so nobody has to rely
//  on color alone. System colors adjust automatically for dark mode.
//

import SwiftUI

/// Spacing on a 4-point grid.
/// (nonisolated: plain constant numbers, safe to read from any thread.)
nonisolated enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii: small controls, cards, and large panels.
nonisolated enum Radius {
    static let control: CGFloat = 10
    static let card: CGFloat = 16
    static let panel: CGFloat = 22
}

/// Apple's minimum comfortable tap target (Human Interface Guidelines).
nonisolated let minimumTapSize: CGFloat = 44

// MARK: - Brand color

// Shared pieces (counters, check rows, tags, the logo) read `brand` from the
// environment. On the Map and its sheets it's the app's blue accent; on every
// other tab it's ink (see Sheet.swift), so the same component fits both.

extension EnvironmentValues {
    @Entry var brand: Color = .accentColor
}

// MARK: - Meaning colors

extension IncidentStatus {
    var color: Color {
        switch self {
        case .active: Color(.systemRed)
        case .responding: Color(.systemOrange)
        case .resolved: Color(.systemGray)
        }
    }
}

extension PriorityLevel {
    var color: Color {
        switch self {
        case .high: Color(.systemRed)
        case .medium: Color(.systemOrange)
        case .low: Color(.systemGray)
        }
    }
}

// MARK: - Surfaces

extension View {
    /// The look shared by every panel floating over a map. It used to be
    /// frosted glass, and now it's flat like the tab bar.
    func floatingSurface(cornerRadius: CGFloat = Radius.card) -> some View {
        flatSurface(cornerRadius: cornerRadius)
    }

    /// A flat, solid panel (no glass or blur), the same gray as the tab bar,
    /// with a soft shadow so it stands out over the map.
    func flatSurface(cornerRadius: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(Color.tabBar, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    /// A solid card on a grouped background (used for most content).
    func card(padding: CGFloat = Spacing.l) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}


// MARK: - Flat toolbars

extension ToolbarContent {
    /// iOS 26 puts a glass bubble behind toolbar buttons. RollCall keeps
    /// them flat, like the rest of the app.
    @ToolbarContentBuilder
    func flat() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
