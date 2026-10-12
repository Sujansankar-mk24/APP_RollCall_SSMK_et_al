//
//  Theme.swift
//  RollCall
//
//  Design tokens: spacing, corner radii and the floating-panel look are
//  defined once here, so every screen looks consistent. Views use these
//  names (like Spacing.m) instead of typing numbers.
//
//  Colors carry meaning and are used for meaning only. The brand color is a
//  deep indigo (Assets > AccentColor) for buttons and selection; it never
//  means a status. Status colors (green safe, red needs help, ...) live with
//  the status itself and always come with an icon and a word, so nobody has
//  to rely on color alone.
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
    static let control: CGFloat = 12
    static let card: CGFloat = 20
    static let panel: CGFloat = 28
}

/// Apple's minimum comfortable tap target (Human Interface Guidelines).
nonisolated let minimumTapSize: CGFloat = 44

extension View {
    /// The look shared by every panel floating over a map: frosted glass
    /// (.ultraThinMaterial), a hairline border and a soft shadow, so it stays
    /// readable over any part of the map in light or dark mode.
    func floatingSurface(cornerRadius: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
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
