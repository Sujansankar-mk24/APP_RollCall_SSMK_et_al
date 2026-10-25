//
//  KPICard.swift
//  RollCall
//
//  A number on its own paper card: a big figure, its label, and one line of
//  context. The label turns red or amber when the number means "someone
//  needs help" (and the caption says why, so color isn't the only clue).
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
            // Plain words (not capitals): narrow cards need every letter of room.
            Label { Text(title) } icon: { Image(systemName: systemImage) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(emphasis ?? .secondary)
                .lineLimit(2, reservesSpace: true)   // every card's label takes two lines, so the numbers line up
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(size: 40, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .sheetBox(padding: Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    KPICard(title: "Needs help", value: "3", caption: "Waiting for a responder", systemImage: "exclamationmark.triangle.fill", emphasis: .red)
        .padding()
        .sheetPage()
}
