//
//  TypePickerGrid.swift
//  RollCall
//
//  "What's happening?": big, easy-to-tap tiles for every incident type,
//  grouped into Fire & smoke, Severe weather, and Medical & other.
//

import SwiftUI

struct TypePickerGrid: View {
    @Binding var selection: IncidentType?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: Spacing.s)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ForEach(IncidentCategory.allCases) { category in
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(category.title)
                        .font(.app(.footnote).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: columns, spacing: Spacing.s) {
                        ForEach(category.types) { type in
                            tile(for: type)
                        }
                    }
                }
            }
        }
    }

    private func tile(for type: IncidentType) -> some View {
        let isSelected = selection == type
        return Button {
            selection = type
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.symbol)
                    .font(.app(.title2))
                    .frame(height: 28)
                Text(type.title)
                    .font(.app(.footnote).weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.themeAccent : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? Color.themeAccent.opacity(0.14) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(isSelected ? Color.themeAccent : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    @Previewable @State var selection: IncidentType? = .tornado
    ScrollView {
        TypePickerGrid(selection: $selection).padding()
    }
    .background(Color(.systemGroupedBackground))
}
