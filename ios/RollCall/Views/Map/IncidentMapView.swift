//
//  IncidentMapView.swift
//  RollCall
//
//  The home screen: a full-screen map of North Texas with danger zones
//  around every hazard, plus floating controls on top.
//
//  Two kinds of hazards share the map:
//    live data (diamonds)        real National Weather Service alerts, NASA
//                                satellite fires and NOAA storm reports
//    community reports (circles) what residents reported in the app
//  Colors show the kind of hazard; official alerts also shade their area.
//
//  Layout (top to bottom):
//    [Incidents ⌄]  filter chips        settings (gear)
//    "Updated ... ago", "Live"          legend
//    "Use my location"
//    (the Incidents button unrolls the incident log over the top left)
//    (map with zones and markers, and a blue dot for you)
//                                       zoom in / zoom out
//             [Report incident]         recenter button
//
//  Tapping an incident zooms in on it and opens its detail sheet.
//  "Report incident" opens the report form; after sending, a message
//  confirms it and the map moves to the incident.
//

import MapKit
import SwiftUI

struct IncidentMapView: View {
    @State private var viewModel: MapViewModel
    @State private var cameraPosition: MapCameraPosition = .region(AppConfig.homeRegion)
    /// The area currently on screen (updated whenever the map stops moving).
    @State private var visibleRegion = AppConfig.homeRegion
    @State private var selectedIncidentID: IncidentSummary.ID?
    @State private var sheetDetent: PresentationDetent = .medium
    @State private var isReporting = false
    /// The server's answer to the last report sent, shown as a confirmation message.
    @State private var lastReport: ReportCreated?
    /// What the AI found in that report's photo/video (updates live).
    @State private var lastReportAnalysis: ReportAnalysisState = .noMedia
    /// The live hazard whose sheet is open.
    @State private var selectedHazard: Hazard?
    @State private var showsLiveData = false
    /// The incident log panel (top left), opened from the Incidents button.
    @State private var showsIncidents = DebugLaunchOptions.opensIncidents
    /// The map's size on screen (the incident log is sized from it).
    @State private var mapSize: CGSize = .zero
    /// Follows the phone for the blue dot ("Use my location").
    @State private var live = LiveLocation()
    @State private var tracking: Tracking = .off
    @State private var locationProblem: LocationProblem?
    /// Which way the map is turned (0 = north up), so the dot's cone points the right way.
    @State private var cameraHeading: Double = 0
    /// How far up the map's camera is (meters), so following you keeps your zoom.
    @State private var cameraDistance: Double = 0
    /// A nearby-danger warning the user closed (it comes back for a different hazard).
    @State private var dismissedDangerID: String?
    /// "My community": your neighbors' homes, with their pictures in bubbles.
    @State private var showsCommunity = false
    @State private var homes: [CommunityHome] = []
    @State private var openPerson: Int?
    @Environment(AuthStore.self) private var auth
    /// Lets the compass sit with the other map buttons.
    @Namespace private var mapScope
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: IncidentStore) {
        _viewModel = State(initialValue: MapViewModel(store: store))
    }

    /// The incident whose detail sheet is open (looked up from the latest data).
    private var selectedIncident: IncidentSummary? {
        viewModel.incidents.first { $0.id == selectedIncidentID }
    }

    var body: some View {
        Map(position: $cameraPosition, selection: $selectedIncidentID, scope: mapScope) {
            // Live hazards first (underneath), then community reports on top.
            ForEach(viewModel.visibleHazards) { hazard in
                ZoneShapes(zones: hazard.zones, center: hazard.coordinate, color: hazard.kind.color)
                Annotation(hazard.title, coordinate: hazard.coordinate, anchor: .center) {
                    Button { select(hazard) } label: {
                        HazardMarker(hazard: hazard, isSelected: selectedHazard?.id == hazard.id)
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }

            // My community: a small house for each neighbor, and up close a
            // bubble with their picture above it.
            if showsCommunity {
                ForEach(homes) { home in
                    Annotation(home.name, coordinate: CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude),
                               anchor: .bottom) {
                        CommunityHomeMarker(home: home, showsBubble: isZoomedInClose) { openPerson = home.userId }
                    }
                    .annotationTitles(.hidden)
                }
            }

            // You are here: the blue dot, with a cone showing which way you face.
            if tracking != .off, let here = live.location {
                Annotation("Your location", coordinate: here.coordinate, anchor: .center) {
                    UserLocationDot(coneAngle: live.heading.map { $0 - cameraHeading })
                }
                .annotationTitles(.hidden)
            }

            ForEach(viewModel.visibleIncidents) { incident in

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
            MapScaleView()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            cameraHeading = context.camera.heading
            cameraDistance = context.camera.distance
        }
        // While following, keep the map on you as you move (and turned the
        // way you face, in compass mode).
        .onChange(of: live.location) {
            if tracking.follows { moveCameraToUser(animated: true) }
            reportSurroundings()
        }
        .onChange(of: viewModel.hazardFeed?.updatedAt) { reportSurroundings() }
        .onChange(of: live.heading) { if tracking == .compass { moveCameraToUser(animated: false) } }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        // Dragging the map yourself stops following you (the dot stays).
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
            if tracking.follows { tracking = .shown }
        })
        .onChange(of: live.authorization) {
            if live.isDenied && tracking != .off {
                tracking = .off
                locationProblem = .denied
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
        .safeAreaInset(edge: .top) {
            if viewModel.loadState == .loaded {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    topBar
                        // The incident log hangs just below the button row, on
                        // top of everything else (it doesn't push anything down).
                        .overlay(alignment: .bottomLeading) {
                            incidentsPanel
                                .alignmentGuide(.bottom) { panel in panel[.top] - Spacing.s }
                        }
                        .zIndex(1)
                    infoRow
                    nearbyWarning
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Step aside while the report confirmation is showing (they'd overlap).
            if viewModel.loadState == .loaded && lastReport == nil {
                VStack(spacing: Spacing.m) {
                    // Always on screen, like Google Maps. Tap it to turn north up.
                    MapCompass(scope: mapScope)
                        .mapControlVisibility(.visible)
                    zoomButtons
                    recenterButton
                }
                .padding(Spacing.l)
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.loadState == .loaded {
                VStack(spacing: Spacing.m) {
                    if let report = lastReport {
                        // "View" only once it's on the map (a report under review isn't yet).
                        let isOnMap = viewModel.incidents.contains { $0.id == report.incidentId }
                        ReportSentToast(result: report, analysis: lastReportAnalysis, onView: isOnMap ? {
                            selectedIncidentID = report.incidentId
                            lastReport = nil
                        } : nil)
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
            await followLastReport()
        }
        .sheet(item: $openPerson) { id in PersonProfileView(personID: id).sheetBrand() }
        .alert(item: $locationProblem) { problem in
            problem.alert
        }
        .sheet(isPresented: $isReporting) {
            ReportFormView { result in
                Task { await reportWasSent(result) }
            }
            .presentationBackground(Color(.systemGroupedBackground))
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.loadState)
        .onChange(of: selectedIncidentID) { _, newValue in
            if newValue != nil {
                selectedHazard = nil
                if showsIncidents { setIncidents(open: false) }   // tapped on the map with the log open
                focusOnSelectedIncident()
            }
        }
        .sheet(item: $selectedHazard) { hazard in
            HazardDetailView(hazard: hazard, note: viewModel.hazardFeed?.note ?? "")
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.panel)
                .presentationBackground(Color(.systemBackground))
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showsLiveData) {
            LiveDataSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color(.systemGroupedBackground))
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
                .presentationBackground(Color(.systemBackground))
                // Keep the map usable behind a half-height sheet (tap another incident).
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.scrolls)
            }
        }
        .task {
            // Runs when the screen appears; SwiftUI cancels it when it goes away.
            await viewModel.load()
            openDebugSelectionIfRequested()
            if DebugLaunchOptions.tracksLocation { tapLocationButton() }
            await viewModel.keepRefreshing()
        }
        .mapScope(mapScope)
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

    /// While the confirmation is showing: if a photo/video was sent, wait for
    /// the AI's answer and show it. Then hide the confirmation after a few seconds.
    private func followLastReport() async {
        guard let report = lastReport else { return }
        if let mediaID = report.mediaId {
            lastReportAnalysis = .analyzing
            if let analysis = await viewModel.waitForAnalysis(incidentID: report.incidentId, mediaID: mediaID) {
                lastReportAnalysis = .finished(analysis)
                await viewModel.load()   // if the AI confirmed it, it's on the map now
            } else {
                lastReportAnalysis = .unknown
            }
        } else {
            lastReportAnalysis = .noMedia
        }
        try? await Task.sleep(for: .seconds(7))
        guard !Task.isCancelled else { return }
        lastReport = nil
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

    /// Only one sheet can be open at a time: close a hazard or incident sheet
    /// first, then open the Live data sheet once it has slid away.
    private func openLiveData() {
        let wasShowingSheet = selectedHazard != nil || selectedIncidentID != nil
        selectedHazard = nil
        selectedIncidentID = nil
        Task {
            if wasShowingSheet { try? await Task.sleep(for: .milliseconds(450)) }
            showsLiveData = true
        }
    }

    /// Open a live hazard's sheet and fit its zones on screen above it.
    private func select(_ hazard: Hazard) {
        selectedIncidentID = nil
        if showsIncidents { setIncidents(open: false) }
        selectedHazard = hazard
        // Show the widest zone (or about 10 km for an outlined area).
        let widest = hazard.zones.compactMap(\.radiusM).max().map(Double.init) ?? 5_000
        let height = min(max(widest * 2.6 / 111_000, 0.02), 3)   // degrees of latitude on screen
        let center = CLLocationCoordinate2D(latitude: hazard.latitude - height * 0.3, longitude: hazard.longitude)
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: center, span: MKCoordinateSpan(latitudeDelta: height, longitudeDelta: 0.001)))
        }
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

    /// The Incidents button and the filter chips.
    private var topBar: some View {
        HStack(spacing: 0) {
            IncidentsButton(isOpen: showsIncidents, urgentCount: viewModel.store.needsAttentionCount) {
                setIncidents(open: !showsIncidents)
            }
            .padding(.leading, Spacing.l)
            MapFilterBar(filters: $viewModel.filters)
            SettingsButton()
                .padding(.trailing, Spacing.l)
                .environment(\.brand, Color.themeAccent)
        }
        .padding(.top, Spacing.xs)
    }

    /// "Updated ... ago" and "Live" on the left, the legend on the right.
    private var infoRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    UpdateStatusPill(
                        lastUpdated: viewModel.lastUpdated,
                        refreshError: viewModel.refreshError,
                        isRefreshing: viewModel.isRefreshing,
                        onRetry: { Task { await viewModel.load() } }
                    )
                    refreshButton
                }
                LiveDataPill(feed: viewModel.hazardFeed, hasError: viewModel.hazardError != nil) {
                    openLiveData()
                }
                myLocationButton
                if auth.me?.community?.status == .member { communityButton }
            }
            Spacer()
            MapLegend()
        }
        .padding(.horizontal, Spacing.l)
    }

    /// The incident log over the top left of the screen. A strip on the right
    /// and the bottom of the map stay visible and usable. It unrolls from the
    /// top (the panel's height grows) like an accordion.
    @ViewBuilder
    private var incidentsPanel: some View {
        if showsIncidents {
            IncidentsPanel(store: viewModel.store,
                           hazards: viewModel.visibleHazards,
                           onSelect: { show($0) },
                           onSelectHazard: { hazard in setIncidents(open: false); select(hazard) },
                           onClose: { setIncidents(open: false) })
                // Most of the screen's top left. It starts over the status
                // pills and stops just above Report incident, so the right
                // strip and the bottom of the map stay visible and usable.
                // (mapSize is the map below the top bar.)
                .frame(width: max(mapSize.width - Spacing.l * 2 - 56, 280),
                       height: max(min(mapSize.height, 680), 320))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                .padding(.leading, Spacing.l)
                .transition(reduceMotion ? .opacity : Accordion.reveal)
        }
    }

    private func setIncidents(open: Bool) {
        if open {
            // One thing at a time: close any open sheet first.
            selectedIncidentID = nil
            selectedHazard = nil
        }
        withAnimation(reduceMotion ? nil : Accordion.motion) { showsIncidents = open }
    }

    /// From the incident log: fold it up, then fly to the incident and open it.
    private func show(_ incident: IncidentSummary) {
        setIncidents(open: false)
        if !viewModel.filters.matches(incident) { viewModel.clearFilters() }   // make sure it's on the map
        selectedIncidentID = incident.id
    }

    /// The main action on the map.
    private var reportButton: some View {
        Button {
            selectedIncidentID = nil
            selectedHazard = nil
            if showsIncidents { setIncidents(open: false) }
            lastReport = nil
            isReporting = true
        } label: {
            Label("Report incident", systemImage: "exclamationmark.bubble.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .frame(minHeight: 52)
                .background(Color.themeAccent, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a form to report an emergency")
        .accessibilityIdentifier("reportIncidentButton")  // lets automated UI tests find it
    }

    /// + and − buttons (pinching also works; in the simulator, hold Option and drag).
    private var zoomButtons: some View {
        VStack(spacing: 0) {
            zoomButton(systemImage: "plus", label: "Zoom in", factor: 0.5)
            Divider().frame(width: 28)
            zoomButton(systemImage: "minus", label: "Zoom out", factor: 2)
        }
        .floatingSurface(cornerRadius: 24)
    }

    private func zoomButton(systemImage: String, label: String, factor: Double) -> some View {
        Button {
            zoom(by: factor)
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.themeAccent)
        .accessibilityLabel(label)
        .accessibilityIdentifier(factor < 1 ? "zoomInButton" : "zoomOutButton")
    }

    /// factor 0.5 = show half as much (zoom in), 2 = show twice as much (zoom out).
    private func zoom(by factor: Double) {
        let span = MKCoordinateSpan(
            latitudeDelta: min(max(visibleRegion.span.latitudeDelta * factor, 0.002), 30),
            longitudeDelta: min(max(visibleRegion.span.longitudeDelta * factor, 0.002), 30))
        let region = MKCoordinateRegion(center: visibleRegion.center, span: span)
        visibleRegion = region  // so tapping several times in a row keeps zooming
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(region)
        }
    }

    /// About a quarter mile around a home: close enough for the picture bubbles.
    private var isZoomedInClose: Bool { visibleRegion.span.latitudeDelta < 0.012 }

    /// Shows or hides your community's homes on the map.
    private var communityButton: some View {
        Button {
            Task { await toggleCommunity() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "house.and.flag.fill")
                Text(showsCommunity ? "Hide my community" : "My community")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(showsCommunity ? Color.white : Color.themeAccent)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background { if showsCommunity { Capsule().fill(Color.themeAccent) } }
            .floatingSurface(cornerRadius: 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -8)
        .accessibilityHint("Shows where your neighbors live")
        .accessibilityIdentifier("myCommunityOnMap")
    }

    private func toggleCommunity() async {
        if showsCommunity {
            withAnimation { showsCommunity = false }
            return
        }
        guard let id = auth.me?.community?.id else { return }
        homes = (try? await APIClient.shared.fetchCommunityHomes(communityID: id)) ?? []
        withAnimation { showsCommunity = true }
        // Fit everyone's home on screen.
        guard !homes.isEmpty else { return }
        let lats = homes.map(\.latitude), lons = homes.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.01),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.01))
        withAnimation(.easeInOut(duration: 0.6)) { cameraPosition = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// "Use my location", like the location button in Google Maps:
    ///   first tap   asks for permission (the iPhone's own popup), then
    ///               shows the blue dot and follows you
    ///   next tap    compass mode: the map turns with you
    ///   next tap    back to north up, still following you
    private var myLocationButton: some View {
        Button(action: tapLocationButton) {
            HStack(spacing: 6) {
                if tracking.follows && live.location == nil {
                    ProgressView().controlSize(.mini)   // waiting for the first GPS fix
                } else {
                    Image(systemName: tracking.symbol)
                }
                Text(tracking.title)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tracking == .off ? Color.themeAccent : Color.white)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background {
                if tracking != .off { Capsule().fill(Color.themeAccent) }
            }
            .floatingSurface(cornerRadius: 14)
            .padding(.vertical, 8)   // a 44 pt tap area without a bigger pill
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -8)
        .accessibilityHint(tracking == .off ? "Shows where you are on the map" : "Changes how the map follows you")
        .accessibilityIdentifier("useMyLocationOnMap")
        .animation(.snappy(duration: 0.2), value: tracking)
    }

    private func tapLocationButton() {
        if live.isDenied {
            locationProblem = .denied
            return
        }
        if showsIncidents { setIncidents(open: false) }
        if !live.isRunning { live.start() }
        let next: Tracking = switch tracking {
        case .off, .shown: .following
        case .following: live.heading == nil ? .following : .compass   // no compass in the simulator
        case .compass: .following
        }
        tracking = next
        // The first time, zoom in to your neighborhood (about 4 km across).
        if next == .following && tracking != .compass && cameraDistance > 12_000 { cameraDistance = 6_000 }
        moveCameraToUser(animated: true)
    }

    /// Center the map on you. Compass mode also turns it the way you face.
    private func moveCameraToUser(animated: Bool) {
        guard let here = live.location else { return }   // it moves once the first GPS fix arrives
        let camera = MapCamera(centerCoordinate: here.coordinate,
                               distance: cameraDistance > 0 ? min(cameraDistance, 12_000) : 6_000,
                               heading: tracking == .compass ? (live.heading ?? 0) : 0)
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) { cameraPosition = .camera(camera) }
        } else {
            cameraPosition = .camera(camera)
        }
    }

    /// Asks NASA, NOAA and the Weather Service again right now (new fires,
    /// ended alerts), plus the latest community reports.
    private var refreshButton: some View {
        Button {
            Task { await viewModel.refreshEverything() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .rotationEffect(.degrees(viewModel.isRefreshingAll ? 360 : 0))
                .animation(viewModel.isRefreshingAll ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                           value: viewModel.isRefreshingAll)
                .foregroundStyle(Color.themeAccent)
                .frame(width: 28, height: 28)
                .floatingSurface(cornerRadius: 14)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-8)
        .disabled(viewModel.isRefreshingAll)
        .accessibilityLabel("Refresh the map")
        .accessibilityHint("Checks for new fires, alerts and reports")
        .accessibilityIdentifier("refreshMap")
    }

    /// The closest danger to you, if you're near one (fires, storms, floods;
    /// never injuries). Tap it to see the hazard, or close it.
    private var nearbyDanger: NearbyDanger? {
        guard tracking != .off, let here = live.location else { return nil }
        return NearbyDanger.closest(to: here, hazards: viewModel.hazardFeed?.hazards ?? [],
                                    incidents: viewModel.incidents)
    }

    @ViewBuilder
    private var nearbyWarning: some View {
        if let danger = nearbyDanger, danger.id != dismissedDangerID {
            NearbyDangerBanner(danger: danger) {
                switch danger.source {
                case .hazard(let hazard): select(hazard)
                case .incident(let incident): show(incident)
                }
            } onClose: {
                withAnimation(.snappy) { dismissedDangerID = danger.id }
            }
            .padding(.horizontal, Spacing.l)
            .transition(.move(edge: .top).combined(with: .opacity))
            .sensoryFeedback(.warning, trigger: danger.id)
        }
    }

    /// Tells notifications and the Lock Screen status what's around you.
    private func reportSurroundings() {
        guard tracking != .off, live.location != nil else { return }
        AlertsManager.shared.update(danger: nearbyDanger,
                                    place: auth.me?.community?.city ?? String(localized: "North Texas"))
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
        .foregroundStyle(Color.themeAccent)
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
                LoadingLogo(size: 32)
                Text("Loading incidents…")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .floatingSurface(cornerRadius: Radius.panel)

        case .failed(let error):
            MessageCard(error: error, isWorking: viewModel.isRefreshing,
                        action: { Task { await viewModel.retry() } })
            .padding(Spacing.l)

        case .loaded:
            if !viewModel.visibleHazards.isEmpty {
                EmptyView()   // live data is on the map, so it isn't empty
            } else if viewModel.incidents.isEmpty {
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

/// How the map follows the user (see myLocationButton).
private enum Tracking {
    case off, shown, following, compass

    var follows: Bool { self == .following || self == .compass }

    var title: LocalizedStringKey {
        switch self {
        case .off: "Use my location"
        case .shown: "My location"
        case .following: "Following you"
        case .compass: "Compass mode"
        }
    }

    var symbol: String {
        switch self {
        case .off: "location"
        case .shown: "location"
        case .following: "location.fill"
        case .compass: "location.north.line.fill"
        }
    }
}

/// Why "Use my location" didn't work, and what to tell the user.
private enum LocationProblem: Identifiable {
    case denied, notFound

    var id: Self { self }

    var alert: Alert {
        switch self {
        case .denied:
            Alert(title: Text("Location is turned off for RollCall"),
                  message: Text("To see where you are on the map, open Settings and allow location access for RollCall."),
                  primaryButton: .default(Text("Open Settings")) {
                      if let url = URL(string: UIApplication.openSettingsURLString) {
                          UIApplication.shared.open(url)
                      }
                  },
                  secondaryButton: .cancel(Text("Not now")))
        case .notFound:
            Alert(title: Text("Couldn't find your location"),
                  message: Text("Check that Location Services is on, then try again."),
                  dismissButton: .default(Text("OK")))
        }
    }
}

#Preview {
    IncidentMapView(store: IncidentStore())
}
