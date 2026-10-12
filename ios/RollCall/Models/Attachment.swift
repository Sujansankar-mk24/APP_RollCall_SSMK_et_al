//
//  ReportSubmission.swift
//  RollCall
//
//  A photo or video someone attaches (used by check-ins: "I need help" can
//  include a picture of the situation).
//

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
