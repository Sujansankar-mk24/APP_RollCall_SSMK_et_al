//
//  MapLegend.swift
//  RollCall
//
//  Explains the map: how solid a zone is = how dangerous; the color is the
//  kind of hazard; diamonds are live data, circles are community reports.
//

import SwiftUI

struct MapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(ZoneLevel.allCases) { level in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(level.fillOpacity * 2))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.8), style: level.edge))
                        .frame(width: 14, height: 10)
                    Text(level.title)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill").frame(width: 14)
                Text("Live data")
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "circle.fill").frame(width: 14)
                Text("Community report")
            }
            .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.s)
        .floatingSurface(cornerRadius: Radius.control + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map legend. The most solid zones are immediate danger, lighter zones mean evacuate, faint dashed zones mean be cautious. Colors show the kind of hazard. Diamonds are live data, circles are community reports.")
    }
}

#Preview {
    MapLegend()
        .padding()
        .background(Color.gray.opacity(0.2))
}
