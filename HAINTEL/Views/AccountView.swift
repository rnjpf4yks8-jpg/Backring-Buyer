import SwiftUI

/// Sign in, create a buyer account, or (in demo mode) switch between sample people.
struct AccountView: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = store.user {
                    Section("Signed in") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Role", value: user.role.label)
                        if let slot = OpinionSlot.allCases.first(where: { store.isAuthor($0) }) {
                            LabeledContent("Posts", value: slot.field.title)
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
                        Text("Catalog info is free. Vet and agent opinions are paid with the card on your Apple ID, so there’s no card to enter here. Vets and agents: create an account, then HAINTEL staff add you to a sale.")
                    }
                    Section {
                        Button {
                            working = true
                            Task {
                                if creating {
                                    await store.createAccount(name: name, email: email, password: password)
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
        if let slot = OpinionSlot.allCases.first(where: { store.sale.member($0)?.uid == person.uid }) {
            return "\(person.role.label) · posts \(slot.field.title)"
        }
        return person.role.label
    }
}
