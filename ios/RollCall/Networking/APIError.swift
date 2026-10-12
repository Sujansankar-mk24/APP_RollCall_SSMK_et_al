//
//  APIError.swift
//  RollCall
//
//  Everything that can go wrong when talking to the server, written so it
//  can be shown to a person (not just a programmer).
//

import Foundation

enum APIError: Error, Equatable {
    /// The server couldn't be reached at all (not running, wrong address, no network).
    case serverUnreachable
    /// The server answered, but with an error code (like 404 or 500).
    case badResponse(statusCode: Int)
    /// The server's answer wasn't in the shape the app expected.
    case unreadableResponse
    /// The app couldn't read the photo/video it was about to upload.
    case unreadableAttachment
    /// The privacy rules don't allow this person to see it (the server says why).
    case notShared(String)
    /// It doesn't exist (for example, a household that was deleted).
    case notFound

    var title: LocalizedStringResource {
        switch self {
        case .serverUnreachable: "Can't reach RollCall"
        case .notShared: "Kept private"
        case .notFound: "Not found"
        case .unreadableAttachment: "Couldn't read the video"
        default: "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case .serverUnreachable:
            String(localized: "The RollCall server isn't responding. Make sure the backend is running on this Mac, then try again.")
        case .badResponse(let statusCode):
            String(localized: "The server returned an error (code \(statusCode)). Try again in a moment.")
        case .unreadableResponse:
            String(localized: "The server sent data this version of the app doesn't understand.")
        case .unreadableAttachment:
            String(localized: "Remove the video and choose it again, then try sending.")
        case .notShared(let reason):
            reason.isEmpty ? String(localized: "This information isn't shared with you.") : reason
        case .notFound:
            String(localized: "It may have been deleted.")
        }
    }
}
