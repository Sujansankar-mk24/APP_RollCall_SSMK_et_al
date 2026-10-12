//
//  FlowLayout.swift
//  RollCall
//
//  Lays chips out left to right and wraps onto a new line when a row is
//  full, like words in a paragraph.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > maxWidth, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += rows[last].items.isEmpty ? size.width : size.width + spacing
            rows[last].height = max(rows[last].height, size.height)
            rows[last].items.append(index)
        }
        return rows
    }
}

/// A row of chips that wraps, e.g. "2 people · 65+ · Oxygen · No vehicle".
struct TagChips: View {
    let tags: [NeedTag]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                HStack(spacing: 4) {
                    Image(systemName: tag.symbol)
                        .foregroundStyle(tag.tint)
                        .imageScale(.small)
                    Text(tag.text)
                }
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}
