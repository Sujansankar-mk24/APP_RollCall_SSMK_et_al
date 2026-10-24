//
//  NearbyDangerBanner.swift
//  RollCall
//
//  The warning at the top of the Map when you're close to a hazard:
//  "Active fire 2.1 mi away", or "You're inside a Tornado Warning".
//  Tapping it shows the hazard. The X hides it until a different hazard
//  comes close.
//

import SwiftUI

struct NearbyDangerBanner: View {
    let danger: NearbyDanger
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button(action: onOpen) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: danger.kind.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(danger.kind.color, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(danger.isInside ? "You're inside this area" : "\(danger.distanceText) from you")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(danger.kind.color)
                        Text(verbatim: danger.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("Tap for what to do")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: minimumTapSize, height: minimumTapSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide this warning")
        }
        .padding(.leading, Spacing.m)
        .padding(.vertical, Spacing.s)
        .floatingSurface(cornerRadius: Radius.card)
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(danger.kind.color.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearbyDanger")
    }
}
