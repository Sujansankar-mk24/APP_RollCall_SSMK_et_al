//
//  ReportViewModel.swift
//  RescueSight
//
//  Holds everything typed and picked in the "Report incident" form, checks
//  it's ready to send, and sends it.
//

import AVFoundation
import CoreLocation
import MapKit
import Observation
import PhotosUI
import SwiftUI

@Observable
final class ReportViewModel {

    // MARK: Form fields

    var selectedType: IncidentType?
    var description = "" {
        didSet {
            // Keep it short, like the server requires.
            if description.count > Self.maxDescriptionLength {
                description = String(description.prefix(Self.maxDescriptionLength))
            }
        }
    }
    static let maxDescriptionLength = 500

    /// Where the pin is. Starts in the middle of North Texas until we know better.
    private(set) var coordinate = AppConfig.homeRegion.center
    /// What the small map in the form is looking at.
    var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: AppConfig.homeRegion.center,
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)))
    private(set) var placeName: String?
    private(set) var isLocating = false
    private(set) var locationNote: String?

    private(set) var attachment: Attachment?
    private(set) var isLoadingAttachment = false
    private(set) var attachmentError: String?

    private(set) var isSubmitting = false
    private(set) var submitError: APIError?

    private let api: APIClient
    private let locationProvider = LocationProvider()
    private var placeLookup: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    // MARK: State checks

    var canSubmit: Bool {
        selectedType != nil && !isSubmitting && !isLoadingAttachment
    }

    /// True once the person has entered anything (used to ask before throwing it away).
    var hasChanges: Bool {
        selectedType != nil || !description.isEmpty || attachment != nil
    }

    // MARK: Location

    /// Put the pin on the phone's current location.
    func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }

        guard let location = await locationProvider.currentLocation() else {
            locationNote = locationProvider.isDenied
                ? "Location access is off. Drag the pin to where it's happening."
                : "Couldn't find your location. Drag the pin to where it's happening."
            return
        }
        locationNote = nil
        movePin(to: location.coordinate)
        withAnimation(.easeInOut) {
            mapPosition = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
        }
    }

    /// Called when the pin is dragged or the map is tapped.
    func movePin(to newCoordinate: CLLocationCoordinate2D) {
        coordinate = newCoordinate
        lookUpPlaceName()
    }

    /// Find the street/town name for the pin. If the pin keeps moving, only
    /// the last lookup matters, so earlier ones are cancelled.
    private func lookUpPlaceName() {
        placeLookup?.cancel()
        let target = coordinate
        placeLookup = Task {
            try? await Task.sleep(for: .milliseconds(400))  // wait until the pin stops moving
            guard !Task.isCancelled else { return }
            let name = await locationProvider.placeName(for: target)
            guard !Task.isCancelled else { return }
            placeName = name
        }
    }

    // MARK: Photo or video

    func loadAttachment(from item: PhotosPickerItem?) async {
        attachment = nil
        attachmentError = nil
        guard let item else { return }

        isLoadingAttachment = true
        defer { isLoadingAttachment = false }

        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    throw CocoaError(.fileReadUnknown)
                }
                attachment = .video(file: movie.url, preview: await Self.firstFrame(of: movie.url))
            } else {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw CocoaError(.fileReadUnknown)
                }
                // Shrink big phone photos (and convert HEIC to JPEG) so uploads are quick.
                let resized = image.preparingThumbnail(of: Self.fittingSize(image.size, maxSide: 2048)) ?? image
                guard let jpeg = resized.jpegData(compressionQuality: 0.85) else {
                    throw CocoaError(.fileReadUnknown)
                }
                attachment = .photo(jpeg: jpeg, preview: resized)
            }
        } catch {
            attachmentError = "Couldn't load that photo or video. Try a different one."
        }
    }

    func removeAttachment() {
        attachment = nil
        attachmentError = nil
    }

    private static func fittingSize(_ size: CGSize, maxSide: CGFloat) -> CGSize {
        let scale = min(1, maxSide / max(size.width, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// A still picture from the start of a video, for the preview.
    private static func firstFrame(of url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true  // keep portrait videos upright
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: frame)
    }

    // MARK: Sending

    /// Send the report. Returns the server's answer, or nil if it failed
    /// (submitError then explains why, and the form keeps everything entered).
    func submit() async -> ReportCreated? {
        guard let selectedType else { return nil }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let report = ReportSubmission(
            type: selectedType,
            coordinate: coordinate,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            locationName: placeName ?? "",
            attachment: attachment
        )
        do {
            return try await api.submitReport(report)
        } catch {
            submitError = error
            return nil
        }
    }
}
