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
            VStack(spacing: Spacing.xl) {
                header
                form
                demoSection
            }
            .padding(Spacing.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .task { await viewModel.loadDemoAccounts() }
        .sheet(isPresented: $showsAllDemoAccounts) {
            DemoAccountsSheet(accounts: viewModel.demoAccounts) { account in
                showsAllDemoAccounts = false
                Task { await viewModel.open(account, with: auth) }
            }
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.m) {
            BrandMark(size: 76)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.s)
            Text("RollCall")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text("Make sure no one gets left behind.")
                .font(.title3.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(spacing: Spacing.m) {
            Picker("", selection: $viewModel.mode) {
                Text("Sign in").tag(SignInViewModel.Mode.signIn)
                Text("Create account").tag(SignInViewModel.Mode.createAccount)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("authMode")

            VStack(spacing: Spacing.m) {
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
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("signInError")
            }

            Button(action: submit) {
                HStack(spacing: Spacing.s) {
                    if viewModel.isWorking { ProgressView().tint(.white) }
                    Text(viewModel.mode == .signIn ? "Sign in" : "Create account")
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("submitAuth")

            if viewModel.mode == .createAccount {
                Text("Your password is stored scrambled, so not even RollCall can read it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.snappy(duration: 0.25), value: viewModel.mode)
    }

    @ViewBuilder
    private var demoSection: some View {
        if !viewModel.featured.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("Trying the demo?", systemImage: "theatermasks.fill")
                    .font(.headline)
                Text("Open a fictional account with one tap. Every person and address in the demo is made up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(viewModel.featured) { account in
                    Button { Task { await viewModel.open(account, with: auth) } } label: {
                        DemoAccountRow(account: account)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("demo_\(account.kind.rawValue)")
                }
                Button("All demo accounts") { showsAllDemoAccounts = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: minimumTapSize)
            }
            .card()
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
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.subheadline.weight(.semibold))
                Text(account.detail.isEmpty ? String(localized: account.kind.title)
                                            : "\(String(localized: account.kind.title)) · \(account.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
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
                            }
                        }
                    }
                }
            }
            .navigationTitle("Demo accounts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension View {
    /// A roomy text field on a card background.
    func authField() -> some View {
        self
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 52)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

#Preview {
    SignInView().environment(AuthStore())
}
