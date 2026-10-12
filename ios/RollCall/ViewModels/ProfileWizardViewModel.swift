//
//  ProfileWizardViewModel.swift
//  RollCall
//
//  Holds everything typed and picked while a resident sets up (or edits)
//  their household, one step at a time, and saves it.
//

import CoreLocation
import MapKit
import Observation
import SwiftUI

@Observable
final class ProfileWizardViewModel {

    enum Mode: Equatable {
        case register                    // a new household opting in
        case edit(householdID: Int)      // changing an existing profile
    }

    /// The five steps, in order.
    enum Step: Int, CaseIterable {
        case home, people, needs, contact, review
    }

    let mode: Mode
    var input: HouseholdInput
    private(set) var step: Step = .home
    var consent: Bool

    // Location
    var mapPosition: MapCameraPosition
    private(set) var hasPin: Bool
    private(set) var isLocating = false
    private(set) var locationNote: String?

    // Saving
    private(set) var isSaving = false
    var saveError: APIError?

    private let api: APIClient
    private let viewer: Viewer?
    private let locationProvider = LocationProvider()
    private var addressLookup: Task<Void, Never>?

    init(mode: Mode, existing: Household? = nil, viewer: Viewer? = nil, api: APIClient = .shared) {
        self.mode = mode
        self.viewer = viewer
        self.api = api
        input = existing.map(HouseholdInput.init) ?? HouseholdInput()
        hasPin = existing != nil
        consent = existing != nil   // they agreed when they first registered
        let center = existing?.coordinate ?? AppConfig.homeRegion.center
        mapPosition = .region(MKCoordinateRegion(
            center: center,
            span: existing == nil ? MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                                  : MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: input.latitude, longitude: input.longitude)
    }

    // MARK: - Moving between steps

    /// Can the person go on to the next step? (Only what's truly required is checked.)
    var canContinue: Bool {
        switch step {
        case .home:
            return !input.contactName.trimmed.isEmpty && !input.address.trimmed.isEmpty && hasPin
        case .people:
            return input.people >= 1
        case .review:
            return consent && !isSaving
        default:
            return true
        }
    }

    /// Why the Next button is greyed out, in plain words.
    var whatsMissing: LocalizedStringResource? {
        switch step {
        case .home where input.contactName.trimmed.isEmpty: "Add your name to continue."
        case .home where !hasPin || input.address.trimmed.isEmpty: "Set your home's location to continue."
        case .people where input.people < 1: "Add at least one person."
        default: nil
        }
    }

    var isLastStep: Bool { step == .review }

    func goNext() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    // MARK: - Location

    /// Put the pin on the phone's current location and fill in the address.
    func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        guard let location = await locationProvider.currentLocation() else {
            locationNote = String(localized: "Couldn't get your location. Search for your address instead.")
            return
        }
        // RollCall covers North Texas; a location far away (like the
        // simulator's default spot in California) would be wrong.
        let center = CLLocation(latitude: AppConfig.homeRegion.center.latitude, longitude: AppConfig.homeRegion.center.longitude)
        if location.distance(from: center) > 250_000 {
            locationNote = String(localized: "Your location is outside North Texas. Search for your address instead.")
            return
        }
        locationNote = nil
        place(at: location.coordinate, zoom: true)
        await fillAddress(for: location.coordinate)
    }

    /// The person picked an address from the search suggestions.
    func usePlace(_ place: AddressSearch.Place) {
        locationNote = nil
        self.place(at: place.coordinate, zoom: true)
        addressLookup?.cancel()
        addressLookup = Task { await fillAddress(for: place.coordinate) }
    }

    /// The pin was dragged (or the map tapped).
    func movePin(to coordinate: CLLocationCoordinate2D) {
        place(at: coordinate, zoom: false)
        addressLookup?.cancel()
        addressLookup = Task {
            try? await Task.sleep(for: .milliseconds(400))   // wait until the pin stops moving
            guard !Task.isCancelled else { return }
            await fillAddress(for: coordinate)
        }
    }

    private func place(at coordinate: CLLocationCoordinate2D, zoom: Bool) {
        input.latitude = coordinate.latitude
        input.longitude = coordinate.longitude
        hasPin = true
        if zoom {
            withAnimation(.easeInOut) {
                mapPosition = .region(MKCoordinateRegion(center: coordinate,
                                                         span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            }
        }
    }

    private func fillAddress(for coordinate: CLLocationCoordinate2D) async {
        guard let found = await locationProvider.address(for: coordinate) else { return }
        input.address = found.street
        input.city = found.city
    }

    // MARK: - Needs

    func toggle(_ item: MedicalEquipment) {
        if let index = input.medicalEquipment.firstIndex(of: item) {
            input.medicalEquipment.remove(at: index)
        } else {
            input.medicalEquipment.append(item)
        }
    }

    // MARK: - Saving

    /// Save the profile. Returns the saved household, or nil if it failed
    /// (saveError then says why, and everything typed is kept).
    func save() async -> Household? {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        var clean = input
        clean.contactName = clean.contactName.trimmed
        clean.address = clean.address.trimmed
        do {
            switch mode {
            case .register:
                return try await api.registerHousehold(clean)
            case .edit(let id):
                guard let viewer else { return nil }
                return try await api.updateHousehold(id: id, clean, as: viewer)
            }
        } catch {
            saveError = error
            return nil
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
