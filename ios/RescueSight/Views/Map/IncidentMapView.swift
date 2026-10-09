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
//                                       display (light/night) button
//             [Report incident]         recenter button
//
//  Tapping an incident zooms in on it and opens its detail sheet.
//  "Report incident" opens the report form; after sending, a message
//  confirms it and the map moves to the incident.
//

import MapKit
import SwiftUI

struct IncidentMapView: View {
    @State private var viewModel = MapViewModel()
    @State private var cameraPosition: MapCameraPosition = .region(AppConfig.homeRegion)
    @State private var selectedIncidentID: IncidentSummary.ID?
    @State private var sheetDetent: PresentationDetent = .medium
    @State private var isReporting = false
    /// The server's answer to the last report sent, shown as a confirmation message.
    @State private var lastReport: ReportCreated?

    /// The incident whose detail sheet is open (looked up from the latest data).
    private var selectedIncident: IncidentSummary? {
        viewModel.incidents.first { $0.id == selectedIncidentID }
    }

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
                VStack(spacing: Spacing.m) {
                    AppearanceButton()
                    recenterButton
                }
                .padding(Spacing.l)
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.loadState == .loaded {
                VStack(spacing: Spacing.m) {
                    if let report = lastReport {
                        ReportSentToast(result: report) {
                            selectedIncidentID = report.incidentId
                            lastReport = nil
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    reportButton
                }
                .padding(.bottom, Spacing.l)
            }
        }
        .overlay {
            stateOverlay
        }
        .animation(.spring(duration: 0.35), value: lastReport)
        .task(id: lastReport) {
            // Hide the confirmation after a few seconds.
            guard lastReport != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            lastReport = nil
        }
        .sheet(isPresented: $isReporting) {
            ReportFormView { result in
                Task { await reportWasSent(result) }
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.loadState)
        .onChange(of: selectedIncidentID) { _, newValue in
            if newValue != nil { focusOnSelectedIncident() }
        }
        .sheet(isPresented: isShowingDetail) {
            if let incident = selectedIncident {
                IncidentDetailView(summary: incident) {
                    Task { await viewModel.load() }  // update the map's colors after a status change
                }
                .id(incident.id)  // a different incident gets a fresh sheet
                .presentationDetents([.medium, .large], selection: $sheetDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.panel)
                // Keep the map usable behind a half-height sheet (tap another incident).
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.scrolls)
            }
        }
        .task {
            // Runs when the screen appears; SwiftUI cancels it when it goes away.
            await viewModel.load()
            openDebugSelectionIfRequested()
            await viewModel.keepRefreshing()
        }
    }

    // MARK: - Selection

    /// The sheet is open whenever an incident is selected; closing it clears the selection.
    private var isShowingDetail: Binding<Bool> {
        Binding(
            get: { selectedIncidentID != nil },
            set: { isOpen in
                if !isOpen {
                    selectedIncidentID = nil
                    sheetDetent = .medium  // next sheet opens at half height again
                }
            }
        )
    }

    /// After a report is sent: refresh the map, fly to the incident, and confirm.
    private func reportWasSent(_ result: ReportCreated) async {
        await viewModel.load()
        if let incident = viewModel.incidents.first(where: { $0.id == result.incidentId }) {
            // Make sure the new incident isn't hidden by the current filters.
            if !viewModel.filters.matches(incident) { viewModel.clearFilters() }
            focus(on: incident, leavingRoomForSheet: false)
        }
        lastReport = result
    }

    /// Debug builds only: open an incident at launch (for screenshots and testing).
    private func openDebugSelectionIfRequested() {
        if DebugLaunchOptions.opensReportForm {
            isReporting = true
            return
        }
        guard let id = DebugLaunchOptions.incidentToSelect else { return }
        if DebugLaunchOptions.opensLargeSheet { sheetDetent = .large }
        selectedIncidentID = id
    }

    private func focusOnSelectedIncident() {
        guard let incident = selectedIncident else { return }
        focus(on: incident, leavingRoomForSheet: true)
    }

    /// Zoom in on an incident. With `leavingRoomForSheet`, it's placed in the
    /// strip of map between the top controls and the half-height sheet.
    private func focus(on incident: IncidentSummary, leavingRoomForSheet: Bool) {
        let height = 0.06  // degrees of latitude shown top to bottom (about 6.5 km)
        // Moving the map's center south pushes the incident up the screen.
        let shift = leavingRoomForSheet ? height * 0.35 : 0
        let center = CLLocationCoordinate2D(latitude: incident.latitude - shift,
                                            longitude: incident.longitude)
        withAnimation(.easeInOut(duration: 0.6)) {
            // The tiny longitude span makes the map fit the height exactly,
            // so the 0.35 shift above always lands in the same place.
            cameraPosition = .region(MKCoordinateRegion(
                center: center, span: MKCoordinateSpan(latitudeDelta: height, longitudeDelta: 0.001)))
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

    /// The main action on the map.
    private var reportButton: some View {
        Button {
            selectedIncidentID = nil
            lastReport = nil
            isReporting = true
        } label: {
            Label("Report incident", systemImage: "exclamationmark.bubble.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .frame(minHeight: 52)
                .background(Color.accentColor, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a form to report an emergency")
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
