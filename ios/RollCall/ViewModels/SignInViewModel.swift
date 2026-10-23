//
//  SignInViewModel.swift
//  RollCall
//
//  What's typed on the sign-in screen, plus the fictional demo accounts.
//

import Foundation
import Observation

@Observable
final class SignInViewModel {
    enum Mode: Hashable { case signIn, createAccount }

    var mode: Mode = .signIn
    var name = ""
    var email = ""
    var password = ""
    private(set) var isWorking = false
    var error: APIError?

    private(set) var demoAccounts: [DemoAccount] = []
    /// True if the server couldn't be reached to list the demo accounts.
    private(set) var serverUnreachable = false
    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }

    static let minimumPasswordLength = 8

    var canSubmit: Bool {
        let emailLooksRight = email.trimmed.contains("@") && email.trimmed.contains(".")
        switch mode {
        case .signIn: return emailLooksRight && !password.isEmpty && !isWorking
        case .createAccount:
            return !name.trimmed.isEmpty && emailLooksRight && password.count >= Self.minimumPasswordLength && !isWorking
        }
    }

    func submit(with auth: AuthStore) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn: try await auth.signIn(email: email.trimmed, password: password)
            case .createAccount: try await auth.signUp(name: name.trimmed, email: email.trimmed, password: password)
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Demo accounts

    func loadDemoAccounts() async {
        do {
            demoAccounts = try await api.fetchDemoAccounts()
            serverUnreachable = false
        } catch {
            demoAccounts = []
            serverUnreachable = true
        }
    }

    /// The one-tap accounts the server picked: a resident, a volunteer from
    /// the same neighborhood, and a responder.
    var featured: [DemoAccount] {
        let order: [DemoAccount.Kind] = [.resident, .volunteer, .responder]
        return demoAccounts.filter(\.featured).sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
    }

    func open(_ account: DemoAccount, with auth: AuthStore) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await auth.signIn(demo: account)
        } catch {
            self.error = error
        }
    }
}
