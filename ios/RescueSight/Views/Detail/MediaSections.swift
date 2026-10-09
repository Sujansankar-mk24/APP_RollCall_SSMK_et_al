//
//  MediaSections.swift
//  RescueSight
//
//  Two sections of the detail sheet:
//    * Photos & videos: everything residents uploaded.
//    * Camera feed: footage from a camera source (a drone / ESP32-CAM later,
//      or a simulated feed in the demo). Empty until a camera sends something.
//

import SwiftUI

struct MediaGallerySection: View {
    let media: [MediaItem]
    let onOpen: (MediaItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: Spacing.s)]

    var body: some View {
        SectionCard(title: "Photos & videos", systemImage: "photo.on.rectangle",
                    trailingNote: media.isEmpty ? nil : "\(media.count)") {
            if media.isEmpty {
                Text("No one has added a photo or video to this incident yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.s) {
                    ForEach(media) { item in
                        MediaThumbnail(item: item) { onOpen(item) }
                    }
                }
            }
        }
    }
}

struct CameraFeedSection: View {
    let media: [MediaItem]
    let onOpen: (MediaItem) -> Void

    var body: some View {
        SectionCard(title: "Camera feed", systemImage: "video.fill") {
            if media.isEmpty {
                HStack(alignment: .top, spacing: Spacing.m) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No camera footage yet. Video from a drone or scene camera will appear here and be checked by the AI automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(media) { item in
                    Button { onOpen(item) } label: {
                        HStack(spacing: Spacing.m) {
                            RemoteImage(url: item.thumbnailURL)
                                .frame(width: 96, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                .overlay { PlayBadge() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Camera footage")
                                    .font(.subheadline.weight(.semibold))
                                Text(item.analysis.shortSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Camera footage, \(item.analysis.shortSummary)")
                }
            }
        }
    }
}

/// One square tile in the gallery.
struct MediaThumbnail: View {
    let item: MediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { RemoteImage(url: item.thumbnailURL ?? item.fileURL) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay {
                    if item.kind == .video { PlayBadge() }
                }
                .overlay(alignment: .bottomLeading) {
                    if item.analysis.status.isInProgress {
                        ProgressView()
                            .controlSize(.small)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    } else if item.analysis.foundSomething {
                        Image(systemName: "viewfinder")
                            .font(.caption.weight(.bold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.kind == .video ? "Video" : "Photo"), \(item.analysis.shortSummary)")
        .accessibilityHint("Opens full screen")
    }
}

/// The round "play" mark on video thumbnails.
struct PlayBadge: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(.black.opacity(0.45), in: Circle())
            .accessibilityHidden(true)
    }
}
