//
//  SignInView.swift
//  RollCall
//
//  Shown only when no account is saved on this phone (the first time, or after
//  signing out). Sign in or create an account.
//

import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @State private var viewModel = SignInViewModel()
    @State private var choosesServer = false
    @State private var showsPassword = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                serverProblem
                form
                serverRow
            }
            .padding(Spacing.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheetPage()
        .task { await viewModel.checkServer() }
        .sheet(isPresented: $choosesServer, onDismiss: {
            Task { await viewModel.checkServer() }
        }) {
            ServerSheet()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            BrandMark(size: 56)
                .padding(.top, Spacing.xl)
            SheetTitle(title: "RollCall", kicker: String(localized: "North Texas · Emergency roll call"))
            Text("Make sure no one gets left behind.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var form: some View {
        VStack(spacing: Spacing.m) {
            SheetTabs(selection: $viewModel.mode, options: [
                (value: SignInViewModel.Mode.signIn, title: String(localized: "Sign in")),
                (value: .createAccount, title: String(localized: "Create account")),
            ], identifierPrefix: "authMode_")

            VStack(alignment: .leading, spacing: Spacing.l) {
                if viewModel.mode == .createAccount {
                    TextField("Your name", text: $viewModel.name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)   // "Jordan Tatum", never ALL CAPS
                        .autocorrectionDisabled()
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .email }
                        .authField()
                        .accessibilityIdentifier("signUpName")
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                        .authField()
                        .accessibilityIdentifier("emailField")
                    if !viewModel.email.isEmpty && focused != .email && !viewModel.emailLooksRight {
                        hint("Check the email, like name@example.com", ok: false)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    passwordField
                    if viewModel.mode == .createAccount {
                        hint(viewModel.passwordIsLongEnough
                             ? "At least 8 characters"
                             : "At least 8 characters (\(SignInViewModel.minimumPasswordLength - viewModel.password.count) more)",
                             ok: viewModel.passwordIsLongEnough)
                    }
                }
            }
            .onChange(of: viewModel.name) { viewModel.edited() }
            .onChange(of: viewModel.email) { viewModel.edited() }
            .onChange(of: viewModel.password) { viewModel.edited() }

            if let error = viewModel.error {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label(error.message, systemImage: "exclamationmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.systemRed))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("signInError")
                    if viewModel.emailAlreadyUsed {
                        Button("Sign in instead") {
                            focused = nil
                            Task { await viewModel.signInInstead(with: auth) }
                        }
                        .buttonStyle(SmallInkButtonStyle(prominent: false))
                        .accessibilityIdentifier("signInInstead")
                    }
                }
            }

            Button(action: submit) {
                HStack(spacing: Spacing.s) {
                    if viewModel.isWorking { ProgressView().tint(Color.paper) }
                    Text(viewModel.mode == .signIn ? "Sign in" : "Create account")
                }
            }
            .buttonStyle(InkButtonStyle())
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("submitAuth")

            if viewModel.mode == .createAccount {
                SheetNote(text: "Your password is stored scrambled, so not even RollCall can read it.", systemImage: "lock.fill")
            }
        }
        .animation(.snappy(duration: 0.25), value: viewModel.mode)
    }

    /// Shown only when the server can't be reached.
    @ViewBuilder
    private var serverProblem: some View {
        if viewModel.serverUnreachable {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SheetNote(text: "Can't reach the RollCall server, so signing in won't work yet. Start the backend on this Mac, or choose a shared server below.",
                          systemImage: "antenna.radiowaves.left.and.right.slash", color: Color(.systemOrange))
                Button("Try again") { Task { await viewModel.checkServer() } }
                    .buttonStyle(InkButtonStyle(prominent: false))
                    .accessibilityIdentifier("retryServer")
            }
        }
    }

    /// Which server this app talks to, and a way to change it.
    private var serverRow: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Server")
            Button { choosesServer = true } label: {
                let isThisMac = auth.serverURL == ServerSettings.thisMac
                HStack(spacing: Spacing.m) {
                    Image(systemName: isThisMac ? "desktopcomputer" : "network")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: ServerSettings.displayName(for: auth.serverURL)).font(.headline)
                        Text(isThisMac ? "Only accounts made on this Mac" : "Shared with everyone using this server")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Change").font(.callout.weight(.semibold)).underline()
                }
                .contentShape(Rectangle())
                .sheetBox(padding: Spacing.m)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("serverRow")
        }
    }

    /// The password, with a button to show or hide what's typed.
    private var passwordField: some View {
        HStack(spacing: Spacing.s) {
            Group {
                if showsPassword {
                    TextField(passwordPrompt, text: $viewModel.password)
                } else {
                    SecureField(passwordPrompt, text: $viewModel.password)
                }
            }
            .textContentType(viewModel.mode == .createAccount ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused, equals: .password)
            .submitLabel(.go)
            .onSubmit { submit() }
            .accessibilityIdentifier("passwordField")
            Button {
                showsPassword.toggle()
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: minimumTapSize, height: minimumTapSize)
            }
            .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
        }
        .authField()
    }

    private var passwordPrompt: LocalizedStringKey {
        viewModel.mode == .createAccount ? "Choose a password" : "Password"
    }

    /// A small line under a field: a green check when it's right, gray otherwise.
    private func hint(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "info.circle")
            .font(.callout)
            .foregroundStyle(ok ? Color(.systemGreen) : .secondary)
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        focused = nil
        Task { await viewModel.submit(with: auth) }
    }
}

private extension View {
    /// A roomy text field in a box, like a paper form.
    func authField() -> some View {
        self
            .font(.title3)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 54)
            .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.paperControl, style: .continuous).strokeBorder(Color.ink.opacity(0.25), lineWidth: 1))
    }
}

#Preview {
    SignInView().environment(AuthStore())
}

/// Choose the server: this Mac, or a shared one (someone's Mac shared through
/// a tunnel). The address is tested before it's used.
struct ServerSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var address = ServerSettings.isThisMac ? "" : ServerSettings.url.absoluteString
    @State private var isChecking = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text("Everyone who uses the same server sees the same accounts, households and communities.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionLabel("Shared server")
                        LabeledField(label: "Server address", prompt: "e.g. something.trycloudflare.com",
                                     text: $address, contentType: .URL, keyboard: .URL, handwritten: false,
                                     identifier: "serverAddressField")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let problem {
                            Label(problem, systemImage: "exclamationmark.circle.fill")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Color(.systemRed))
                        }
                        Button {
                            Task { await useSharedServer() }
                        } label: {
                            HStack(spacing: Spacing.s) {
                                if isChecking { ProgressView().tint(Color.paper) }
                                Text("Connect")
                            }
                        }
                        .buttonStyle(InkButtonStyle())
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
                        .accessibilityIdentifier("connectServer")
                        SheetNote(text: "The person running the server gets this address from scripts/share_server.sh and sends it to you. It changes each time they restart sharing.")
                    }

                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionLabel("This Mac")
                        Button("Use the server on this Mac") {
                            auth.switchServer(to: nil)
                            dismiss()
                        }
                        .buttonStyle(InkButtonStyle(prominent: false))
                        .accessibilityIdentifier("useThisMac")
                    }
                }
                .padding(Spacing.l)
            }
            .sheetPage()
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }.flat()
            }
        }
    }

    private func useSharedServer() async {
        problem = nil
        guard let url = ServerSettings.address(from: address) else {
            problem = String(localized: "That doesn't look like a web address.")
            return
        }
        isChecking = true
        defer { isChecking = false }
        guard await APIClient.shared.isRollCallServer(at: url) else {
            problem = String(localized: "Couldn't reach a RollCall server there. Check the address, and that sharing is still running.")
            return
        }
        auth.switchServer(to: url)
        dismiss()
    }
}
