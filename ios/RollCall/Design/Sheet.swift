//
//  Sheet.swift
//  RollCall
//
//  The "roll-call sheet" look used everywhere except the Map: like the
//  printed sign-in sheet a teacher or a fire captain fills in.
//
//    Printed and written  everything the app says is printed in the system
//                         font. What a person wrote in (a name, an address,
//                         a neighborhood) is in handwriting, like a name
//                         written on the line of a real roll call.
//    Paper cards          related things sit together on a card of lighter
//                         paper with a thin border. No lines across the page.
//    Stamps               the only color: status labels stamped like a rubber
//                         stamp (green SAFE, red NEEDS HELP, amber NO ANSWER)
//    Easy to read         nothing smaller than 15 pt, and every size follows
//                         the user's text size setting
//
//  Screens call .sheetPage() once. Every component below then draws itself
//  in ink on paper.
//

import SwiftUI

// MARK: - Page

extension View {
    /// Ink-colored buttons and controls (without the paper background).
    func sheetBrand() -> some View {
        environment(\.brand, .ink).tint(.ink)
    }

    /// Paper background, ink-colored buttons and controls, for a whole screen.
    func sheetPage() -> some View {
        self
            .background(Color.paper.ignoresSafeArea())
            .environment(\.brand, .ink)
            .tint(.ink)
            .toolbarBackground(Color.paper, for: .navigationBar)
            // When this page is shown as a sheet, give it solid paper instead
            // of the system's see-through glass (ignored everywhere else).
            .presentationBackground(Color.paper)
    }
}

// MARK: - Tokens

extension Radius {
    /// Buttons and fields on the sheet.
    static let paperControl: CGFloat = 8
    /// Paper cards.
    static let paperCard: CGFloat = 12
}

// MARK: - Type

extension Font {
    /// Page titles, printed: "Roll Call", "Community".
    static let sheetDisplay = Font.system(.title, weight: .semibold)
    /// Card and section headings, printed: "Join the roll call?".
    static let sheetHeading = Font.system(.title3, weight: .semibold)
    /// Small printed labels on the form ("Your household", "Members").
    static let sheetLabel = Font.system(.subheadline, weight: .semibold)
    /// Something a person wrote in: a name, an address, a neighborhood.
    /// Bradley Hand comes with every iPhone, and `relativeTo` makes it grow
    /// with the user's text size.
    static let sheetEntry = Font.custom("BradleyHandITCTT-Bold", size: 22, relativeTo: .title3)
    /// A bigger written-in entry, for the name at the top of a page.
    static let sheetEntryLarge = Font.custom("BradleyHandITCTT-Bold", size: 30, relativeTo: .title)
}

extension View {
    /// The small printed label over a part of the form: "YOUR HOUSEHOLD".
    func sheetLabelStyle() -> some View {
        self.font(.sheetLabel).textCase(.uppercase).tracking(0.6)
    }

    /// Text a person wrote in, drawn in handwriting and ink.
    func sheetEntryStyle(large: Bool = false) -> some View {
        self.font(large ? .sheetEntryLarge : .sheetEntry).foregroundStyle(Color.ink)
    }
}

// MARK: - Headers and sections

/// The top of a page: a small printed label and the page's title. Fixed
/// wording ("Roll Call") is printed. A name someone typed ("Pecan Hollow")
/// is handwritten, like a name filled in at the top of a form.
struct SheetTitle: View {
    private let title: Text
    private let kicker: String?
    private let isWrittenIn: Bool

    /// Fixed wording, translated from the String Catalog ("Roll Call").
    init(title: LocalizedStringKey, kicker: String? = nil) {
        self.title = Text(title)
        self.kicker = kicker
        isWrittenIn = false
    }

    /// A name typed by someone, shown exactly as written ("Pecan Hollow").
    init(verbatim title: String, kicker: String? = nil) {
        self.title = Text(verbatim: title)
        self.kicker = kicker
        isWrittenIn = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let kicker {
                Text(kicker).sheetLabelStyle().foregroundStyle(.secondary)
            }
            title
                .font(isWrittenIn ? .sheetEntryLarge : .sheetDisplay)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The small printed label above a card: "NEEDS".
struct SectionLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .sheetLabelStyle()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.s)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A thin line between two entries inside a card (never across the page).
struct RuleLine: View {
    var body: some View {
        Rectangle().fill(Color.ink.opacity(0.12)).frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A paper card: related entries grouped together, like the lines of one
/// box on a form. On iOS 18 and later, a thin line separates each entry.
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
    /// One entry on a card: roomy padding, full width.
    func sheetRow() -> some View {
        self.padding(.vertical, Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The paper card's look: lighter paper, rounded corners, a thin border.
    func paperCard(emphasis: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.paperCard, style: .continuous)
        return self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paperRaised, in: shape)
            .overlay(shape.strokeBorder(Color.ink.opacity(emphasis ? 0.9 : 0.14), lineWidth: emphasis ? 1.5 : 1))
    }

    /// A card with padding all around, for one block of content (a request,
    /// a message, a form section).
    func sheetBox(padding: CGFloat = Spacing.l, emphasis: Bool = false) -> some View {
        self
            .padding(padding)
            .paperCard(emphasis: emphasis)
    }
}

// MARK: - Tabs

/// A row of choices on a paper strip, with the chosen one filled in ink
/// ("Open (7) | Resolved (3) | All (10)").
struct SheetTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    /// For UI tests: each choice gets the identifier "<prefix><position>",
    /// or the matching entry of `identifiers` if those are given.
    var identifierPrefix = ""
    var identifiers: [String] = []
    @Namespace private var fill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                let isSelected = selection == option.value
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.paper : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: minimumTapSize)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous)
                                    .fill(Color.ink)
                                    .matchedGeometryEffect(id: "fill", in: fill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(index < identifiers.count ? identifiers[index]
                                         : identifierPrefix.isEmpty ? "" : "\(identifierPrefix)\(index)")
            }
        }
        .padding(4)
        .paperCard()
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

// MARK: - Buttons

/// Ink buttons with slightly rounded corners. `.prominent` is filled ink; otherwise
/// it's an ink outline. Always at least 52 pt tall, so they're easy to hit.
struct InkButtonStyle: ButtonStyle {
    var prominent = true
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let color: Color = destructive ? Color(.systemRed) : .ink
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(prominent ? Color.paper : color)
            .background(prominent ? color : Color.clear, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous).strokeBorder(color, lineWidth: 1.5))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
            .contentShape(Rectangle())
    }
}

/// A compact ink button for inside a row ("Approve", "Offer to help").
struct SmallInkButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: minimumTapSize)
            .foregroundStyle(prominent ? Color.paper : Color.ink)
            .background(prominent ? Color.ink : Color.clear, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous).strokeBorder(Color.ink, lineWidth: 1.5))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
            .contentShape(Rectangle())
            .fixedSize()
    }
}

// MARK: - Stamps

/// A rubber-stamp status label, slightly tilted: "✓ SAFE", "NEEDS HELP".
/// This is where color lives on the sheet, always next to a word.
struct Stamp: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .ink
    var tilt: Double = -2

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.subheadline.weight(.bold)) }
            Text(text).font(.sheetLabel.weight(.bold)).textCase(.uppercase).tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 2))
        .rotationEffect(.degrees(tilt))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Notes and messages

/// A short note in its own small card, with an icon: "You can leave anytime."
struct SheetNote: View {
    let text: LocalizedStringKey
    var systemImage: String? = nil
    var color: Color = .ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Image(systemName: systemImage ?? "info.circle")
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Loading problems and empty lists, in the sheet style.
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
            Label { title.font(.sheetHeading) } icon: { Image(systemName: systemImage) }
            message.font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(InkButtonStyle(prominent: false))
            }
        }
        .sheetBox()
    }
}
