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
    private(set) var isFindingAddress = false
    private(set) var locationNote: LocationNote?

    /// A short message under the map. Green when the phone's location agrees
    /// with the typed address, orange when something needs a look.
    struct LocationNote: Equatable {
        let text: String
        let isGood: Bool
    }

    // Saving
    private(set) var isSaving = false
    var saveError: APIError?

    private let api: APIClient
    private let locationProvider = LocationProvider()
    private var addressLookup: Task<Void, Never>?

    init(mode: Mode, existing: Household? = nil, name: String = "", api: APIClient = .shared) {
        self.mode = mode
        self.api = api
        var start = existing.map(HouseholdInput.init) ?? HouseholdInput()
        if existing == nil { start.contactName = name }   // start with the account's name
        input = start
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
            return !input.contactName.trimmed.isEmpty && hasFullAddress && hasPin
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
        case .home where !hasFullAddress: "Type your street, town and 5-digit ZIP code."
        case .home where !hasPin: "Put the pin on your home to continue."
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

    // MARK: - Address and location
    //
    // The resident TYPES their address (street, town, ZIP). The app then finds
    // it on the map by itself, and the phone's GPS can double-check it. The pin
    // can be dragged if it's slightly off.

    var hasFullAddress: Bool {
        !input.address.trimmed.isEmpty && !input.city.trimmed.isEmpty && input.zipCode.trimmed.count == 5
            && input.zipCode.trimmed.allSatisfy(\.isNumber)
    }

    /// Changes whenever any part of the address changes (the view watches it).
    var addressText: String { "\(input.address)|\(input.city)|\(input.zipCode)" }

    /// The address was edited: look it up on the map once typing pauses.
    func addressChanged() {
        addressLookup?.cancel()
        guard hasFullAddress else { return }
        addressLookup = Task {
            try? await Task.sleep(for: .milliseconds(700))   // wait until typing stops
            guard !Task.isCancelled else { return }
            await findTypedAddress()
        }
    }

    private func findTypedAddress() async {
        isFindingAddress = true
        defer { isFindingAddress = false }
        let full = "\(input.address.trimmed), \(input.city.trimmed), TX \(input.zipCode.trimmed)"
        guard let found = await locationProvider.coordinate(forAddress: full) else {
            locationNote = LocationNote(text: String(localized: "Couldn't find that address on the map. Check it, or move the pin yourself."), isGood: false)
            return
        }
        place(at: found, zoom: true)
        locationNote = nil
    }

    /// The location button: if no address is typed yet, fill it in from GPS
    /// (the resident can still edit it). If one is typed, check that the phone
    /// is actually near it.
    func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        guard let location = await locationProvider.currentLocation() else {
            locationNote = LocationNote(text: String(localized: "Couldn't get your location. Type your address instead."), isGood: false)
            return
        }
        // RollCall covers North Texas; a location far away (like the
        // simulator's default spot in California) would be wrong.
        let center = CLLocation(latitude: AppConfig.homeRegion.center.latitude, longitude: AppConfig.homeRegion.center.longitude)
        if location.distance(from: center) > 250_000 {
            locationNote = LocationNote(text: String(localized: "Your location is outside North Texas. Type your address instead."), isGood: false)
            return
        }
        if hasPin && hasFullAddress {
            let pin = CLLocation(latitude: input.latitude, longitude: input.longitude)
            let meters = location.distance(from: pin)
            locationNote = meters < 300
                ? LocationNote(text: String(localized: "Your phone's location matches this address."), isGood: true)
                : LocationNote(text: String(localized: "Your phone is \(Self.distanceText(meters)) from this address. That's fine if you're not home right now."), isGood: false)
            return
        }
        place(at: location.coordinate, zoom: true)
        if let found = await locationProvider.postalAddress(for: location.coordinate) {
            input.address = found.street
            input.city = found.city
            input.zipCode = found.zip
        }
        locationNote = LocationNote(text: String(localized: "Filled in from your location. Check that it's right."), isGood: true)
    }

    /// The pin was dragged (or the map tapped). The typed address stays as it is.
    func movePin(to coordinate: CLLocationCoordinate2D) {
        addressLookup?.cancel()
        place(at: coordinate, zoom: false)
        locationNote = nil
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

    private static func distanceText(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles)
            .formatted(.measurement(width: .abbreviated, usage: .road))
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
        clean.city = clean.city.trimmed
        clean.zipCode = clean.zipCode.trimmed
        do {
            switch mode {
            case .register:
                return try await api.registerHousehold(clean)
            case .edit(let id):
                return try await api.updateHousehold(id: id, clean)
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
