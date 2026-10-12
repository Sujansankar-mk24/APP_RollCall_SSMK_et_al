//
//  MapLegend.swift
//  RollCall
//
//  Explains what the zone colors and sizes mean.
//

import SwiftUI

struct MapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(IncidentStatus.allCases) { status in
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 10, height: 10)
                    Text(status.title)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "circle.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Text("Bigger = more reports")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.s)
        .floatingSurface(cornerRadius: Radius.control + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map legend. Red zones are active, amber zones have responders on the way, gray zones are resolved. Bigger zones have more reports.")
    }
}

#Preview {
    MapLegend()
        .padding()
        .background(Color.gray.opacity(0.2))
}
