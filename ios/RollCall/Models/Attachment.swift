//
//  Attachment.swift
//  RollCall
//
//  A photo or video someone attaches to an incident report, plus what the
//  app sends when someone reports an incident and what the server answers
//  (matches ReportCreatedOut in backend/app/schemas.py).
//

import CoreLocation
import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

/// A photo or video, ready to upload.
enum Attachment {
    case photo(jpeg: Data, preview: UIImage)
    case video(file: URL, preview: UIImage?)

    var preview: UIImage? {
        switch self {
        case .photo(_, let preview): preview
        case .video(_, let preview): preview
        }
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

struct ReportSubmission {
    let type: IncidentType
    let coordinate: CLLocationCoordinate2D
    let description: String
    let locationName: String
    let attachment: Attachment?
}

/// The server's answer after a report is saved.
struct ReportCreated: Decodable, Equatable {
    let incidentId: Int
    let reportId: Int
    let mediaId: Int?
    let merged: Bool        // true if it joined an existing incident
    let reportCount: Int
    let message: String     // e.g. "Added to existing incident (3 reports)"
}

/// Lets PhotosPicker hand us a video as a file. Videos can be large, so
/// instead of loading them into memory we copy the file somewhere we own.
/// (nonisolated: the Photos framework may call this from a background thread.)
nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
