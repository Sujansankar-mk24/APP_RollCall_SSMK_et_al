//
//  Theme.swift
//  RescueSight
//
//  Design tokens: the app's spacing, corner radii and meaning-colors are
//  defined once here, so every screen looks consistent. Views use these
//  names (like Spacing.m) instead of typing numbers.
//
//  Colors carry meaning, so they are used for meaning only:
//    red = active emergency, amber = responders on the way, gray = resolved.
//  The brand/accent color (blue) is for buttons and selection, never status.
//  System colors are used because they adjust automatically for dark mode.
//

import SwiftUI

/// Spacing on a 4-point grid.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii: small controls, cards, and large panels.
enum Radius {
    static let control: CGFloat = 10
    static let card: CGFloat = 16
    static let panel: CGFloat = 22
}

/// Apple's minimum comfortable tap target (Human Interface Guidelines).
let minimumTapSize: CGFloat = 44

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

// MARK: - Floating surfaces

extension View {
    /// The look shared by every panel floating over the map: frosted glass
    /// (.ultraThinMaterial), a hairline border and a soft shadow, so it stays
    /// readable over any part of the map in light or dark mode.
    func floatingSurface(cornerRadius: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
