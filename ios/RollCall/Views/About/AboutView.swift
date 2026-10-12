//
//  AboutView.swift
//  RollCall
//
//  The About tab: what RollCall does, what each tab is for, who can see your
//  information, and where the demo data comes from.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    EmergencyBanner()
                    tabsSection
                    privacySection
                    projectSection
                }
                .padding(Spacing.l)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { AppearanceToolbarMenu() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.l) {
            BrandMark(size: 60, showsRings: false)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("RollCall")
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
                Text("Make sure no one gets left behind.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - What each tab does

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("What's in the app")
            VStack(alignment: .leading, spacing: Spacing.l) {
                infoRow("map.fill", "Map",
                        "See emergencies near you and report one with a photo or video. Reports close together merge into one incident, and AI checks the photos for fire, smoke and people.")
                infoRow("list.bullet.rectangle.fill", "Incidents",
                        "For responders: every incident sorted by priority, with a \"Why this priority?\" breakdown anyone can check.")
                infoRow("person.crop.circle.badge.checkmark", "Roll Call",
                        "Households sign up ahead of time. When an emergency hits, everyone in the area is asked if they're safe, a volunteer buddy checks on anyone who doesn't answer, and responders see who still needs help.")
            }
            .card()
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("Who can see your information")
            VStack(alignment: .leading, spacing: Spacing.l) {
                infoRow("person.fill", "You",
                        "Always. You can edit your household or delete it completely at any time.")
                infoRow("person.2.wave.2.fill", "Your volunteer buddy",
                        "Only if you ask for one, and only the households they agreed to check on.")
                infoRow("cross.case.fill", "Responders",
                        "Only during an active emergency, and only for homes inside the emergency zone.")
                infoRow("eye.slash.fill", "Everyone else",
                        "Never. Incident reports on the map don't show who sent them.")
            }
            .card()
            Text("These rules are checked by the server, not just hidden in the app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - About the project

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("About this project")
            VStack(alignment: .leading, spacing: Spacing.l) {
                infoRow("building.columns.fill", "Congressional App Challenge 2026",
                        "Built for Texas' 4th District by a high school student.")
                infoRow("theatermasks.fill", "Demo data",
                        "Every household, volunteer, name, street and phone number is fictional. Sample photos and videos are public domain or Creative Commons, from Wikimedia Commons.")
            }
            .card()
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .fontDesign(.rounded)
            .accessibilityAddTraits(.isHeader)
    }

    private func infoRow(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AboutView()
}
