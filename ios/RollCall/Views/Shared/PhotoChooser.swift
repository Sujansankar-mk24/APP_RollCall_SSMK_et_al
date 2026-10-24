//
//  PhotoChooser.swift
//  RollCall
//
//  "Take a photo" or "Choose from library", in one menu, for profile
//  pictures, ID photos, community pictures and Weekly Recap photos. It hands
//  back a JPEG, shrunk so uploads are quick.
//

import PhotosUI
import SwiftUI

struct PhotoChooser<Label: View>: View {
    let onPicked: (Data) -> Void
    @ViewBuilder let label: Label

    @State private var pickedItem: PhotosPickerItem?
    @State private var showsLibrary = false
    @State private var showsCamera = false

    var body: some View {
        Menu {
            if CameraCapture.isAvailable {
                Button("Take a photo", systemImage: "camera") { showsCamera = true }
            }
            Button("Choose from library", systemImage: "photo.on.rectangle") { showsLibrary = true }
        } label: {
            label
        }
        .photosPicker(isPresented: $showsLibrary, selection: $pickedItem,
                      matching: .all(of: [.images, .not(.screenshots)]))
        .onChange(of: pickedItem) {
            guard let item = pickedItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data), let jpeg = Self.jpeg(from: image) {
                    onPicked(jpeg)
                }
                pickedItem = nil
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCapture { capture in
                if case .photo(let image) = capture, let jpeg = Self.jpeg(from: image) { onPicked(jpeg) }
            }
            .ignoresSafeArea()
        }
    }

    /// At most 1600 pixels on the long side, as a JPEG.
    static func jpeg(from image: UIImage) -> Data? {
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return (image.preparingThumbnail(of: size) ?? image).jpegData(compressionQuality: 0.85)
    }
}
