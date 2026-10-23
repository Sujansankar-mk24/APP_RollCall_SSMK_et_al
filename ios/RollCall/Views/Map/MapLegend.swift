//
//  MapLegend.swift
//  RollCall
//
//  Explains the map's two kinds of icons: diamonds are live data (official
//  alerts, satellite fires, storm reports), circles are community reports.
//  The color is the kind of hazard.
//

import SwiftUI

struct MapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill").frame(width: 14)
                Text("Live data")
            }
            HStack(spacing: 6) {
                Image(systemName: "circle.fill").frame(width: 14)
                Text("Community report")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.s)
        .floatingSurface(cornerRadius: Radius.control + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map legend. Diamonds are live data, circles are community reports. Colors show the kind of hazard.")
    }
}

#Preview {
    MapLegend()
        .padding()
        .background(Color.gray.opacity(0.2))
}
