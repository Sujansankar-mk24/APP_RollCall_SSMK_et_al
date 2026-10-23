//
//  Sheet.swift
//  RollCall
//
//  The "roll-call sheet" look used everywhere except the Map: like the
//  paper attendance sheet a teacher or a fire captain fills in.
//
//    Paper and ink   a warm paper background, ink-black text and buttons
//                    (Assets > Paper, PaperRaised, Ink, each with a dark-mode shade)
//    Ruled rows      thin lines between rows instead of floating cards
//    Stamps          the only color: status labels stamped like a rubber stamp
//                    (green SAFE, red NEEDS HELP, amber NO ANSWER, ...)
//    Big type        heavy condensed headings, and nothing smaller than 15 pt
//
//  Screens call .sheetPage() once; every component below then draws itself
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
    }
}

// MARK: - Type

extension Font {
    /// Big page titles, like the header printed on a form: "ROLL CALL".
    static let sheetDisplay = Font.system(.largeTitle, weight: .black).width(.condensed)
    /// Section and card headings.
    static let sheetHeading = Font.system(.title2, weight: .heavy).width(.condensed)
    /// Small labels ("NO. 014 · PECAN HOLLOW"), still 15 pt so they're easy to read.
    static let sheetLabel = Font.system(.subheadline, design: .monospaced, weight: .semibold)
}

extension View {
    /// Uppercase, spaced-out label text, like a printed form.
    func sheetLabelStyle() -> some View {
        self.font(.sheetLabel).textCase(.uppercase).tracking(0.8)
    }
}

// MARK: - Headers and sections

/// The top of a page: a small label line, a big title, and a thick ink rule.
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
                Text(kicker).sheetLabelStyle().foregroundStyle(.secondary)
            }
            title
                .font(.sheetDisplay)
                .textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.ink).frame(height: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A section label with a rule running to the edge: "NEEDS ─────────".
struct SectionLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(text).sheetLabelStyle()
            Rectangle().fill(Color.ink.opacity(0.25)).frame(height: 1)
        }
        .padding(.top, Spacing.s)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One ruled line between rows.
struct RuleLine: View {
    var body: some View {
        Rectangle().fill(Color.ink.opacity(0.15)).frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A row on the sheet: roomy padding with a ruled line underneath.
    func sheetRow() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self.padding(.vertical, Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            RuleLine()
        }
    }

    /// A boxed area (for something that needs to stand out, like a request):
    /// slightly lighter paper with a thin ink border and square corners.
    func sheetBox(padding: CGFloat = Spacing.l, emphasis: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paperRaised)
            .overlay(Rectangle().strokeBorder(Color.ink.opacity(emphasis ? 1 : 0.2), lineWidth: emphasis ? 2 : 1))
    }
}

// MARK: - Tabs

/// A row of choices with the chosen one underlined in ink, like the tabs on
/// a set of printed forms ("Open (7) | Resolved (3) | All (10)").
struct SheetTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    /// For UI tests: each choice gets the identifier "<prefix><position>".
    var identifierPrefix = ""

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                let isSelected = selection == option.value
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: minimumTapSize)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(isSelected ? Color.ink : Color.clear).frame(height: 3)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(identifierPrefix.isEmpty ? "" : "\(identifierPrefix)\(index)")
            }
        }
        .overlay(alignment: .bottom) { RuleLine() }
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

// MARK: - Buttons

/// Ink buttons with square corners. `.prominent` is filled ink; otherwise
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
            .background(prominent ? color : Color.clear)
            .overlay(Rectangle().strokeBorder(color, lineWidth: 2))
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
            .background(prominent ? Color.ink : Color.clear)
            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1.5))
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
            Text(text).font(.sheetLabel.weight(.bold)).textCase(.uppercase).tracking(1)
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

/// A side note with an ink bar on its left, like a margin note.
struct SheetNote: View {
    let text: LocalizedStringKey
    var systemImage: String? = nil
    var color: Color = .ink

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Rectangle().fill(color).frame(width: 3)
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(color).accessibilityHidden(true)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
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
