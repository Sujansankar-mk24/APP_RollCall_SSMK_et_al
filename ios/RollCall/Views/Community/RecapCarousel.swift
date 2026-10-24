//
//  RecapCarousel.swift
//  RollCall
//
//  The Weekly Recap at the top of a community: photos from the neighborhood
//  that you swipe or tap through, like Locket. Photos disappear after a week
//  unless the admin pins them. Members add photos, and the admin approves
//  them first.
//

import SwiftUI

struct RecapCarousel: View {
    let photos: [RecapPhoto]
    /// The admin can pin, unpin and remove photos (long-press a photo).
    var isAdmin = false
    var onAction: ((RecapPhoto, RecapMenuAction) -> Void)? = nil

    @State private var current: Int = 0

    enum RecapMenuAction { case pin, unpin, remove }

    var body: some View {
        if photos.isEmpty {
            emptyCard
        } else {
            VStack(spacing: Spacing.s) {
                TabView(selection: $current) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        photoCard(photo)
                            .tag(index)
                            .padding(.horizontal, 2)
                            // Tap to go to the next photo (and back to the first at the end).
                            .onTapGesture {
                                withAnimation(.snappy) { current = (current + 1) % photos.count }
                            }
                            .contextMenu { if isAdmin { menu(for: photo) } }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 380)
                pageDots
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("weeklyRecap")
            .onChange(of: photos.count) { current = min(current, max(photos.count - 1, 0)) }
        }
    }

    private func photoCard(_ photo: RecapPhoto) -> some View {
        AsyncImage(url: photo.imageURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.primary.opacity(0.08).overlay { ProgressView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.paperCard, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 2) {
                if !photo.caption.isEmpty {
                    Text(verbatim: photo.caption).font(.headline)
                }
                Text(verbatim: photo.uploaderName).font(.subheadline).opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 6)
            .padding(Spacing.l)
        }
        .overlay(alignment: .topTrailing) {
            if photo.pinned {
                Image(systemName: "pin.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.5), in: Circle())
                    .padding(Spacing.m)
                    .accessibilityLabel("Pinned")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.paperCard, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(photo.caption.isEmpty ? "Photo by \(photo.uploaderName)" : "\(photo.caption), by \(photo.uploaderName)")
    }

    @ViewBuilder
    private func menu(for photo: RecapPhoto) -> some View {
        if photo.pinned {
            Button("Unpin", systemImage: "pin.slash") { onAction?(photo, .unpin) }
        } else {
            Button("Pin (keep it past the week)", systemImage: "pin") { onAction?(photo, .pin) }
        }
        Button("Remove", systemImage: "trash", role: .destructive) { onAction?(photo, .remove) }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(photos.indices, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }

    private var emptyCard: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No photos this week yet")
                .font(.sheetHeading)
            Text("Share what's happening in the neighborhood: a cleanup, a block party, a storm you got through together.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, minHeight: 220)
        .paperCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weeklyRecapEmpty")
    }
}
