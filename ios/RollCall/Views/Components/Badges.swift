//
//  Badges.swift
//  RollCall
//
//  Small rounded labels ("chips"). The icon carries the color; the text stays
//  in the normal text color so it's always easy to read.
//

import SwiftUI

struct Badge: View {
    let text: LocalizedStringKey
    let systemImage: String
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .imageScale(.small)
            Text(text)
                .foregroundStyle(.primary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: Spacing.m) {
        Badge(text: "Oxygen", systemImage: "lungs.fill", color: .red)
        Badge(text: "No vehicle", systemImage: "figure.walk", color: .orange)
    }
    .padding()
}
