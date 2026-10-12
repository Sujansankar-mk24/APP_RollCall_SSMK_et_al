//
//  BrandMark.swift
//  RollCall
//
//  The RollCall logo mark: a person with a check, inside rings that spread
//  out like a roll call going out to a neighborhood.
//

import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 88
    var showsRings = true

    var body: some View {
        ZStack {
            if showsRings {
                ForEach(1...3, id: \.self) { ring in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.16 - Double(ring) * 0.04), lineWidth: 1.5)
                        .frame(width: size * (1 + CGFloat(ring) * 0.55), height: size * (1 + CGFloat(ring) * 0.55))
                }
            }
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .shadow(color: Color.accentColor.opacity(0.35), radius: size * 0.18, y: size * 0.08)
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    BrandMark().padding(80)
}
