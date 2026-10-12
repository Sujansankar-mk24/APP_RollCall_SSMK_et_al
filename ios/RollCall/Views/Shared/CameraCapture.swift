//
//  CameraCapture.swift
//  RollCall
//
//  Opens the iPhone camera to take a photo or record a short video (up to
//  30 seconds) right from the report form. SwiftUI has no camera view of
//  its own, so this wraps UIKit's UIImagePickerController.
//
//  The iPhone simulator has no camera, so the form hides this button there
//  and you choose from the photo library instead.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CameraCapture: UIViewControllerRepresentable {
    /// What the camera produced.
    enum Result {
        case photo(UIImage)
        case video(URL)
    }

    let onCapture: (Result) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = 30
        picker.videoQuality = .typeMedium  // smaller files upload faster
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Receives the camera's result (UIKit uses a "delegate" object for this).
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture

        init(parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(.photo(image))
            } else if let recorded = info[.mediaURL] as? URL {
                // The camera's file is temporary; copy it somewhere we control.
                let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
                if (try? FileManager.default.copyItem(at: recorded, to: copy)) != nil {
                    parent.onCapture(.video(copy))
                }
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
