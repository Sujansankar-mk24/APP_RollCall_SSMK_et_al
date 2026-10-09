//
//  APIError.swift
//  RescueSight
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

    var title: String {
        switch self {
        case .serverUnreachable: "Can't reach RescueSight"
        case .badResponse: "Something went wrong"
        case .unreadableResponse: "Something went wrong"
        case .unreadableAttachment: "Couldn't read the video"
        }
    }

    var message: String {
        switch self {
        case .serverUnreachable:
            "The incident server isn't responding. Make sure the backend is running on this Mac, then try again."
        case .badResponse(let statusCode):
            "The server returned an error (code \(statusCode)). Try again in a moment."
        case .unreadableResponse:
            "The server sent data this version of the app doesn't understand."
        case .unreadableAttachment:
            "Remove the video and choose it again, then try sending."
        }
    }
}
