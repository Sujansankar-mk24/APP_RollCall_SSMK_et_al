//
//  SignInViewModel.swift
//  RollCall
//
//  What's typed on the sign-in screen, and whether the server can be reached.
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
    /// Signing up with an email that already has an account: offer "Sign in instead".
    private(set) var emailAlreadyUsed = false

    /// True if the server couldn't be reached.
    private(set) var serverUnreachable = false
    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }

    static let minimumPasswordLength = 8

    /// Something like name@example.com (the server checks it properly).
    var emailLooksRight: Bool {
        let parts = email.trimmed.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[1].hasSuffix(".") && !email.contains(" ")
    }

    var passwordIsLongEnough: Bool { password.count >= Self.minimumPasswordLength }

    var canSubmit: Bool {
        switch mode {
        case .signIn: return emailLooksRight && !password.isEmpty && !isWorking
        case .createAccount:
            return !name.trimmed.isEmpty && emailLooksRight && passwordIsLongEnough && !isWorking
        }
    }

    /// Anything typed changes, so an old error no longer applies.
    func edited() {
        error = nil
        emailAlreadyUsed = false
    }

    /// From "that email already has an account": it's probably theirs, so
    /// switch to Sign in with the same email and password, and try it.
    func signInInstead(with auth: AuthStore) async {
        mode = .signIn
        await submit(with: auth)
    }

    func submit(with auth: AuthStore) async {
        isWorking = true
        edited()
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn: try await auth.signIn(email: email.trimmed, password: password)
            case .createAccount: try await auth.signUp(name: name.trimmed, email: email.trimmed, password: password)
            }
        } catch {
            self.error = error
            if mode == .createAccount, case .refused(let reason) = error, reason.contains("already") {
                emailAlreadyUsed = true
            }
        }
    }

    // MARK: - Server check

    /// Is the server reachable? (If not, the screen says so instead of
    /// letting sign-in fail with a confusing error.)
    func checkServer() async {
        serverUnreachable = !(await api.isRollCallServer(at: AppConfig.apiBaseURL))
    }
}
