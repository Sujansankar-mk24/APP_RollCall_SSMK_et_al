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
    @State private var replaysIntro = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    Button { replaysIntro = true } label: {
                        Label("Watch the intro again", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(InkButtonStyle(prominent: false))
                    .accessibilityIdentifier("replayIntro")
                    tabsSection
                    privacySection
                    projectSection
                    sourcesSection
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .fullScreenCover(isPresented: $replaysIntro) {
                IntroReplay { replaysIntro = false }.sheetBrand()
            }
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
                .font(.app(.title3).weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - What each tab does

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("What's in the app")
            SheetCard {
                infoRow("AboutMap", "Map",
                        "Live fires and storm warnings from NASA and the National Weather Service, and a warning when you're close to one. Report an emergency with a photo you just took. Reports close together merge into one incident, and AI checks the photos for fire, smoke and people.")
                infoRow("AboutIncidents", "Incidents",
                        "On the Map, the Incidents button (top left) opens every incident sorted by priority, with a \"Why this priority?\" breakdown anyone can check.")
                infoRow("AboutRollCall", "Roll Call",
                        "Households sign up ahead of time (or choose \"Not now\"). When an emergency hits, everyone in the area is asked if they're safe, a volunteer buddy checks on anyone who doesn't answer, and responders see who still needs help. You can call or text your buddy, and \"They need help\" calls 911 with everything the dispatcher needs.")
                infoRow("AboutCommunity", "Community",
                        "Join your neighborhood and see its Weekly Recap of photos. The admin approves who joins and which photos go in. Neighbors are buddies for each other, and you can see the first responders in your town.")
                infoRow("AboutResponders", "First responders",
                        "Firefighters, EMS, police and emergency managers apply with their ID, and a person checks it. Only they can mark an incident responding or resolved. Anyone can report a responder who seems fake or reckless.")
                infoRow("AboutSettings", "Settings",
                        "The gear at the top of every tab has your profile, this page, and light or dark mode. You sign out from your profile.")
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("Who can see your information")
            SheetCard {
                infoRow("PrivacyYou", "You",
                        "Always. You can edit your household or delete it completely at any time.")
                infoRow("PrivacyBuddy", "Your volunteer buddy",
                        "Only after you accept them, and then they see your household like this. Buddies always come from your own community.")
                infoRow("PrivacyResponders", "Responders",
                        "Only during an active emergency, and only for homes inside the emergency zone.")
                infoRow("PrivacyEveryone", "Everyone else",
                        "Never. Neighbors in your community see only your first name and street until you accept them as a buddy. Incident reports on the map don't show who sent them.")
            }
            SheetNote(text: "The server enforces these rules, so a changed copy of the app can't get around them.", systemImage: "lock.fill")
        }
    }

    // MARK: - About the project

    /// Where everything in the app comes from, with links.
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("Sources and credits")
            SheetCard {
                sourceRow("map.fill", "Maps", "Apple Maps (MapKit) and Apple's map data", "https://www.apple.com/legal/internet-services/maps/")
                sourceRow("exclamationmark.triangle.fill", "Weather warnings",
                          "National Weather Service, api.weather.gov (official alerts and their areas, like Tornado Warnings)",
                          "https://www.weather.gov/documentation/services-web-api")
                sourceRow("flame.fill", "Satellite fires", "NASA FIRMS, fires seen by the VIIRS satellites",
                          "https://firms.modaps.eosdis.nasa.gov")
                sourceRow("globe.americas.fill", "Natural events",
                          "NASA EONET (wildfires, storms, floods, earthquakes and more)", "https://eonet.gsfc.nasa.gov")
                sourceRow("tornado", "Storm reports", "NOAA Storm Prediction Center, today's tornado, wind and hail reports",
                          "https://www.spc.noaa.gov/climo/reports/")
                sourceRow("hurricane", "Hurricanes", "National Hurricane Center, active storms", "https://www.nhc.noaa.gov")
                sourceRow("viewfinder", "Photo AI",
                          "YOLOv8 by Ultralytics (AGPL-3.0), a fire and smoke model trained on the D-Fire dataset, OpenCV, and Apple's Vision framework on the phone",
                          "https://github.com/ultralytics/ultralytics")
                sourceRow("photo.fill", "Photos",
                          "Demo incident photos and video from Wikimedia Commons (public domain and Creative Commons). Welcome photo: South Carolina National Guard, Port Arthur, Texas, 2017, public domain.",
                          "https://commons.wikimedia.org/wiki/File:Support_during_Hurricane_Harvey_(TX)_(19).jpg")
                sourceRow("textformat", "Type and icons", "SF Pro and SF Symbols by Apple", "https://developer.apple.com/sf-symbols/")
            }
        }
    }

    private func sourceRow(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey,
                           _ link: String) -> some View {
        Link(destination: URL(string: link)!) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: symbol)
                    .font(.app(.title3).weight(.semibold))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(.headline)).foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.app(.callout))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.app(.footnote).weight(.semibold)).foregroundStyle(.tertiary)
            }
            .sheetRow()
        }
        .accessibilityHint("Opens the source's website")
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            sectionTitle("About this project")
            SheetCard {
                infoRow("ProjectChallenge", "Congressional App Challenge 2026",
                        "Built for Texas' 4th District by a high school student.")
                infoRow("ProjectDemo", "Demo incidents",
                        "The community reports already on the map are made-up examples. Their photos and videos are public domain or Creative Commons, from Wikimedia Commons. Live data (diamonds) is real.")
                infoRow("ProjectNot911", "Not a 911 service",
                        "RollCall helps neighbors and responders check on each other, but it doesn't contact 911 for you.")
            }
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.sheetHeading)
            .accessibilityAddTraits(.isHeader)
    }

    /// One part of the app, with a real screenshot of it (Assets: AboutMap,
    /// AboutRollCall, ... taken in the simulator with made-up demo accounts).
    private func infoRow(_ picture: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(picture)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.headline))
                Text(detail)
                    .font(.app(.callout))
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

/// The first-launch intro again: the Welcome screen, then the three short
/// pages that explain how RollCall works.
private struct IntroReplay: View {
    let onClose: () -> Void
    @State private var showsPages = false

    var body: some View {
        if showsPages {
            IntroView(onFinish: onClose)
                .transition(.opacity)
        } else {
            WelcomeView(onGetStarted: { withAnimation(.easeInOut) { showsPages = true } },
                        onSignIn: onClose, isReplay: true)
                .transition(.opacity)
        }
    }
}
