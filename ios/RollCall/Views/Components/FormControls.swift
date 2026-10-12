//
//  FormControls.swift
//  RollCall
//
//  Large, friendly controls used in the household setup: easy to hit, easy to
//  read, and clear to VoiceOver.
//

import SwiftUI

/// "Children  [ - ] 2 [ + ]": a number with big minus and plus buttons.
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
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(brand)
                .frame(width: 44, height: 44)
                .background(brand.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)")
                .font(.title2.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 32)
                .contentTransition(.numericText())
            stepButton("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .card(padding: Spacing.m)
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
                .font(.headline)
                .frame(width: minimumTapSize, height: minimumTapSize)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? brand : Color.secondary.opacity(0.5))
        .disabled(!enabled)
    }
}

/// A big on/off tile with an icon, title and a short explanation.
struct ToggleTile: View {
    @Environment(\.brand) private var brand
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    @Binding var isOn: Bool
    var identifier: String = ""

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(isOn ? .white : brand)
                        .frame(width: 44, height: 44)
                        .background(isOn ? brand : brand.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? brand : Color.secondary.opacity(0.5))
                }
                Text(title).font(.headline).multilineTextAlignment(.leading)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(Spacing.m)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isOn ? brand : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// A rounded chip that can be selected (for picking several things).
struct SelectChip: View {
    @Environment(\.brand) private var brand
    let title: LocalizedStringResource
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: systemImage) }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: minimumTapSize)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(isSelected ? brand : Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// "Step 2 of 5" with a segmented bar.
struct StepProgress: View {
    @Environment(\.brand) private var brand
    let current: Int   // 0-based
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index <= current ? brand : Color(.tertiarySystemFill))
                        .frame(height: 6)
                }
            }
            Text("Step \(current + 1) of \(total)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

/// A text field with its label above it (never a placeholder-only field).
struct LabeledField: View {
    let label: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var identifier: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold))
            TextField(prompt, text: $text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 50)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }
}
