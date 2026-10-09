//
//  IncidentMapView.swift
//  RescueSight
//
//  The home screen: a full-screen map of North Texas with a colored zone
//  for every incident, plus floating controls on top.
//
//  Layout (top to bottom):
//    filter chips
//    "Updated ... ago"                  legend
//    (map with zones and markers)
//                                       recenter button
//

import MapKit
import SwiftUI

struct IncidentMapView: View {
    @State private var viewModel = MapViewModel()
    @State private var cameraPosition: MapCameraPosition = .region(AppConfig.homeRegion)
    @State private var selectedIncidentID: IncidentSummary.ID?

    var body: some View {
        Map(position: $cameraPosition, selection: $selectedIncidentID) {
            ForEach(viewModel.visibleIncidents) { incident in
                // The zone: see-through fill so streets stay readable, solid edge.
                MapCircle(center: incident.coordinate, radius: incident.zoneRadius)
                    .foregroundStyle(incident.status.color.opacity(0.28))
                    .stroke(incident.status.color.opacity(0.9), lineWidth: 1.5)

                // The icon in the middle of the zone. Tapping it selects the incident.
                Annotation(incident.locationName, coordinate: incident.coordinate, anchor: .center) {
                    IncidentMarker(incident: incident, isSelected: selectedIncidentID == incident.id)
                }
                .annotationTitles(.hidden)
                .tag(incident.id)
            }
        }
        // A calm map with no restaurants or shops, so the incidents stand out.
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) {
            if viewModel.loadState == .loaded {
                topControls
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.loadState == .loaded {
                recenterButton
                    .padding(Spacing.l)
            }
        }
        .overlay {
            stateOverlay
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.loadState)
        .task {
            // Runs when the screen appears; SwiftUI cancels it when it goes away.
            await viewModel.load()
            await viewModel.keepRefreshing()
        }
    }

    // MARK: - Floating controls

    private var topControls: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            MapFilterBar(filters: $viewModel.filters)

            HStack(alignment: .top) {
                UpdateStatusPill(
                    lastUpdated: viewModel.lastUpdated,
                    refreshError: viewModel.refreshError,
                    isRefreshing: viewModel.isRefreshing,
                    onRetry: { Task { await viewModel.load() } }
                )
                Spacer()
                MapLegend()
            }
            .padding(.horizontal, Spacing.l)
        }
        .padding(.top, Spacing.xs)
    }

    private var recenterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(AppConfig.homeRegion)
            }
        } label: {
            Image(systemName: "scope")
                .font(.title3.weight(.medium))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .floatingSurface(cornerRadius: 24)
        .accessibilityLabel("Recenter map")
        .accessibilityHint("Shows all of North Texas")
    }

    // MARK: - Loading, error and empty states

    @ViewBuilder
    private var stateOverlay: some View {
        switch viewModel.loadState {
        case .loading:
            HStack(spacing: Spacing.s) {
                ProgressView()
                Text("Loading incidents…")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .floatingSurface(cornerRadius: Radius.panel)

        case .failed(let error):
            MessageCard(
                systemImage: "antenna.radiowaves.left.and.right.slash",
                title: error.title,
                message: error.message,
                actionTitle: "Try again",
                isWorking: viewModel.isRefreshing,
                action: { Task { await viewModel.retry() } }
            )
            .padding(Spacing.l)

        case .loaded:
            if viewModel.incidents.isEmpty {
                MessageCard(
                    systemImage: "checkmark.shield",
                    title: "No incidents reported",
                    message: "When people in your community report an emergency, it will appear on this map."
                )
                .padding(Spacing.l)
            } else if viewModel.visibleIncidents.isEmpty {
                MessageCard(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "No incidents match these filters",
                    message: "Try a longer time range or include more types and statuses.",
                    actionTitle: "Clear filters",
                    action: { viewModel.clearFilters() }
                )
                .padding(Spacing.l)
            }
        }
    }
}

#Preview {
    IncidentMapView()
}
