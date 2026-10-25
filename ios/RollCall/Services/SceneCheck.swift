//
//  SceneCheck.swift
//  RollCall
//
//  Looks at a report's photo right on the phone, with Apple's Vision
//  framework, and lists what the whole scene shows ("snow", "storm",
//  "fire", "bedroom", ...). The labels go to the server with the report,
//  and it only puts the report on the map if the photo shows that kind of
//  disaster (backend/app/ai/verify.py). Nothing extra leaves the phone.
//
//  It also reads the words on a first responder's ID photo (text(in:)), so
//  the server can check them against the agency, name and badge number the
//  applicant typed (backend/app/services/responder_check.py).
//

import UIKit
import Vision

enum SceneCheck {
    /// "snow:0.82,blizzard:0.41,sky:0.38", the most likely labels first.
    static func labels(for image: UIImage, limit: Int = 12) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let results = request.results else { return "" }
            return results
                .filter { $0.confidence >= 0.1 }
                .sorted { $0.confidence > $1.confidence }
                .prefix(limit)
                .map { "\($0.identifier):\(String(format: "%.2f", $0.confidence))" }
                .joined(separator: ",")
        }.value
    }

    /// Every line of text Vision can read in the picture, one per line.
    static func text(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // A phone photo may be stored sideways, so tell Vision which way is up.
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            guard (try? handler.perform([request])) != nil, let results = request.results else { return "" }
            return results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
