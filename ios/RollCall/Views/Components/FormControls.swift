//
//  FormControls.swift
//  RollCall
//
//  The controls used to fill in the household form, drawn like a paper form:
//  check boxes, a counter with big buttons, tags, and boxes to write in
//  (what you type shows up in handwriting, like filling in a form by hand).
//  Easy to hit, easy to read, and clear to VoiceOver.
//

import SwiftUI

/// "Children   [ − ]  2  [ + ]": a number with big minus and plus buttons.
struct CounterRow: View {
    @Environment(\.brand) private var brand
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...20
    var identifier: String = ""

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Label { Text(title) } icon: { Image(systemName: systemImage) }
                    .font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)")
                .font(.system(.title, weight: .semibold)).monospacedDigit()
                .frame(minWidth: 32)
                .contentTransition(.numericText())
            stepButton("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .sheetRow()
        .animation(.snappy(duration: 0.2), value: value)
        // VoiceOver: one adjustable element ("Children, 2, adjustable").
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityIdentifier(identifier)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .frame(width: minimumTapSize, height: minimumTapSize)
                .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous).strokeBorder(enabled ? brand : Color.secondary.opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? brand : Color.secondary.opacity(0.5))
        .disabled(!enabled)
    }
}

/// "☐ Mobility needs": a big check box, like ticking a box on a form.
/// (Named ToggleTile because it used to be a tile; it's now a row.)
struct ToggleTile: View {
    @Environment(\.brand) private var brand
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    @Binding var isOn: Bool
    var identifier: String = ""

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .center, spacing: Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? brand : Color.clear)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(brand, lineWidth: 1.5)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.paper)
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Label { Text(title) } icon: { Image(systemName: systemImage) }
                        .font(.sheetHeading)
                    Text(subtitle)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .sheetRow()
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isOn)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// A tag that can be selected (for picking several things).
struct SelectChip: View {
    @Environment(\.brand) private var brand
    let title: LocalizedStringResource
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: isSelected ? "checkmark" : systemImage) }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: minimumTapSize)
                .foregroundStyle(isSelected ? Color.paper : Color.primary)
                .background(isSelected ? brand : Color.clear, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous).strokeBorder(isSelected ? brand : Color.primary.opacity(0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// "STEP 2 OF 5" with a row of numbered boxes; finished steps are filled in.
struct StepProgress: View {
    @Environment(\.brand) private var brand
    let current: Int   // 0-based
    let total: Int

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(0..<total, id: \.self) { index in
                Text("\(index + 1)")
                    .font(.sheetLabel.weight(.bold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(index <= current ? Color.paper : Color.secondary)
                    .background(index <= current ? brand : Color.clear, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous).strokeBorder(index <= current ? brand : Color.secondary.opacity(0.4), lineWidth: 1.5))
            }
            Spacer()
            Text("Step \(current + 1) of \(total)").sheetLabelStyle().foregroundStyle(.secondary)
        }
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

/// A form field: a printed label above, and a box to write in (never a
/// placeholder-only field). What you type is shown in handwriting.
struct LabeledField: View {
    let label: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    /// Off for things like web addresses, which are easier to check in print.
    var handwritten = true
    var identifier: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).sheetLabelStyle().foregroundStyle(.secondary)
            TextField(text: $text, prompt: Text(prompt).font(.body)) { Text(label) }
                .font(handwritten ? .sheetEntry : .title3)
                .foregroundStyle(Color.ink)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 50)
                .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }
}
