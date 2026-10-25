import SwiftUI

/// Sign in, create an account as a buyer, vet, agent or staff, or (in demo mode) switch between sample people.
struct AccountView: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: Role = .buyer
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = store.user {
                    Section {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Role", value: user.role.label)
                        if !user.isApproved {
                            LabeledContent("Account", value: user.accountStatus.label)
                        }
                        if let slot = OpinionSlot.allCases.first(where: { store.isAuthor($0) }) {
                            LabeledContent("Posts", value: slot.title)
                        }
                    } header: {
                        Text("Signed in")
                    } footer: {
                        switch user.accountStatus {
                        case .pending: Text("HAINTEL will check your account and approve your \(user.role.label) account. Until then you can browse the free catalog info.")
                        case .rejected: Text("HAINTEL didn’t approve this account. You can still browse the free catalog info. Contact HAINTEL if this is a mistake.")
                        case .approved: EmptyView()
                        }
                    }
                }

                if store.isDemo {
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
                } else if store.user == nil {
                    Section {
                        Picker("", selection: $creating) {
                            Text("Sign in").tag(false)
                            Text("Create account").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if creating {
                            TextField("Your name", text: $name).textContentType(.name)
                        }
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(creating ? .newPassword : .password)
                    } footer: {
                        Text("Catalog info is free. Vet and agent opinions are paid with the card on your Apple ID, so there’s no card to enter here.")
                    }
                    if creating {
                        Section {
                            Picker("I am a", selection: $role) {
                                ForEach(Role.signUpChoices, id: \.self) { Text($0.label).tag($0) }
                            }
                        } footer: {
                            Text(role.needsApproval
                                 ? "\(role.signUpDetail) HAINTEL approves \(role.label) accounts before they can do this."
                                 : role.signUpDetail)
                        }
                    }
                    Section {
                        Button {
                            working = true
                            Task {
                                if creating {
                                    await store.createAccount(name: name, email: email, password: password, role: role)
                                } else {
                                    await store.signIn(email: email, password: password)
                                }
                                working = false
                                if store.user != nil { dismiss() }
                            }
                        } label: {
                            if working { ProgressView() } else { Text(creating ? "Create account" : "Sign in") }
                        }
                        .disabled(working || email.isEmpty || password.count < 6 || (creating && name.isEmpty))
                    }
                }

                if !store.isDemo, store.user != nil {
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

    private func personDetail(_ person: AppUser) -> String {
        if !person.isApproved { return "\(person.role.label) · \(person.accountStatus.label)" }
        if let slot = OpinionSlot.allCases.first(where: { store.sale.member($0)?.uid == person.uid }) {
            return "\(person.role.label) · posts \(slot.title)"
        }
        return person.role.label
    }
}
