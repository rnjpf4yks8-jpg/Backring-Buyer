import SwiftUI

/// Administrator only: add people, approve or decline people asking to be vets, bloodstock agents or
/// staff, change anyone's role, and delete accounts.
struct PeopleView: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var working: Set<String> = []
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { adding = true } label: {
                        Label("Add a person", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("Make an account for a vet, bloodstock agent, staff member or buyer yourself, with their role. They get an email to set their password.")
                }

                if store.roleRequests.isEmpty {
                    Section("Requests") {
                        Text("No one is waiting for approval.").foregroundStyle(Theme.slate)
                    }
                } else {
                    Section {
                        ForEach(store.roleRequests, id: \.uid) { person in requestRow(person) }
                    } header: {
                        Text("Requests (\(store.roleRequests.count))")
                    } footer: {
                        Text("Approved people get their role right away. Declined people stay buyers. Either way they get a notification.")
                    }
                }

                Section("Everyone (\(store.people.count))") {
                    ForEach(filteredPeople, id: \.uid) { person in
                        NavigationLink {
                            PersonDetail(uid: person.uid)
                        } label: {
                            PersonRow(person: person, isYou: person.uid == store.user?.uid)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Name or email")
            .refreshable { await store.loadPeople() }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .overlay(alignment: .bottom) { ErrorBanner() }
            .task { await store.loadPeople() }
            .sheet(isPresented: $adding) { AddPersonSheet() }
        }
    }

    private var filteredPeople: [AppUser] {
        let term = search.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return store.people }
        return store.people.filter {
            $0.name.localizedCaseInsensitiveContains(term) || ($0.email ?? "").localizedCaseInsensitiveContains(term)
        }
    }

    private func requestRow(_ person: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PersonRow(person: person, isYou: false)
            if working.contains(person.uid) {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 12) {
                    Button {
                        Task { await act(on: person) { await store.approve(person) } }
                    } label: {
                        Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                    Button {
                        Task { await act(on: person) { await store.decline(person) } }
                    } label: {
                        Label("Decline", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func act(on person: AppUser, _ work: () async -> Void) async {
        working.insert(person.uid)
        await work()
        working.remove(person.uid)
    }
}

/// Name, email, role, and what they asked for.
private struct PersonRow: View {
    let person: AppUser
    let isYou: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isYou ? "\(person.name) (you)" : person.name).foregroundStyle(Theme.ink)
            if let email = person.email, !email.isEmpty {
                Text(email).font(.footnote).foregroundStyle(Theme.slate)
            }
            HStack(spacing: 6) {
                Text(person.role.label)
                if let asked = person.requestedRole {
                    Text("· wants to be \(asked.label.lowercased())").foregroundStyle(Theme.amber)
                }
                if let when = person.requestedAt, person.requestedRole != nil {
                    Text(when, format: .relative(presentation: .named)).foregroundStyle(Theme.slate)
                }
            }
            .font(.footnote.weight(.medium))
        }
    }
}

/// One person: change their role or delete their account.
private struct PersonDetail: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let uid: String
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var sendingReset = false
    @State private var resetSent = false

    var body: some View {
        Form {
            if let person = store.people.first(where: { $0.uid == uid }) {
                let isYou = person.uid == store.user?.uid
                Section {
                    LabeledContent("Name", value: person.name)
                    if let email = person.email { LabeledContent("Email", value: email) }
                    if let slot = OpinionSlot.allCases.first(where: { store.sale.member($0)?.uid == person.uid }) {
                        LabeledContent("Posts in \(store.sale.name)", value: slot.title)
                    }
                }

                if let asked = person.requestedRole {
                    Section {
                        Button("Approve as \(asked.label.lowercased())") { Task { await store.approve(person) } }
                            .foregroundStyle(Theme.green)
                        Button("Decline", role: .destructive) { Task { await store.decline(person) } }
                    } header: {
                        Text("Asked to be \(asked.label.lowercased())")
                    }
                }

                Section {
                    Picker("Role", selection: Binding(
                        get: { person.role },
                        set: { role in Task { await store.changeRole(of: person, to: role) } })) {
                        ForEach(Role.all, id: \.self) { Text($0.label).tag($0) }
                    }
                    .disabled(isYou)
                } footer: {
                    Text(isYou
                         ? "You can’t change your own role here."
                         : "\(person.role.abilities) Change it to Buyer to take away vet, agent or staff access.")
                }

                if !isYou, let email = person.email, !email.isEmpty {
                    Section {
                        Button {
                            sendingReset = true
                            Task {
                                resetSent = await store.sendPasswordReset(email: email)
                                sendingReset = false
                            }
                        } label: {
                            if sendingReset {
                                ProgressView()
                            } else if resetSent {
                                Label("Password email sent", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                            } else {
                                Label("Email a link to set their password", systemImage: "envelope")
                            }
                        }
                        .disabled(sendingReset || resetSent)
                    } footer: {
                        Text("For someone you added who didn’t get the first email, or who forgot their password. Ask them to check junk mail.")
                    }
                }

                if !isYou {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            if deleting { ProgressView() } else { Label("Delete account", systemImage: "trash") }
                        }
                        .disabled(deleting || person.role == .admin)
                    } footer: {
                        Text(person.role == .admin
                             ? "Change this administrator to another role before deleting the account."
                             : "Removes their sign-in, profile and purchases, and takes them off every panel. Opinions they already posted stay. This can’t be undone.")
                    }
                    .confirmationDialog("Delete \(person.name)’s account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete account", role: .destructive) {
                            deleting = true
                            Task {
                                let deleted = await store.deleteAccount(person)
                                deleting = false
                                if deleted { dismiss() }
                            }
                        }
                    } message: {
                        Text("They won’t be able to sign in again with this account. This can’t be undone.")
                    }
                }
            } else {
                Text("This account no longer exists.").foregroundStyle(Theme.slate)
            }
        }
        .navigationTitle("Person")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Administrator: makes an account for someone else, with their role, so they don't have to sign up
/// and wait for approval. They get an email to choose their password, or the administrator gives them one.
struct AddPersonSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var role: Role = .vet
    @State private var password = ""
    @State private var triedAdding = false
    @State private var working = false
    @State private var problem: String?
    @State private var added: AppUser?
    @State private var emailed = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var emailLooksRight: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !trimmedEmail.contains(" ")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let added {
                    Section {
                        Label("\(added.name) is set up as \(asWho(added.role)).", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                        Text(emailed
                             ? "They’ll get an email with a link to choose their password (ask them to check junk mail). Then they sign in on the Account screen with \(added.email ?? "their email")."
                             : "Give them the password you typed. They sign in on the Account screen with \(added.email ?? "their email").")
                            .foregroundStyle(Theme.slate)
                        if added.role == .vet || added.role == .agent {
                            Text("To have them post on a sale, open the sale and put them on its Panel (Vet 1, Vet 2, BS1 or BS2).")
                                .foregroundStyle(Theme.slate)
                        }
                    }
                    Section {
                        Button("Add another person") { reset() }
                    }
                } else {
                    Section {
                        TextField("Name, e.g. Dr. Jane Smith", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                        if triedAdding && trimmedName.isEmpty {
                            Text("Enter their name.").font(Theme.sans(14)).foregroundStyle(Theme.red)
                        }
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if triedAdding && !emailLooksRight {
                            Text("Enter their email address.").font(Theme.sans(14)).foregroundStyle(Theme.red)
                        }
                    } header: {
                        Text("Person")
                    }

                    Section {
                        Picker("Role", selection: $role) {
                            ForEach(Role.all, id: \.self) { Text($0.label).tag($0) }
                        }
                    } footer: {
                        Text(role.abilities)
                    }

                    Section {
                        SecureField("Password (optional)", text: $password)
                            .textContentType(.newPassword)
                        if triedAdding && !password.isEmpty && password.count < 6 {
                            Text("Passwords are at least 6 characters.").font(Theme.sans(14)).foregroundStyle(Theme.red)
                        }
                    } footer: {
                        Text("Leave blank and they’ll get an email to choose their own password. Or type one (at least 6 characters) to give them yourself.")
                    }

                    if let problem {
                        Section { Text(problem).foregroundStyle(Theme.red) }
                    }
                }
            }
            .navigationTitle("Add person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if added == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if working { ProgressView() } else { Button("Add") { add() } }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .interactiveDismissDisabled(working)
        }
    }

    private func add() {
        triedAdding = true
        problem = nil
        guard !trimmedName.isEmpty, emailLooksRight, password.isEmpty || password.count >= 6 else { return }
        if store.people.contains(where: { $0.email?.lowercased() == trimmedEmail.lowercased() }) {
            problem = "\(trimmedEmail) already has an account. Find them under Everyone to change their role."
            return
        }
        working = true
        Task {
            let person = await store.addPerson(name: trimmedName, email: trimmedEmail, role: role, password: password)
            working = false
            if let person {
                emailed = password.isEmpty
                added = person
            } else {
                problem = store.errorMessage ?? "Couldn’t add them. Try again."
                store.errorMessage = nil
            }
        }
    }

    private func asWho(_ role: Role) -> String {
        switch role {
        case .buyer: "a buyer"
        case .vet: "a vet"
        case .agent: "a bloodstock agent"
        case .staff: "Backring Buyer staff"
        case .admin: "an administrator"
        }
    }

    private func reset() {
        name = ""
        email = ""
        password = ""
        role = .vet
        triedAdding = false
        problem = nil
        added = nil
    }
}
