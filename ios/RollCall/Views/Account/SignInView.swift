//
//  SignInView.swift
//  RollCall
//
//  Shown only when no account is saved on this phone (the first time, or after
//  signing out). Sign in, create an account, or open a fictional demo account.
//

import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @State private var viewModel = SignInViewModel()
    @State private var showsAllDemoAccounts = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                form
                demoSection
            }
            .padding(Spacing.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheetPage()
        .task { await viewModel.loadDemoAccounts() }
        .sheet(isPresented: $showsAllDemoAccounts) {
            DemoAccountsSheet(accounts: viewModel.demoAccounts) { account in
                showsAllDemoAccounts = false
                Task { await viewModel.open(account, with: auth) }
            }
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

            VStack(spacing: Spacing.l) {
                if viewModel.mode == .createAccount {
                    TextField("Your name", text: $viewModel.name)
                        .textContentType(.name)
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .email }
                        .authField()
                        .accessibilityIdentifier("signUpName")
                }
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
                SecureField(viewModel.mode == .createAccount ? "Password (at least 8 characters)" : "Password",
                            text: $viewModel.password)
                    .textContentType(viewModel.mode == .createAccount ? .newPassword : .password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .authField()
                    .accessibilityIdentifier("passwordField")
            }

            if let error = viewModel.error {
                Label(error.message, systemImage: "exclamationmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(.systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("signInError")
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

    @ViewBuilder
    private var demoSection: some View {
        if !viewModel.featured.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Trying the demo?")
                Text("Open a fictional account with one tap. Every person and address in the demo is made up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Spacing.s)
                RuleLine()
                ForEach(viewModel.featured) { account in
                    Button { Task { await viewModel.open(account, with: auth) } } label: {
                        DemoAccountRow(account: account)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("demo_\(account.kind.rawValue)")
                }
                Button("All demo accounts") { showsAllDemoAccounts = true }
                    .font(.callout.weight(.semibold))
                    .underline()
                    .frame(minHeight: minimumTapSize)
            }
            .disabled(viewModel.isWorking)
        }
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        focused = nil
        Task { await viewModel.submit(with: auth) }
    }
}

struct DemoAccountRow: View {
    let account: DemoAccount

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: account.kind.symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.4), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.headline)
                Text(account.detail.isEmpty ? String(localized: account.kind.title)
                                            : "\(String(localized: account.kind.title)) · \(account.detail)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.headline).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .sheetRow()
        .accessibilityElement(children: .combine)
    }
}

/// Every fictional demo account, grouped by kind.
struct DemoAccountsSheet: View {
    let accounts: [DemoAccount]
    let onPick: (DemoAccount) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach([DemoAccount.Kind.resident, .volunteer, .responder], id: \.self) { kind in
                    let group = accounts.filter { $0.kind == kind }
                    if !group.isEmpty {
                        Section(String(localized: kind.title)) {
                            ForEach(group) { account in
                                Button { onPick(account) } label: { DemoAccountRow(account: account) }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .navigationTitle("Demo accounts")
            .navigationBarTitleDisplayMode(.inline)
            .sheetPage()
        }
    }
}

private extension View {
    /// A roomy text field with a line to write on, like a paper form.
    func authField() -> some View {
        self
            .font(.title3)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 54)
            .background(Color.paperRaised)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.ink).frame(height: 2) }
    }
}

#Preview {
    SignInView().environment(AuthStore())
}
