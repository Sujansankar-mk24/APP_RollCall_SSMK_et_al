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
}
