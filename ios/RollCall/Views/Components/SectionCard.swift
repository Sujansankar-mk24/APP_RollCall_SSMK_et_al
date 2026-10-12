//
//  SectionCard.swift
//  RollCall
//
//  The rounded card used for each section of the detail sheet, with a
//  title (and optional small note on the right) above it.
//

import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    var systemImage: String?
    var trailingNote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                Spacer()
                if let trailingNote {
                    Text(trailingNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Spacing.xs)

            VStack(alignment: .leading, spacing: Spacing.m) {
                content
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

/// A picture loaded from the server, with a gentle placeholder while it
/// loads and an icon if it can't be loaded.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            default:
                Color(.tertiarySystemFill)
            }
        }
    }
}
