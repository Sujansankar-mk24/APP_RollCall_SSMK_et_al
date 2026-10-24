//
//  ReportViewModel.swift
//  RollCall
//
//  Holds everything typed and picked in the "Report incident" form, checks
//  it's ready to send, and sends it.
//

import AVFoundation
import CoreLocation
import ImageIO
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

    /// Every report needs a type, a photo and a short description, so
    /// responders can trust it and the AI can check it.
    var canSubmit: Bool {
        selectedType != nil && attachment != nil && hasEnoughDescription && !isSubmitting && !isLoadingAttachment
    }

    static let minDescriptionLength = 10
    var hasEnoughDescription: Bool {
        description.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minDescriptionLength
    }

    /// What's still needed before sending, shown under the button.
    var whatsMissing: String? {
        if selectedType == nil { return String(localized: "Choose what's happening.") }
        if attachment == nil { return String(localized: "Add a photo of it.") }
        if !hasEnoughDescription { return String(localized: "Describe what you see in a few words.") }
        return nil
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
                ? "Location access is off. Search for an address or drag the pin."
                : "Couldn't find your location. Search for an address or drag the pin."
            return
        }

        // RollCall covers North Texas. A location far away (like the
        // simulator's default spot in California) would put the report in the
        // wrong state, so leave the pin where it is and explain.
        let center = CLLocation(latitude: AppConfig.homeRegion.center.latitude,
                                longitude: AppConfig.homeRegion.center.longitude)
        if location.distance(from: center) > Self.serviceAreaRadius {
            locationNote = "Your location is outside North Texas. Search for an address or drag the pin. (In the simulator, set a location with Features > Location.)"
            return
        }

        locationNote = nil
        movePin(to: location.coordinate)
        zoomMap(to: location.coordinate)
    }

    /// The address search couldn't find the exact spot of a suggestion.
    func reportLocationLookupFailed() {
        locationNote = "Couldn't find that place. Try another suggestion, or drag the pin to the spot."
    }

    /// How far from the middle of North Texas a report can be (250 km).
    static let serviceAreaRadius: CLLocationDistance = 250_000

    /// Put the pin on a place picked from the address search.
    func usePlace(_ place: AddressSearch.Place) {
        placeLookup?.cancel()
        coordinate = place.coordinate
        placeName = place.name
        locationNote = nil
        zoomMap(to: place.coordinate)
    }

    private func zoomMap(to coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut) {
            mapPosition = .region(MKCoordinateRegion(
                center: coordinate,
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
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw CocoaError(.fileReadUnknown)
            }
            // Only real, recent photos: not screenshots, downloads or old pictures.
            if let problem = Self.photoProblem(in: data) {
                attachmentError = problem
                return
            }
            guard let photo = Self.photoAttachment(from: image) else { throw CocoaError(.fileReadUnknown) }
            attachment = photo
        } catch {
            attachmentError = String(localized: "Couldn't load that photo. Try a different one.")
        }
    }

    /// A photo or video just taken with the camera.
    func useCapture(_ capture: CameraCapture.Result) async {
        attachmentError = nil
        switch capture {
        case .photo(let image):
            attachment = Self.photoAttachment(from: image)
        case .video(let url):
            attachment = .video(file: url, preview: await Self.firstFrame(of: url))
        }
        if attachment == nil {
            attachmentError = "Couldn't use that photo. Try taking it again."
        }
    }

    /// How old a library photo can be (2 days). Reports are about what's
    /// happening now.
    static let maxPhotoAge: TimeInterval = 2 * 24 * 60 * 60

    /// Why a picked photo can't be used, or nil if it's fine. A photo taken
    /// with a camera carries the camera's name and the time it was taken
    /// (its EXIF data). Screenshots, downloaded and saved images usually
    /// don't, so they're turned away.
    static func photoProblem(in data: Data, now: Date = .now) -> String? {
        #if DEBUG
        // The UI tests use sample photos from the internet: -RSAllowAnyPhoto YES
        if UserDefaults.standard.bool(forKey: "RSAllowAnyPhoto") { return nil }
        #endif
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return String(localized: "Couldn't read that photo. Try a different one.")
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let camera = (tiff?[kCGImagePropertyTIFFModel] as? String) ?? (exif?[kCGImagePropertyExifLensModel] as? String)
        guard camera != nil, let taken = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(exifDate) else {
            return String(localized: "That picture wasn't taken with a camera, so it can't be used. Screenshots and saved images don't count. Take a new photo, or pick one you took yourself.")
        }
        if now.timeIntervalSince(taken) > maxPhotoAge {
            return String(localized: "That photo was taken \(taken.formatted(.relative(presentation: .named))). Reports need a photo from the last 2 days.")
        }
        return nil
    }

    /// EXIF dates look like "2026:10:24 15:42:07", in the phone's local time.
    private static func exifDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    /// Shrink big phone photos (and convert HEIC to JPEG) so uploads are quick.
    private static func photoAttachment(from image: UIImage) -> Attachment? {
        let resized = image.preparingThumbnail(of: fittingSize(image.size, maxSide: 2048)) ?? image
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return .photo(jpeg: jpeg, preview: resized)
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
