//
//  LocationPickerMap.swift
//  RollCall
//
//  A small map with a pin you can drag (or tap anywhere to move it) to
//  mark exactly where the incident is.
//
//  How dragging works: MapReader gives us a "proxy" that converts between
//  screen points and GPS coordinates. While the pin is dragged, we take the
//  pin's starting point on screen, add how far the finger has moved, and
//  convert that point back into a coordinate.
//

import MapKit
import SwiftUI

struct LocationPickerMap: View {
    let coordinate: CLLocationCoordinate2D
    @Binding var position: MapCameraPosition
    let onMove: (CLLocationCoordinate2D) -> Void

    @State private var dragStartPoint: CGPoint?
    private let space = NamedCoordinateSpace.named("locationPicker")

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                Annotation("Incident location", coordinate: coordinate, anchor: .bottom) {
                    pin
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: space)
                                .onChanged { drag in
                                    // Where the pin's tip was on screen when the drag began.
                                    if dragStartPoint == nil {
                                        dragStartPoint = proxy.convert(coordinate, to: space)
                                    }
                                    guard let start = dragStartPoint else { return }
                                    let point = CGPoint(x: start.x + drag.translation.width,
                                                        y: start.y + drag.translation.height)
                                    if let newCoordinate = proxy.convert(point, from: space) {
                                        onMove(newCoordinate)
                                    }
                                }
                                .onEnded { _ in dragStartPoint = nil }
                        )
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onTapGesture(coordinateSpace: space) { point in
                if let newCoordinate = proxy.convert(point, from: space) {
                    onMove(newCoordinate)
                }
            }
        }
        .coordinateSpace(space)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map with the incident pin")
        .accessibilityHint("Drag the pin or tap the map to move it")
    }

    private var pin: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 36))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color(.systemRed))
            .background(Circle().fill(.white).padding(4))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            .scaleEffect(dragStartPoint == nil ? 1 : 1.2, anchor: .bottom)
            .animation(.spring(duration: 0.2), value: dragStartPoint == nil)
            .frame(width: 52, height: 52, alignment: .bottom)  // bigger area to grab
            .contentShape(Rectangle())
    }
}
