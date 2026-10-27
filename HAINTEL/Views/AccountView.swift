import SwiftUI

/// Sign in or create an account (asking to be a vet, bloodstock agent or staff if you are one),
/// ask for a role later, or (in demo mode) switch between sample people.
struct AccountView: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var signUpRole: Role = .buyer
    @State private var askFor: Role = .vet
    @State private var adminCode = ""
    @State private var claiming = false
    @State private var resetSent = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = store.user {
                    Section("Signed in") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Role", value: user.role.label)
                        if let slot = OpinionSlot.allCases.first(where: { store.isAuthor($0) }) {
                            LabeledContent("Posts", value: slot.title)
                        }
                    }
                    if store.isAdmin {
                        Section {
                            Button {
                                dismiss()
                                store.showPeople = true
                            } label: {
                                HStack {
                                    Label("People and requests", systemImage: "person.2.badge.gearshape")
                                    Spacer()
                                    if !store.roleRequests.isEmpty {
                                        Text("\(store.roleRequests.count)")
                                            .font(.footnote.bold()).foregroundStyle(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 2)
                                            .background(Theme.red, in: Capsule())
                                    }
                                }
                            }
                        } footer: {
                            Text("Add people, approve or decline vets, bloodstock agents and staff, change roles, or delete accounts. Delete a sale by pressing and holding it on the sales list.")
                        }
                    }
                }

                if !store.isDemo, let user = store.user, [.buyer, .vet, .agent].contains(user.role) {
                    roleRequestSection(user)
                }

                if store.isDemo {
                    demoPeople
                } else if store.user == nil {
                    signInForm
                }

                if !store.isDemo, store.user != nil {
                    if !store.isAdmin { adminSetup }
                    Section {
                        Button("Sign out", role: .destructive) {
                            Task {
                                await store.signOut()
                                dismiss()
                            }
                        }
                    }
                }

                if let message = store.errorMessage {
                    Section { Text(message).foregroundStyle(Theme.red) }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Sections

    private var signInForm: some View {
        Group {
            Section {
                Picker("", selection: $creating) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)
                if creating {
                    TextField("Your name", text: $name).textContentType(.name)
                    Picker("I am a", selection: $signUpRole) {
                        ForEach([Role.buyer] + Role.requestable, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(creating ? .newPassword : .password)
            } footer: {
                Text(creating && signUpRole != .buyer
                     ? "The administrator approves vets, bloodstock agents and staff. Until then you can use the app as a buyer, and you’ll get a notification when you’re approved."
                     : "Catalog info is free. Vet and agent opinions are paid with the card on your Apple ID, so there’s no card to enter here.")
            }
            Section {
                Button {
                    working = true
                    Task {
                        if creating {
                            await store.createAccount(name: name, email: email, password: password, role: signUpRole)
                        } else {
                            await store.signIn(email: email, password: password)
                        }
                        working = false
                        if store.user != nil, store.errorMessage == nil { dismiss() }
                    }
                } label: {
                    if working { ProgressView() } else { Text(creating ? "Create account" : "Sign in") }
                }
                .disabled(working || email.isEmpty || password.count < 6 || (creating && name.isEmpty))
                if !creating {
                    Button(resetSent ? "Password email sent. Check your inbox (and junk mail)." : "Forgot password? Email me a link") {
                        Task { resetSent = await store.sendPasswordReset(email: email) }
                    }
                    .font(.footnote)
                    .disabled(resetSent || !email.contains("@"))
                }
            }
        }
    }

    /// Buyers, vets and agents ask for a (different) role, or see that they're waiting.
    private func roleRequestSection(_ user: AppUser) -> some View {
        Section {
            if let asked = user.requestedRole {
                LabeledContent("Asked to be", value: asked.label)
                Text("Waiting for the administrator to approve. Until then you use the app as \(user.role.label.lowercased()).")
                    .font(.footnote).foregroundStyle(Theme.slate)
                Button("Cancel request", role: .destructive) {
                    Task { await store.requestRole(nil) }
                }
            } else {
                let choices = Role.requestable.filter { $0 != user.role }
                Picker("Role", selection: $askFor) {
                    ForEach(choices, id: \.self) { Text($0.label).tag($0) }
                }
                .onAppear { if !choices.contains(askFor) { askFor = choices.first ?? .vet } }
                Button("Ask the administrator") {
                    Task { await store.requestRole(askFor) }
                }
            }
        } header: {
            Text("Vet, bloodstock agent or staff?")
        }
    }

    /// For the owner, once: turns this account into the administrator.
    private var adminSetup: some View {
        Section {
            SecureField("Administrator code", text: $adminCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                claiming = true
                Task {
                    if await store.claimAdmin(code: adminCode) { adminCode = "" }
                    claiming = false
                }
            } label: {
                if claiming { ProgressView() } else { Text("Become administrator") }
            }
            .disabled(claiming || adminCode.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Owner setup")
        } footer: {
            Text("Only for the owner setting up Backring Buyer the first time. Everyone else asks for a role above.")
        }
    }

    private var demoPeople: some View {
        Section {
            ForEach(SampleData.people, id: \.uid) { person in
                Button {
                    Task {
                        await store.signInDemo(as: person)
                        dismiss()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(person.name).foregroundStyle(Theme.ink)
                            Text(personDetail(person)).font(.footnote).foregroundStyle(Theme.slate)
                        }
                        Spacer()
                        if store.user?.uid == person.uid {
                            Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                        }
                    }
                }
            }
        } header: {
            Text("Demo: sign in as")
        } footer: {
            Text("Firebase isn’t connected yet, so the app runs on sample data and nothing is saved after you close it.")
        }
    }

    private func personDetail(_ person: AppUser) -> String {
        if let slot = OpinionSlot.allCases.first(where: { store.sale.member($0)?.uid == person.uid }) {
            return "\(person.role.label) · posts \(slot.title)"
        }
        if let asked = person.requestedRole { return "\(person.role.label) · asked to be \(asked.label.lowercased())" }
        return person.role.label
    }
}
