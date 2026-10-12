//
//  Badges.swift
//  RollCall
//
//  Small rounded labels for status, priority and needs. The icon carries the
//  color; the text stays in the normal text color so it's always easy to
//  read (orange or gray text on a light background would be too faint).
//

import SwiftUI

struct Badge: View {
    private let text: Text
    let systemImage: String
    var color: Color = .accentColor

    /// For fixed wording, like "Oxygen" (translated from the String Catalog).
    init(text: LocalizedStringKey, systemImage: String, color: Color = .accentColor) {
        self.text = Text(text)
        self.systemImage = systemImage
        self.color = color
    }

    /// For wording that's already worked out in code, like "High priority · 92".
    init<S: StringProtocol>(text: S, systemImage: String, color: Color = .accentColor) {
        self.text = Text(text)
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .imageScale(.small)
            text
                .foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct StatusBadge: View {
    let status: IncidentStatus

    var body: some View {
        Badge(text: status.title, systemImage: status.symbol, color: status.color)
            .accessibilityLabel("Status: \(status.title)")
    }
}

struct PriorityBadge: View {
    let priority: Priority

    var body: some View {
        Badge(text: "\(priority.level.title) priority · \(priority.score)",
              systemImage: "gauge.with.dots.needle.67percent",
              color: priority.level.color)
            .accessibilityLabel("\(priority.level.title) priority, score \(priority.score) out of 100")
    }
}

#Preview {
    VStack(spacing: Spacing.m) {
        ForEach(IncidentStatus.allCases) { StatusBadge(status: $0) }
        PriorityBadge(priority: Priority(score: 92, level: .high, factors: []))
        Badge(text: "Oxygen", systemImage: "lungs.fill", color: .red)
    }
    .padding()
}
