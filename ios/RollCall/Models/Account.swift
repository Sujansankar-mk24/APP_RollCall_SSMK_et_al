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
    /// Can you offer to be their buddy? See BuddyOffer.
    var buddyOffer: BuddyOffer = .none
    /// Their buddy connections in your community, for the bubble web.
    var connections: [CommunityMember] = []
    var connectionPairs: [BuddyPair] = []

    var photoURL: URL? { AppConfig.mediaURL(photoUrl) }

    /// "Be their buddy" on a profile: only for someone in your community who
    /// joined the roll call.
    enum BuddyOffer: String, Decodable, Hashable {
        case none, canOffer = "can_offer", asked, checkingOn = "checking_on"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, photoUrl, bio, memberSince, communityId, communityName, isCommunityAdmin, awayFromHome,
             isVolunteer, wantsBuddy, hasBuddy, isMyBuddy, responder, address, phone, buddyOffer, connections,
             connectionPairs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        bio = try c.decode(String.self, forKey: .bio)
        memberSince = try c.decode(Date.self, forKey: .memberSince)
        communityId = try c.decodeIfPresent(Int.self, forKey: .communityId)
        communityName = try c.decodeIfPresent(String.self, forKey: .communityName)
        isCommunityAdmin = try c.decode(Bool.self, forKey: .isCommunityAdmin)
        awayFromHome = try c.decode(Bool.self, forKey: .awayFromHome)
        isVolunteer = try c.decode(Bool.self, forKey: .isVolunteer)
        wantsBuddy = try c.decode(Bool.self, forKey: .wantsBuddy)
        hasBuddy = try c.decode(Bool.self, forKey: .hasBuddy)
        isMyBuddy = try c.decode(Bool.self, forKey: .isMyBuddy)
        responder = try c.decodeIfPresent(ResponderInfo.self, forKey: .responder)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        // Older servers don't send these, so they're optional here.
        buddyOffer = (try? c.decodeIfPresent(BuddyOffer.self, forKey: .buddyOffer)) ?? .none
        connections = (try? c.decodeIfPresent([CommunityMember].self, forKey: .connections)) ?? []
        connectionPairs = (try? c.decodeIfPresent([BuddyPair].self, forKey: .connectionPairs)) ?? []
    }
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
