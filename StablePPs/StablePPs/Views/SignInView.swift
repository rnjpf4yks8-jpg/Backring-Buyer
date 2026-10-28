import SwiftUI

/// Sign in with the Backring Buyer email and password (same accounts), or create one.
struct SignInView: View {
    @Environment(StableStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var working = false
    @State private var message: String?
    @State private var resetSent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stable PPs")
                            .font(Theme.display(40))
                            .foregroundStyle(Theme.turf)
                        Text("Your horses' past performances, DRF style, and the best races for each within 200 miles.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                } footer: {
                    Text(creating
                         ? "Creates a new account. If you have a Backring Buyer account, sign in with it instead."
                         : "Use the same email and password as Backring Buyer.")
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Text(creating ? "Create account" : "Sign in").fontWeight(.semibold)
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working || email.isEmpty || password.isEmpty)
                    Button(creating ? "I have an account: sign in" : "Create an account") { creating.toggle() }
                    if !creating {
                        Button("Forgot password?") { Task { await reset() } }
                            .disabled(working || email.isEmpty)
                    }
                }
                if let message {
                    Section { Text(message).foregroundStyle(resetSent ? Theme.good : Theme.bad) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() async {
        working = true
        message = nil
        resetSent = false
        defer { working = false }
        do {
            if creating { try await store.createAccount(email: email, password: password) }
            else { try await store.signIn(email: email, password: password) }
        } catch {
            message = error.localizedDescription
        }
    }

    private func reset() async {
        working = true
        defer { working = false }
        do {
            try await store.sendPasswordReset(email: email)
            resetSent = true
            message = "Check your email for a link to choose a new password."
        } catch {
            resetSent = false
            message = error.localizedDescription
        }
    }
}
