//
//  SlidingTabBar.swift
//  RollCall
//
//  The bar along the bottom of the app: a flat rounded bar with a colored
//  pill that slides to the tab you pick. Each tab has its own pill color
//  (Map green, Roll Call red, Community orange), and the color changes as
//  the pill slides. It replaces the system's glass tab bar.
//
//  The look and motion follow the "Tabs sliding" transition from
//  transitions.dev, rebuilt in SwiftUI:
//    bar  #f1f1f1, 3 pt padding, 3 pt between tabs, fully rounded
//    pill slides in 250 ms with the curve cubic-bezier(0.22, 1, 0.36, 1)
//    text white on the pill, #0f0f0f at 80% on the others
//  Tabs are 44 pt tall (the recipe's 30 pt, raised to Apple's minimum tap
//  size), and there's a matching dark-mode version. If Reduce Motion is on,
//  the pill jumps instead of sliding.
//

import SwiftUI

struct SlidingTabBar<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let title: LocalizedStringKey
        let color: Color
        var badge: Int = 0
        let identifier: String
    }

    @Binding var selection: Tab
    let items: [Item]
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The recipe's motion: 250 ms, cubic-bezier(0.22, 1, 0.36, 1).
    private static var slide: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.25) }

    /// How much room the bar takes at the bottom of each screen.
    static var height: CGFloat { minimumTapSize + 3 * 2 + Spacing.xs }

    var body: some View {
        // Like the recipe, each tab is as wide as its label and the bar is as
        // wide as its tabs. On a narrow phone, a tighter version is used.
        ViewThatFits(in: .horizontal) {
            bar(tabPadding: 12)
            bar(tabPadding: 7)
            bar(tabPadding: 5, compact: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mainTabBar")
    }

    private func bar(tabPadding: CGFloat, compact: Bool = false) -> some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.tab) { item in
                tabButton(item, padding: tabPadding, compact: compact)
            }
        }
        .padding(3)
        .background(TabColors.bar, in: Capsule())
        .fixedSize()
    }

    private func tabButton(_ item: Item, padding: CGFloat, compact: Bool) -> some View {
        let isSelected = selection == item.tab
        return Button {
            withAnimation(reduceMotion ? nil : Self.slide) { selection = item.tab }
        } label: {
            Text(item.title)
                .lineLimit(1)
                .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : TabColors.textMuted)
                .padding(.horizontal, padding)
                .frame(minHeight: minimumTapSize)
                .overlay(alignment: .topTrailing) {
                    // A small count bubble on the corner, so it doesn't take up width.
                    if item.badge > 0 {
                        Text("\(item.badge)")
                            .font(.app(.caption2).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color(.systemRed), in: Capsule())
                            .overlay(Capsule().strokeBorder(TabColors.bar, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }
            .background {
                // Only the chosen tab draws the pill; matchedGeometryEffect makes
                // SwiftUI slide that one pill from the old tab to the new one.
                if isSelected {
                    Capsule()
                        .fill(item.color)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(item.badge > 0 ? Text("\(item.badge) need attention") : Text(""))
        .accessibilityIdentifier(item.identifier)
    }
}

/// The recipe's bar and text colors (#f1f1f1 and #0f0f0f), each with a
/// dark-mode shade, kept in Assets > TabBar and TabText.
private enum TabColors {
    static let bar = Color.tabBar
    static let textMuted = Color.tabText.opacity(0.8)
}
