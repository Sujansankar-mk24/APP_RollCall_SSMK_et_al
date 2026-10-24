//
//  AboutView.swift
//  RollCall
//
//  About RollCall (from the gear): what the app does, what each tab is for,
//  who can see your information, and where the demo data comes from.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    tabsSection
                    privacySection
                    projectSection
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("closeAbout")
                }
                .flat()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            BrandMark(size: 44)
            SheetTitle(title: "About RollCall", kicker: String(localized: "Congressional App Challenge 2026"))
            Text("Make sure no one gets left behind.")
                .font(.title3.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - What each tab does

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("What's in the app")
            SheetCard {
                infoRow("map.fill", "Map",
                        "See emergencies near you and report one with a photo or video. Reports close together merge into one incident, and AI checks the photos for fire, smoke and people.")
                infoRow("list.bullet.rectangle.fill", "Incidents",
                        "On the Map, the Incidents button (top left) opens every incident sorted by priority, with a \"Why this priority?\" breakdown anyone can check.")
                infoRow("person.crop.circle.badge.checkmark", "Roll Call",
                        "Households sign up ahead of time (or choose \"Not now\"). When an emergency hits, everyone in the area is asked if they're safe, a volunteer buddy checks on anyone who doesn't answer, and responders see who still needs help.")
                infoRow("house.and.flag.fill", "Community",
                        "Join your neighborhood. The admin approves who joins, and neighbors in the same community can be buddies for each other.")
                infoRow("gearshape.fill", "Settings",
                        "The gear at the top of every tab has your profile, this page, and light or dark mode. You sign out from your profile.")
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("Who can see your information")
            SheetCard {
                infoRow("person.fill", "You",
                        "Always. You can edit your household or delete it completely at any time.")
                infoRow("person.2.wave.2.fill", "Your volunteer buddy",
                        "Only after you accept them. Volunteers outside your community can only ask by typing your exact address, if your community allows it.")
                infoRow("cross.case.fill", "Responders",
                        "Only during an active emergency, and only for homes inside the emergency zone.")
                infoRow("eye.slash.fill", "Everyone else",
                        "Never. Neighbors in your community see only your first name and street, and only if you asked for a buddy. Incident reports on the map don't show who sent them.")
            }
            SheetNote(text: "The server enforces these rules, so a changed copy of the app can't get around them.", systemImage: "lock.fill")
        }
    }

    // MARK: - About the project

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("About this project")
            SheetCard {
                infoRow("building.columns.fill", "Congressional App Challenge 2026",
                        "Built for Texas' 4th District by a high school student.")
                infoRow("theatermasks.fill", "Demo incidents",
                        "The community reports already on the map are made-up examples. Their photos and videos are public domain or Creative Commons, from Wikimedia Commons. Live data (diamonds) is real.")
                infoRow("cross.case.fill", "Not a 911 service",
                        "RollCall helps neighbors and responders, but it doesn't contact 911 for you.")
            }
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.sheetHeading)
            .accessibilityAddTraits(.isHeader)
    }

    private func infoRow(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheetRow()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AboutView()
}
