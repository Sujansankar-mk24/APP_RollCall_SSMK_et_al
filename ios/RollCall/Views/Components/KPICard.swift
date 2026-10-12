//
//  KPICard.swift
//  RollCall
//
//  A number card: big number, label, and one line of context. It turns red or
//  amber when its number means "someone needs help".
//

import SwiftUI

struct KPICard: View {
    let title: LocalizedStringKey
    let value: String
    let caption: LocalizedStringKey
    let systemImage: String
    var emphasis: Color?       // red/amber when the number needs attention
    var identifier: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(emphasis ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .card(padding: Spacing.m)
        .overlay(alignment: .topTrailing) {
            // A small colored dot, so "needs attention" never depends on color
            // alone: the caption says why.
            if let emphasis {
                Circle().fill(emphasis).frame(width: 8, height: 8).padding(Spacing.m)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    KPICard(title: "Needs help", value: "3", caption: "Waiting for a responder", systemImage: "exclamationmark.triangle.fill", emphasis: .red)
        .padding()
        .background(Color(.systemGroupedBackground))
}
