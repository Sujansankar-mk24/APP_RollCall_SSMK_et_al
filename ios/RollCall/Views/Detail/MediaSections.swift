//
//  MediaSections.swift
//  RollCall
//
//  The "Photos & videos" section of the detail sheet: everything residents
//  uploaded.
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
                            .background(Color(.systemBackground).opacity(0.9), in: Circle())
                            .padding(6)
                    } else if item.analysis.foundSomething {
                        Image(systemName: "viewfinder")
                            .font(.caption.weight(.bold))
                            .padding(6)
                            .background(Color(.systemBackground).opacity(0.9), in: Circle())
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
