//
//  MapFilterBar.swift
//  RollCall
//
//  The row of filter chips floating at the top of the map. Each chip opens
//  a menu: type and status allow several choices, time allows one.
//

import SwiftUI

struct MapFilterBar: View {
    @Binding var filters: MapFilters

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                sourceMenu
                typeMenu
                statusMenu
                timeMenu
                if !filters.isDefault {
                    clearButton
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)  // room for the chips' shadows
        }
        // Chips fade out at the edges instead of being cut off next to the
        // Incidents button and the gear.
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: Spacing.m)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: Spacing.l)
            }
        }
        .animation(.easeOut(duration: 0.2), value: filters.isDefault)
    }

    // MARK: - Chips

    /// Community reports, live data (NASA, NOAA, the Weather Service), or both.
    private var sourceMenu: some View {
        Menu {
            Picker("Source", selection: $filters.source) {
                ForEach(MapSource.allCases) { source in
                    Label(source.title, systemImage: source.symbol).tag(source)
                }
            }
        } label: {
            FilterChipLabel(title: filters.source == .all ? String(localized: "Source") : filters.source.title,
                            systemImage: filters.source.symbol, isActive: filters.source != .all)
        }
        .accessibilityIdentifier("sourceFilter")
    }

    private var typeMenu: some View {
        Menu {
            // Quick "modes": show one group of disasters at a time.
            Section("Modes") {
                Button("All incidents", systemImage: "square.grid.2x2") {
                    filters.types = Set(IncidentType.allCases)
                }
                ForEach(IncidentCategory.allCases) { category in
                    Button("\(category.title) only", systemImage: category.symbol) {
                        filters.types = Set(category.types)
                    }
                }
            }
            // Or pick individual types, grouped the same way.
            ForEach(IncidentCategory.allCases) { category in
                Section(category.title) {
                    ForEach(category.types) { type in
                        Toggle(isOn: toggleBinding(type, in: \.types)) {
                            Label(type.title, systemImage: type.symbol)
                        }
                        .menuActionDismissBehavior(.disabled)  // keep the menu open to pick several
                    }
                }
            }
        } label: {
            FilterChipLabel(
                title: filters.typesLabel,
                systemImage: "square.grid.2x2",
                isActive: filters.types.count != IncidentType.allCases.count
            )
        }
        .accessibilityLabel("Incident type filter")
        .accessibilityValue(filters.types.count == IncidentType.allCases.count ? "All types" : filters.typesLabel)
    }

    private var statusMenu: some View {
        Menu {
            ForEach(IncidentStatus.allCases) { status in
                Toggle(status.title, isOn: toggleBinding(status, in: \.statuses))
                    .menuActionDismissBehavior(.disabled)
            }
            Divider()
            Button("Show all statuses") { filters.statuses = Set(IncidentStatus.allCases) }
        } label: {
            FilterChipLabel(
                title: filters.statusesLabel,
                systemImage: "circle.dashed",
                isActive: filters.statuses.count != IncidentStatus.allCases.count
            )
        }
        .accessibilityLabel("Status filter")
        .accessibilityValue(filters.statuses.count == IncidentStatus.allCases.count ? "All statuses" : filters.statusesLabel)
    }

    private var timeMenu: some View {
        Menu {
            Picker("Time", selection: $filters.timeWindow) {
                ForEach(TimeWindow.allCases) { window in
                    Text(window.title).tag(window)
                }
            }
        } label: {
            FilterChipLabel(
                title: filters.timeWindow.shortTitle,
                systemImage: "clock",
                isActive: filters.timeWindow != MapFilters().timeWindow
            )
        }
        .accessibilityLabel("Time filter")
        .accessibilityValue(filters.timeWindow.title)
    }

    private var clearButton: some View {
        Button {
            filters = MapFilters()
        } label: {
            FilterChipLabel(title: "Clear", systemImage: "xmark", isActive: false, showsChevron: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear all filters")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Helpers

    /// A true/false switch for one item in a set of choices. It won't let you
    /// turn off the last remaining choice (that would hide everything).
    private func toggleBinding<Item: Hashable>(
        _ item: Item, in keyPath: WritableKeyPath<MapFilters, Set<Item>>
    ) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: keyPath].contains(item) },
            set: { isOn in
                if isOn {
                    filters[keyPath: keyPath].insert(item)
                } else if filters[keyPath: keyPath].count > 1 {
                    filters[keyPath: keyPath].remove(item)
                }
            }
        )
    }
}

/// What a filter chip looks like. Chips with an active filter are tinted
/// with the accent color so you can see at a glance what's filtered.
struct FilterChipLabel: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var showsChevron = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(title)
                .font(.app(.subheadline).weight(.medium))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.app(.caption2).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isActive ? Color.themeAccent : Color.primary)
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: 38)
        .background {
            if isActive {
                Capsule().fill(Color.themeAccent.opacity(0.14))
            }
        }
        .floatingSurface(cornerRadius: 19)
        .padding(.vertical, 3)                 // invisible padding: 44 pt tall tap area
        .contentShape(Rectangle())
    }
}

#Preview {
    @Previewable @State var filters = MapFilters(types: [.fire])
    MapFilterBar(filters: $filters)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.gray.opacity(0.2))
}
