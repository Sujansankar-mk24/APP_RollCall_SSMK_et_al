//
//  IncidentMarker.swift
//  RollCall
//
//  The round icon for a community report.
//  Color and symbol = the kind of incident (tornado purple, fire red-orange,
//  ...). A small badge shows the status: responders on the way, or resolved
//  (resolved reports also fade). Active high-priority incidents pulse.
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
                .fill(incident.status == .resolved ? Color(.systemGray) : incident.type.color)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
                .frame(width: diameter, height: diameter)

            Image(systemName: incident.type.symbol)
                .font(.system(size: isSelected ? 19 : 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .bottomTrailing) {
            if incident.status != .active {
                // Status badge: an orange "on the way" or a gray check.
                Image(systemName: incident.status == .responding ? "car.fill" : "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(incident.status.color, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }
        }
        .opacity(incident.status == .resolved ? 0.7 : 1)
        .overlay(alignment: .topTrailing) {
            if incident.ai.analyzing {
                ProgressView()
                    .controlSize(.mini)
                    .padding(3)
                    .background(Color(.systemBackground), in: Circle())
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
            .stroke(incident.type.color, lineWidth: 2)
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
