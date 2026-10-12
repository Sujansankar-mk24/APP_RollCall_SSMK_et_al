//
//  IncidentMarker.swift
//  RollCall
//
//  The round icon drawn at the center of each incident zone.
//  Color = status, symbol = type. Active high-priority incidents pulse.
//  A small spinner shows while the AI is still checking a photo/video.
//

import SwiftUI

struct IncidentMarker: View {
    let incident: IncidentSummary
    let isSelected: Bool

    /// Respect the iPhone's "Reduce Motion" setting: no pulsing if it's on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var diameter: CGFloat { isSelected ? 44 : 34 }

    var body: some View {
        ZStack {
            if incident.needsAttention && !reduceMotion {
                pulseRing
            }

            Circle()
                .fill(incident.status.color)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
                .frame(width: diameter, height: diameter)

            Image(systemName: incident.type.symbol)
                .font(.system(size: isSelected ? 19 : 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .topTrailing) {
            if incident.ai.analyzing {
                ProgressView()
                    .controlSize(.mini)
                    .padding(3)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: incident.ai.analyzing)
        .frame(width: minimumTapSize, height: minimumTapSize)  // easy to tap even when small
        .contentShape(Circle())
        .animation(.spring(duration: 0.25), value: isSelected)
        // VoiceOver reads one clear sentence instead of "circle, image".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(incident.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A ring that grows and fades out, over and over.
    private var pulseRing: some View {
        Circle()
            .stroke(incident.status.color, lineWidth: 2)
            .frame(width: 34, height: 34)
            .scaleEffect(isPulsing ? 2.1 : 1)
            .opacity(isPulsing ? 0 : 0.7)
            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

#Preview {
    HStack(spacing: Spacing.xl) {
        ForEach(PreviewData.incidents) { incident in
            IncidentMarker(incident: incident, isSelected: false)
        }
    }
    .padding(40)
}
