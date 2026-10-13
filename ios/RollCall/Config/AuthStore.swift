//
//  AuthStore.swift
//  RollCall
//
//  Who is signed in. The app asks for a sign-in only when there's no saved
//  account on this phone: the first time, or after signing out. Otherwise the
//  saved token (in the Keychain) signs in automatically when the app opens.
//
//  (Debug tip: launch with "-RCSignOut YES" to start signed out, as the UI
//  tests do.)
//

import Foundation
import Observation

@Observable
final class AuthStore {
    enum State: Equatable {
        case checking                 // looking at the saved token
        case signedOut                // show the sign-in screen
        case signedIn(Me)
        case offline(APIError)        // has a saved token, but the server can't be reached
    }

    private(set) var state: State = .checking
    /// The server this app talks to (see ServerSettings).
    private(set) var serverURL = ServerSettings.url
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "RCSignOut") { Keychain.deleteToken() }
        #endif
        APIClient.token = Keychain.loadToken()
        // If the server ever says the token is no longer valid, go back to sign-in.
        NotificationCenter.default.addObserver(forName: APIClient.signedOutNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.forgetToken() }
        }
    }

    var me: Me? {
        if case .signedIn(let me) = state { return me }
        return nil
    }

    // MARK: - Opening the app

    /// Called when the app starts: use the saved token, if there is one.
    func restore() async {
        guard APIClient.token != nil else {
            state = .signedOut
            return
        }
        await refresh()
    }

    /// Download the latest "me" (after joining the roll call, a community, ...).
    func refresh() async {
        guard APIClient.token != nil else { return }
        do {
            state = .signedIn(try await api.fetchMe())
        } catch .signedOut {
            forgetToken()
        } catch {
            if me == nil { state = .offline(error) }
        }
    }

    // MARK: - Signing in and out

    func signUp(name: String, email: String, password: String) async throws(APIError) {
        use(try await api.signUp(name: name, email: email, password: password))
    }

    func signIn(email: String, password: String) async throws(APIError) {
        use(try await api.signIn(email: email, password: password))
    }

    func signIn(demo account: DemoAccount) async throws(APIError) {
        use(try await api.signInDemo(userID: account.userId))
    }

    func signOut() async {
        try? await api.signOut()   // forget it on the server too (fine if offline)
        forgetToken()
    }

    /// Talk to a different server (nil = this Mac). A sign-in only works on
    /// the server it came from, so this also signs out on this phone.
    func switchServer(to url: URL?) {
        forgetToken()
        ServerSettings.use(url)
        serverURL = ServerSettings.url
    }

    private func use(_ response: AuthResponse) {
        Keychain.saveToken(response.token)
        APIClient.token = response.token
        state = .signedIn(response.me)
    }

    private func forgetToken() {
        Keychain.deleteToken()
        APIClient.token = nil
        state = .signedOut
    }

    // MARK: - Small account changes

    func setRollCallOptOut(_ optOut: Bool) async throws(APIError) {
        state = .signedIn(try await api.updateMe(rollCallOptOut: optOut))
    }

    func setVolunteer(_ on: Bool, city: String = "") async throws(APIError) {
        state = .signedIn(on ? try await api.becomeVolunteer(city: city) : try await api.stopVolunteering())
    }
}
