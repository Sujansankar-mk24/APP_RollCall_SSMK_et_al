//
//  Sheet.swift
//  RollCall
//
//  RollCall's look everywhere except the Map, inspired by apps like
//  Phantom and WHOOP: calm, bold and simple.
//
//    Dark first      a near-black page in dark mode (a soft gray one in
//                    light mode) with rounded cards on top
//                    (Assets > Paper, PaperRaised, Ink)
//    Big, bold type  large titles, and small uppercase labels with wide
//                    letter spacing for sections ("YOUR HOUSEHOLD")
//    Pill buttons    full-width capsules. The main one is filled with the
//                    text color (black in light mode, white in dark mode)
//    Grouped rows    related rows share one rounded card, split by thin lines
//    Badges          the only color: small tinted labels for status
//                    (green SAFE, red NEEDS HELP, amber WAITING, ...)
//
//  Screens call .sheetPage() once. Every piece below then draws itself in
//  the right colors. (The names, like "sheet" and "ink", come from the
//  app's earlier paper look. They're kept so every screen still uses them.)
//

import SwiftUI

// MARK: - Page

extension View {
    /// Buttons and controls in the chosen color theme (without the page background).
    func sheetBrand() -> some View {
        modifier(ThemeModifier())
    }

    /// Page background, ink-colored buttons and controls, for a whole screen.
    func sheetPage() -> some View {
        self
            .background(ZStack { Color.paper; ThemeStore.shared.theme.pageWash }.ignoresSafeArea())
            .modifier(ThemeModifier())
            // Scrolling down puts the keyboard away, so it never traps you.
            .scrollDismissesKeyboard(.interactively)
            .toolbarBackground(Color.paper, for: .navigationBar)
            // When this page is shown as a sheet, give it a solid background
            // instead of the system's see-through glass (ignored elsewhere).
            .presentationBackground(Color.paper)
    }
}

// MARK: - Tokens

extension Radius {
    /// Small controls and tinted notes.
    static let paperControl: CGFloat = 14
    /// Cards.
    static let paperCard: CGFloat = 22
}

// MARK: - Type

extension Font {
    /// Page titles: "Roll Call", "Community".
    static let sheetDisplay = Font.system(.largeTitle, weight: .bold)
    /// Card and section headings: "Join the roll call?".
    static let sheetHeading = Font.system(.title3, weight: .semibold)
    /// The small uppercase labels ("YOUR HOUSEHOLD"), still 15 pt so they're easy to read.
    static let sheetLabel = Font.system(.subheadline, weight: .semibold)
    /// Someone's name or address in a list.
    static let sheetEntry = Font.system(.body, weight: .semibold)
    /// A name at the top of a page or card.
    static let sheetEntryLarge = Font.system(.title2, weight: .bold)
}

extension View {
    /// A small uppercase label with wide letter spacing, like WHOOP's.
    func sheetLabelStyle() -> some View {
        self.font(.sheetLabel).textCase(.uppercase).tracking(1.1)
    }

    /// Someone's name or address.
    func sheetEntryStyle(large: Bool = false) -> some View {
        self.font(large ? .sheetEntryLarge : .sheetEntry).foregroundStyle(Color.primary)
    }
}

// MARK: - Headers and sections

/// The top of a page: a small uppercase label and a big bold title.
struct SheetTitle: View {
    private let title: Text
    private let kicker: String?

    /// Fixed wording, translated from the String Catalog ("Roll Call").
    init(title: LocalizedStringKey, kicker: String? = nil) {
        self.title = Text(title)
        self.kicker = kicker
    }

    /// A name typed by someone, shown exactly as written ("Pecan Hollow").
    init(verbatim title: String, kicker: String? = nil) {
        self.title = Text(verbatim: title)
        self.kicker = kicker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let kicker {
                Text(kicker).sheetLabelStyle().foregroundStyle(ThemeStore.shared.theme.labelColor)
            }
            title
                .font(.sheetDisplay)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The small uppercase label above a card: "NEEDS".
struct SectionLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .sheetLabelStyle()
            .foregroundStyle(ThemeStore.shared.theme.labelColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.s)
            .padding(.leading, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A thin line between two rows inside a card.
struct RuleLine: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A rounded card holding a group of rows, split by thin lines (on iOS 18
/// and later), like the grouped lists in Phantom.
struct SheetCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if #available(iOS 18.0, *) {
                Group(subviews: content) { entries in
                    ForEach(entries) { entry in
                        if entry.id != entries.first?.id { RuleLine() }
                        entry
                    }
                }
            } else {
                content
            }
        }
        .padding(.horizontal, Spacing.l)
        .paperCard()
    }
}

extension View {
    /// One row in a card: roomy padding, full width.
    func sheetRow() -> some View {
        self.padding(.vertical, Spacing.m + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The card look: a raised surface with big rounded corners. `emphasis`
    /// adds an outline, for something that needs an answer.
    func paperCard(emphasis: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.paperCard, style: .continuous)
        return self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paperRaised, in: shape)
            .overlay {
                if emphasis { shape.strokeBorder(Color.ink.opacity(0.85), lineWidth: 1.5) }
            }
    }

    /// A card with padding all around, for one block of content.
    func sheetBox(padding: CGFloat = Spacing.l, emphasis: Bool = false) -> some View {
        self
            .padding(padding)
            .paperCard(emphasis: emphasis)
    }
}

// MARK: - Tabs

/// A row of capsule chips with the chosen one filled ("All | Tokens | Perps"
/// in Phantom), used to switch between parts of a page.
struct SheetTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    /// For UI tests: each choice gets the identifier "<prefix><position>",
    /// or the matching entry of `identifiers` if those are given.
    var identifierPrefix = ""
    var identifiers: [String] = []
    @Namespace private var fill
    @Environment(\.brand) private var brand
    @Environment(\.onBrand) private var onBrand

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                let isSelected = selection == option.value
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? onBrand : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, Spacing.s)
                        .frame(maxWidth: .infinity, minHeight: minimumTapSize)
                        .background {
                            if isSelected {
                                Capsule().fill(brand).matchedGeometryEffect(id: "fill", in: fill)
                            } else {
                                Capsule().fill(Color.paperRaised)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(index < identifiers.count ? identifiers[index]
                                         : identifierPrefix.isEmpty ? "" : "\(identifierPrefix)\(index)")
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

// MARK: - Buttons

/// Full-width pill buttons. `prominent` is filled with the text color (black
/// in light mode, white in dark mode); otherwise it sits on a card-colored
/// pill. At least 56 pt tall, so they're easy to hit.
struct InkButtonStyle: ButtonStyle {
    var prominent = true
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.brand) private var brand
    @Environment(\.onBrand) private var onBrand

    func makeBody(configuration: Configuration) -> some View {
        let red = Color(.systemRed)
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(prominent ? (destructive ? .white : onBrand) : (destructive ? red : Color.primary))
            .background(prominent ? (destructive ? red : brand) : Color.paperRaised, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// A smaller pill for inside a row ("Approve", "Offer to help").
struct SmallInkButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.brand) private var brand
    @Environment(\.onBrand) private var onBrand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: minimumTapSize)
            .foregroundStyle(prominent ? onBrand : Color.primary)
            .background(prominent ? brand : Color.primary.opacity(0.08), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .contentShape(Capsule())
            .fixedSize()
    }
}

// MARK: - Badges

/// A small tinted status label: "✓ SAFE", "NEEDS HELP". This is where color
/// lives, always next to a word so color isn't the only clue.
/// (`tilt` is ignored now. It's kept so older calls still work.)
struct Stamp: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .ink
    var tilt: Double = 0

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption.weight(.bold)) }
            Text(text).font(.caption.weight(.bold)).textCase(.uppercase).tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Notes and messages

/// A short note on a tinted rounded background, with an icon.
struct SheetNote: View {
    let text: LocalizedStringKey
    var systemImage: String? = nil
    var color: Color = .ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Image(systemName: systemImage ?? "info.circle")
                .foregroundStyle(color == .ink ? Color.secondary : color)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((color == .ink ? Color.primary : color).opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Loading problems and empty lists.
struct SheetMessage: View {
    let title: Text
    let message: Text
    var systemImage = "exclamationmark.triangle"
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    init(_ title: LocalizedStringKey, message: LocalizedStringKey, systemImage: String = "info.circle",
         actionTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        self.title = Text(title)
        self.message = Text(message)
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    /// For something that went wrong while talking to the server.
    init(error: APIError, action: (() -> Void)? = nil) {
        title = Text(error.title)
        message = Text(verbatim: error.message)
        systemImage = error == .serverUnreachable ? "antenna.radiowaves.left.and.right.slash" : "exclamationmark.triangle"
        actionTitle = action == nil ? nil : "Try again"
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            title.font(.sheetHeading)
            message.font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(InkButtonStyle(prominent: false))
            }
        }
        .sheetBox()
    }
}
