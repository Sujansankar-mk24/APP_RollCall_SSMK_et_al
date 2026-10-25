//
//  RootView.swift
//  RollCall
//
//  If an account is saved on this phone, the app opens straight to the tab
//  bar; otherwise it shows the sign-in screen.
//
//  The tab bar along the bottom:
//    Map        live hazards and community reports on a map, the incident log
//               (the Incidents button, top left), and reporting
//    Roll Call  your household and the neighbors you check on
//    Community  your neighborhood (not shown to responders)
//  Your profile, sign out, About RollCall and light/dark mode are behind the
//  gear button at the top of every tab (SettingsButton.swift).
//  The map and its incident log share one IncidentStore, so they always agree.
//  Every tab except the Map uses the roll-call sheet look (Design/Sheet.swift).
//

import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    /// The intro pages show once, the first time the app is opened.
    @AppStorage("hasSeenIntro") private var hasSeenIntro = DebugLaunchOptions.skipsIntro
    /// The splash stays up long enough to see the logo spin once.
    @State private var showsSplash = !DebugLaunchOptions.skipsIntro
    /// After "Get started" on the Welcome screen, the short intro pages come next.
    @State private var showsIntroPages = false
    /// Right after "Get started", the sign-in screen opens on Create account.
    /// Only for that first time: after signing out it opens on Sign in.
    @State private var startsWithCreate = false

    var body: some View {
        Group {
            if showsSplash {
                SplashView()
            } else {
            switch auth.state {
            case .checking:
                SplashView()
            case .signedOut:
                if hasSeenIntro {
                    SignInView(startsWithCreate: startsWithCreate)
                } else if showsIntroPages {
                    IntroView {
                        startsWithCreate = true
                        withAnimation(.easeInOut) { hasSeenIntro = true }
                    }
                    .transition(.opacity)
                } else {
                    // The first time only: Welcome to RollCall.
                    WelcomeView(onGetStarted: { withAnimation(.easeInOut) { showsIntroPages = true } },
                                onSignIn: {
                                    startsWithCreate = false
                                    withAnimation(.easeInOut) { hasSeenIntro = true }
                                })
                    .transition(.opacity)
                }
            case .offline(let error):
                // There's a saved account, but the server can't be reached.
                VStack(spacing: Spacing.l) {
                    SheetMessage(error: error, action: { Task { await auth.restore() } })
                    Button("Sign out") { Task { await auth.signOut() } }
                        .buttonStyle(InkButtonStyle(prominent: false))
                }
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheetPage()
            case .signedIn(let me):
                MainTabView(me: me)
            }
            }
        }
        .animation(.snappy(duration: 0.3), value: auth.state)
        .animation(.easeInOut(duration: 0.35), value: showsSplash)
        .task { await auth.restore() }
        .task {
            try? await Task.sleep(for: .seconds(1.9))
            showsSplash = false
        }
    }
}

struct MainTabView: View {
    let me: Me
    @Environment(AuthStore.self) private var auth
    @State private var store = IncidentStore()
    @State private var selection: RootTab = DebugLaunchOptions.startTab

    enum RootTab: String, Hashable {
        case map, rollCall, community

        /// The pill's color on each tab: Map green, Roll Call red, Community
        /// orange. They're a bit deeper than the system colors so the white
        /// label on top is easy to read.
        var color: Color {
            switch self {
            case .map: Color(red: 0.12, green: 0.55, blue: 0.27)
            case .rollCall: Color(red: 0.82, green: 0.17, blue: 0.16)
            case .community: Color(red: 0.84, green: 0.40, blue: 0.0)
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            IncidentMapView(store: store)
                .roomForTabBar(extra: Spacing.s)   // Report incident sits just above the bar
                .tag(RootTab.map)

            RollCallTabView()
                .sheetBrand()
                .roomForTabBar()
                .tag(RootTab.rollCall)

            if !me.isResponder {
                CommunityTabView()
                    .sheetBrand()
                    .roomForTabBar()
                    .tag(RootTab.community)
            }
        }
        // Our own bar instead of the system's glass one (see SlidingTabBar.swift).
        // TabView still keeps every tab's screen alive, so switching back is
        // instant and nothing reloads.
        .overlay(alignment: .bottom) {
            SlidingTabBar(selection: $selection, items: tabs)
                .padding(.bottom, Spacing.xs)
        }
        // Signed up as a first responder: the application comes right next.
        .sheet(isPresented: Bindable(auth).opensResponderApplication) {
            ResponderApplicationView().sheetBrand()
        }
    }

    private var tabs: [SlidingTabBar<RootTab>.Item] {
        var items: [SlidingTabBar<RootTab>.Item] = [
            .init(tab: .map, title: "Map", color: RootTab.map.color, identifier: "tab_map"),
            .init(tab: .rollCall, title: "Roll Call", color: RootTab.rollCall.color, identifier: "tab_rollCall"),
        ]
        if !me.isResponder {
            items.append(.init(tab: .community, title: "Community", color: RootTab.community.color,
                               badge: me.community?.status == .pending ? 1 : 0, identifier: "tab_community"))
        }
        return items
    }
}

private extension View {
    /// Hide the system tab bar on this tab, and keep the bottom of the screen
    /// free for our own bar, so buttons and lists stay above it.
    /// `extra` is room on top of the bar's height: plenty on scrolling pages,
    /// so the last button (like Leave community) scrolls well clear of it,
    /// and just a little on the map.
    func roomForTabBar(extra: CGFloat = 72) -> some View {
        self
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: SlidingTabBar<MainTabView.RootTab>.height + extra)
            }
    }
}
