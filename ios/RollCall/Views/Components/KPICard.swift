//
//  KPICard.swift
//  RollCall
//
//  A number on the sheet: a big condensed figure, its label, and one line of
//  context, under a rule. The rule turns red or amber when the number means
//  "someone needs help" (and the caption says why, so color isn't the only clue).
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
            Rectangle().fill(emphasis ?? Color.ink).frame(height: 3)
            Label { Text(title) } icon: { Image(systemName: systemImage) }
                .sheetLabelStyle()
                .foregroundStyle(emphasis ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, Spacing.xs)
            Text(value)
                .font(.system(size: 44, weight: .black).width(.condensed))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    KPICard(title: "Needs help", value: "3", caption: "Waiting for a responder", systemImage: "exclamationmark.triangle.fill", emphasis: .red)
        .padding()
        .sheetPage()
}
