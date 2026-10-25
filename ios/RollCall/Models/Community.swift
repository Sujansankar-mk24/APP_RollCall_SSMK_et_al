//
//  Community.swift
//  RollCall
//
//  Neighborhood communities (matches CommunityOut and CommunityDetailOut in
//  backend/app/schemas.py).
//

import Foundation

struct CommunitySummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let city: String
    let photoUrl: String?
    let memberCount: Int
    let myStatus: MemberStatus?   // nil if you haven't asked to join
    let isAdmin: Bool

    var photoURL: URL? { AppConfig.mediaURL(photoUrl) }
}

struct CommunityDetail: Decodable, Equatable {
    let id: Int
    let name: String
    let city: String
    let photoUrl: String?
    let memberCount: Int
    let myStatus: MemberStatus?
    let isAdmin: Bool
    let members: [CommunityMember]       // only filled in for members
    let buddyPairs: [BuddyPair]          // who checks on whom (only for members)
    let joinRequests: [CommunityMember]  // only filled in for the admin
    let recap: [RecapPhoto]              // the Weekly Recap: anyone can see it
    let pendingPhotos: [RecapPhoto]      // only filled in for the admin

    var photoURL: URL? { AppConfig.mediaURL(photoUrl) }
}

/// One photo in a community's Weekly Recap.
struct RecapPhoto: Decodable, Identifiable, Hashable {
    let id: Int
    let url: String
    let caption: String
    let uploaderName: String
    let status: String
    let pinned: Bool
    let createdAt: Date
    let expiresAt: Date?   // nil when the admin pinned it

    var imageURL: URL? { AppConfig.mediaURL(url) }
}

struct CommunityMember: Decodable, Identifiable, Hashable {
    let userId: Int
    let name: String
    let isAdmin: Bool
    let since: Date
    let photoUrl: String?
    let awayFromHome: Bool
    let hasBuddy: Bool
    let isVolunteer: Bool
    let wantsBuddy: Bool

    var id: Int { userId }
    var photoURL: URL? { AppConfig.mediaURL(photoUrl) }
}

/// Volunteer X checks on resident Y (user ids, both in the community).
struct BuddyPair: Decodable, Hashable {
    let volunteerId: Int
    let residentId: Int
}
