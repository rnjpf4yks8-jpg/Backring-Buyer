import SwiftUI

/// Administrator only: approve or decline people asking to be vets, bloodstock agents or staff,
/// change anyone's role, and delete accounts.
struct PeopleView: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var working: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
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

    private let roles: [Role] = [.buyer, .vet, .agent, .staff, .admin]

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
                        ForEach(roles, id: \.self) { Text($0.label).tag($0) }
                    }
                    .disabled(isYou)
                } footer: {
                    Text(isYou
                         ? "You can’t change your own role here."
                         : "Change it to Buyer to take away vet, agent or staff access. Administrators can do everything you can.")
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
