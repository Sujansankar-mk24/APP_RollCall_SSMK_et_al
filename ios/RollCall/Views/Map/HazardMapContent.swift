//
//  HazardMapContent.swift
//  RollCall
//
//  Drawing danger zones and live-hazard markers on the map.
//
//    Areas     official alerts (like a Tornado Warning) shade the area they
//              cover, colored by the kind of hazard; the more serious, the
//              more solid (see ZoneLevel in Models/Hazard.swift).
//    Markers   live data (official alerts, satellite fires, storm reports) is
//              a DIAMOND; community reports are CIRCLES (IncidentMarker).
//

import MapKit
import SwiftUI

/// The area an official alert covers (e.g. a Tornado Warning's box), drawn
/// as one shape. Rings around points aren't drawn: the icons say enough.
struct ZoneShapes: MapContent {
    let zones: [HazardZone]
    let center: CLLocationCoordinate2D
    let color: Color

    var body: some MapContent {
        ForEach(Array(zones.outsideIn.filter { $0.polygon != nil }.enumerated()), id: \.offset) { _, zone in
            MapPolygon(coordinates: zone.outline)
                .foregroundStyle(color.opacity(zone.level.fillOpacity))
                .stroke(color.opacity(0.9), style: zone.level.edge)
        }
    }
}

/// The diamond icon for a live hazard.
struct HazardMarker: View {
    let hazard: Hazard
    let isSelected: Bool

    private var size: CGFloat { isSelected ? 36 : 28 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hazard.kind.color)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white, lineWidth: 2))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(45))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
            Image(systemName: hazard.kind.symbol)
                .font(.system(size: isSelected ? 16 : 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .bottom) {
            if hazard.isDemo {
                Text("DEMO")
                    .font(.system(size: 9, weight: .heavy))
                    .fixedSize()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .offset(y: 16)
            }
        }
        .frame(width: minimumTapSize, height: minimumTapSize)
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.25), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hazard.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
