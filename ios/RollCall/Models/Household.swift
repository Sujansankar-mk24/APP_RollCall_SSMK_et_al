//
//  Household.swift
//  RollCall
//
//  Swift versions of the JSON the backend sends (backend/app/schemas.py).
//  "Codable" lets Swift turn JSON into these structs automatically. The
//  server uses snake_case names (contact_name); the API client converts them
//  to Swift's camelCase (contactName) for us.
//

import CoreLocation
import Foundation
import MapKit
import SwiftUI

enum HouseholdLanguage: String, Codable, CaseIterable, Identifiable {
    case en, es
    var id: Self { self }

    /// Each language is written in itself, so a Spanish speaker can find "Español".
    var nativeName: String {
        switch self {
        case .en: "English"
        case .es: "Español"
        }
    }
}

/// Powered medical equipment. If the power goes out, these people are in danger first.
enum MedicalEquipment: String, Codable, CaseIterable, Identifiable {
    case oxygen, dialysis, cpap, ventilator
    case powerWheelchair = "power_wheelchair"
    case other

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .oxygen: "Oxygen"
        case .dialysis: "Home dialysis"
        case .cpap: "CPAP"
        case .ventilator: "Ventilator"
        case .powerWheelchair: "Power wheelchair"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .oxygen: "lungs.fill"
        case .dialysis: "drop.fill"
        case .cpap: "bed.double.fill"
        case .ventilator: "wind"
        case .powerWheelchair: "bolt.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct Buddy: Codable, Hashable {
    let id: Int
    let name: String
    let phone: String
    let city: String
}

struct Household: Codable, Identifiable, Hashable {
    let id: Int
    let contactName: String
    let phone: String
    let address: String
    let city: String
    let zipCode: String
    let latitude: Double
    let longitude: Double
    let children: Int
    let adults: Int
    let seniors: Int
    let people: Int
    let livesAlone: Bool
    let mobilityNeeds: Bool
    let medicalEquipment: [MedicalEquipment]
    let noVehicle: Bool
    let pets: Bool
    let livestock: Bool
    let language: HouseholdLanguage
    let notes: String
    let emergencyContactName: String
    let emergencyContactPhone: String
    let wantsBuddy: Bool
    let buddy: Buddy?
    let isDemo: Bool
    let createdAt: Date
    let updatedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var firstName: String {
        contactName.split(separator: " ").first.map(String.init) ?? contactName
    }

    /// The chips shown on cards: who lives here and what help they might need.
    var tags: [NeedTag] {
        var tags: [NeedTag] = []
        tags.append(NeedTag(people == 1 ? "1 person" : "\(people) people", symbol: "person.2.fill", tint: .secondary))
        if livesAlone { tags.append(NeedTag("Lives alone", symbol: "person.fill", tint: .orange)) }
        if seniors > 0 { tags.append(NeedTag("65+", symbol: "figure.walk", tint: .orange)) }
        if children > 0 { tags.append(NeedTag(children == 1 ? "1 child" : "\(children) children", symbol: "figure.child", tint: .orange)) }
        for item in medicalEquipment {
            tags.append(NeedTag(item.title, symbol: item.symbol, tint: .red))
        }
        if mobilityNeeds { tags.append(NeedTag("Mobility needs", symbol: "figure.roll", tint: .red)) }
        if noVehicle { tags.append(NeedTag("No vehicle", symbol: "car.side.fill", tint: .orange)) }
        if pets { tags.append(NeedTag("Pets", symbol: "pawprint.fill", tint: .secondary)) }
        if livestock { tags.append(NeedTag("Livestock", symbol: "hare.fill", tint: .secondary)) }
        if language == .es { tags.append(NeedTag("Español", symbol: "globe", tint: .accentColor)) }
        return tags
    }
}

/// One chip: some text, an icon, and the icon's color.
struct NeedTag: Identifiable, Hashable {
    let text: String
    let symbol: String
    let tint: Color
    var id: String { text }

    /// Text that gets translated (the normal case).
    init(_ text: LocalizedStringResource, symbol: String, tint: Color) {
        self.init(verbatim: String(localized: text), symbol: symbol, tint: tint)
    }

    /// Text shown exactly as written (for example "Español").
    init(verbatim text: String, symbol: String, tint: Color) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }
}

/// What the resident fills in (sent to create or update a profile).
struct HouseholdInput: Codable, Equatable {
    var contactName = ""
    var phone = ""
    var address = ""
    var city = ""
    var zipCode = ""
    var latitude = AppConfig.homeRegion.center.latitude
    var longitude = AppConfig.homeRegion.center.longitude
    var children = 0
    var adults = 1
    var seniors = 0
    var mobilityNeeds = false
    var medicalEquipment: [MedicalEquipment] = []
    var noVehicle = false
    var pets = false
    var livestock = false
    var language: HouseholdLanguage = .en
    var notes = ""
    var emergencyContactName = ""
    var emergencyContactPhone = ""
    var wantsBuddy = false

    var people: Int { children + adults + seniors }

    init() {}

    /// Start editing from an existing profile.
    init(_ h: Household) {
        contactName = h.contactName; phone = h.phone; address = h.address; city = h.city; zipCode = h.zipCode
        latitude = h.latitude; longitude = h.longitude
        children = h.children; adults = h.adults; seniors = h.seniors
        mobilityNeeds = h.mobilityNeeds; medicalEquipment = h.medicalEquipment
        noVehicle = h.noVehicle; pets = h.pets; livestock = h.livestock
        language = h.language; notes = h.notes
        emergencyContactName = h.emergencyContactName; emergencyContactPhone = h.emergencyContactPhone
        wantsBuddy = h.wantsBuddy
    }
}
