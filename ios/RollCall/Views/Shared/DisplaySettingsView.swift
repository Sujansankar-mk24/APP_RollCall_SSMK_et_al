//
//  DisplaySettingsView.swift
//  RollCall
//
//  Settings > Display: light, dark, or matching the iPhone (each with a
//  small preview), and the color theme, each shown with its color so you
//  can see what you're picking before you pick it.
//

import SwiftUI

struct DisplaySettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var mode: AppearanceMode = .system
    private var theme: AppTheme { ThemeStore.shared.theme }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    SectionLabel("Appearance")
                    HStack(spacing: Spacing.m) {
                        ForEach(AppearanceMode.allCases) { option in
                            appearanceCard(option)
                        }
                    }

                    SectionLabel("Color theme")
                    SheetCard {
                        ForEach(AppTheme.allCases) { option in
                            themeRow(option)
                        }
                    }

                    // A live sample of the chosen theme.
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        Text("Preview").sheetLabelStyle().foregroundStyle(.secondary)
                        Button("Join the roll call") {}
                            .buttonStyle(InkButtonStyle())
                            .allowsHitTesting(false)
                        HStack(spacing: Spacing.s) {
                            Button("Approve") {}.buttonStyle(SmallInkButtonStyle())
                            Button("Decline") {}.buttonStyle(SmallInkButtonStyle(prominent: false))
                            Spacer()
                            Toggle("", isOn: .constant(true)).labelsHidden()
                        }
                        .allowsHitTesting(false)
                    }
                    .sheetBox()
                    .accessibilityHidden(true)
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeDisplay")
                }
                .flat()
            }
            .animation(.snappy(duration: 0.25), value: theme)
        }
        .onChange(of: mode) { mode.apply() }
    }

    /// A tiny phone screen showing what the mode looks like.
    private func appearanceCard(_ option: AppearanceMode) -> some View {
        let selected = mode == option
        return Button { mode = option } label: {
            VStack(spacing: Spacing.s) {
                ZStack {
                    switch option {
                    case .light: preview(page: .white, card: Color(white: 0.93), text: .black)
                    case .dark: preview(page: Color(white: 0.05), card: Color(white: 0.17), text: .white)
                    case .system:
                        HStack(spacing: 0) {
                            preview(page: .white, card: Color(white: 0.93), text: .black)
                            preview(page: Color(white: 0.05), card: Color(white: 0.17), text: .white)
                        }
                    }
                }
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous)
                    .strokeBorder(selected ? theme.color : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1))
                Label(option.title, systemImage: selected ? "checkmark.circle.fill" : option.symbol)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("appearance_\(option.rawValue)")
    }

    private func preview(page: Color, card: Color, text: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(text.opacity(0.8)).frame(width: 30, height: 6)
            RoundedRectangle(cornerRadius: 6).fill(card).frame(height: 22)
            RoundedRectangle(cornerRadius: 6).fill(card).frame(height: 14)
            Capsule().fill(theme == .classic ? text : theme.color).frame(height: 12)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(page)
    }

    private func themeRow(_ option: AppTheme) -> some View {
        Button { ThemeStore.shared.theme = option } label: {
            HStack(spacing: Spacing.m) {
                // The theme's color, right next to its name.
                Circle()
                    .fill(option.color)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.body.weight(.semibold))
                    Text(option.subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if theme == option {
                    Image(systemName: "checkmark").font(.headline).foregroundStyle(option.color)
                }
            }
            .sheetRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(theme == option ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("theme_\(option.rawValue)")
    }
}
