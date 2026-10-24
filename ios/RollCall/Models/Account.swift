//
//  Account.swift
//  RollCall
//
//  The signed-in person, as the server describes them (matches MeOut and
//  AuthOut in backend/app/schemas.py).
//

import Foundation

struct Me: Decodable, Equatable {
    let id: Int
    let name: String
    let email: String
    let isResponder: Bool
    let rollCallOptOut: Bool        // chose "Not now" for the roll call
    let householdId: Int?           // their household, if they joined the roll call
    let isVolunteer: Bool           // agreed to check on neighbors
    let community: MyCommunity?
    let isDemo: Bool
    // Profile
    let bio: String
    let photoUrl: String?
    let phone: String
    let awayFromHome: Bool
    // First responder application
    let responderStatus: ResponderStatus
    let responderAgency: String
    let responderRole: String
    let responderCity: String

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var photoURL: URL? { AppConfig.mediaURL(photoUrl) }
}

/// Where someone's first responder application stands.
enum ResponderStatus: String, Codable {
    case none, pending, approved, rejected
}

/// Someone's profile, as you're allowed to see it (the server decides:
/// the address only for people in your community, the phone only for your buddy).
struct Person: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let photoUrl: String?
    let bio: String
    let memberSince: Date
    let communityId: Int?
    let communityName: String?
    let isCommunityAdmin: Bool
    let awayFromHome: Bool
    let isVolunteer: Bool
    let wantsBuddy: Bool
    let hasBuddy: Bool
    let isMyBuddy: Bool
    let responder: ResponderInfo?
    let address: String?
    let phone: String?

    var photoURL: URL? { AppConfig.mediaURL(photoUrl) }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

struct ResponderInfo: Decodable, Hashable {
    let agency: String
    let role: String
    let city: String
}

/// Why someone reports a first responder.
enum ResponderReportReason: String, CaseIterable, Identifiable {
    case fake, abuse, reckless, other

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .fake: "Not a real first responder"
        case .abuse: "Abusing their role"
        case .reckless: "Reckless with incidents"
        case .other: "Something else"
        }
    }
}

/// The community the person belongs to, or is asking to join.
struct MyCommunity: Decodable, Equatable {
    let id: Int
    let name: String
    let city: String
    let status: MemberStatus
    let isAdmin: Bool
}

enum MemberStatus: String, Codable {
    case pending    // asked to join; waiting for the admin
    case member
}

/// The server's answer to signing up or in.
struct AuthResponse: Decodable {
    let token: String
    let me: Me
}
