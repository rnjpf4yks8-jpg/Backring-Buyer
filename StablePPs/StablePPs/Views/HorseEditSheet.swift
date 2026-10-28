import SwiftUI

/// Add a horse, or edit or delete one.
struct HorseEditSheet: View {
    let horse: Horse?
    @Environment(StableStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sex = "F"
    @State private var foalYear = ""
    @State private var color = ""
    @State private var stateBred = ""
    @State private var sire = ""
    @State private var dam = ""
    @State private var damSire = ""
    @State private var breeder = ""
    @State private var trainer = ""
    @State private var owner = ""
    @State private var equibase = ""
    @State private var homeTrack = ""
    @State private var knownStarts = ""
    @State private var knownWins = ""
    @State private var notes = ""
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var problem: String?

    static let states = ["AL", "AR", "AZ", "CA", "CO", "FL", "GA", "IA", "IL", "IN", "KY", "LA", "MD", "MI", "MN", "NE",
                         "NJ", "NM", "NY", "OH", "OK", "PA", "TX", "VA", "WA", "WV", "ON"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                    Picker("Sex", selection: $sex) {
                        ForEach(["F", "C", "G", "R", "M", "H"], id: \.self) { s in
                            Text((DRF.sexWord[s] ?? s).capitalized).tag(s)
                        }
                    }
                    TextField("Foaling year (e.g. 2023)", text: $foalYear).keyboardType(.numberPad)
                    TextField("Color", text: $color)
                    Picker("State-bred", selection: $stateBred) {
                        Text("Not set").tag("")
                        ForEach(Self.states, id: \.self) { Text($0).tag($0) }
                        if !stateBred.isEmpty && !Self.states.contains(stateBred) { Text(stateBred).tag(stateBred) }
                    }
                }
                Section("Breeding and connections") {
                    TextField("Sire", text: $sire)
                    TextField("Dam", text: $dam)
                    TextField("Dam's sire", text: $damSire)
                    TextField("Breeder", text: $breeder)
                    TextField("Trainer", text: $trainer)
                    TextField("Owner", text: $owner)
                }
                Section {
                    TextField("https://www.equibase.com/profiles/Results.cfm?…", text: $equibase)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Equibase page")
                } footer: {
                    Text("Find the horse on Equibase, copy the page link from Safari and paste it here. Open on Equibase then goes straight to the horse.")
                }
                Section {
                    Picker("Home track", selection: $homeTrack) {
                        Text("Not set").tag("")
                        ForEach(Track.byName) { t in Text(t.name).tag(t.code) }
                    }
                    TextField("Lifetime starts", text: $knownStarts).keyboardType(.numberPad)
                    TextField("Lifetime wins", text: $knownWins).keyboardType(.numberPad)
                } header: {
                    Text("For the race search")
                } footer: {
                    Text("Home track is where an unraced horse is stabled; best races are searched within 200 miles of it. Lifetime starts and wins only matter when not every start is in the app.")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6)
                }
                if horse != nil {
                    Section {
                        Button("Delete horse", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(horse == nil ? "Add a horse" : "Edit \(horse?.name ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(horse == nil ? "Add" : "Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog("Delete \(horse?.name ?? "this horse")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await delete() } }
            } message: {
                Text("The horse and its race lines come out of your stable. This can’t be undone.")
            }
            .onAppear(perform: load)
            .alert("Couldn’t save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let h = horse else { return }
        name = h.name
        sex = h.sex ?? "F"
        foalYear = h.foalYear.map(String.init) ?? ""
        color = h.color ?? ""
        stateBred = h.stateBred ?? ""
        sire = h.sire ?? ""
        dam = h.dam ?? ""
        damSire = h.damSire ?? ""
        breeder = h.breeder ?? ""
        trainer = h.trainer ?? ""
        owner = h.owner ?? ""
        equibase = h.equibaseUrl ?? ""
        homeTrack = h.homeTrack ?? ""
        knownStarts = h.known?.starts.map(String.init) ?? ""
        knownWins = h.known?.wins.map(String.init) ?? ""
        notes = h.notes ?? ""
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let link = equibase.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty && !Equibase.isEquibase(link) {
            problem = "The Equibase page has to be an equibase.com link (copy it from Safari's address bar)."
            return
        }
        var h = horse ?? Horse(id: store.newHorseID(for: trimmedName), name: trimmedName)
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        h.name = trimmedName
        h.sex = sex
        h.foalYear = Int(foalYear.trimmingCharacters(in: .whitespaces))
        h.color = clean(color)
        h.stateBred = clean(stateBred)
        h.sire = clean(sire)
        h.dam = clean(dam)
        h.damSire = clean(damSire)
        h.breeder = clean(breeder)
        h.trainer = clean(trainer)
        h.owner = clean(owner)
        h.equibaseUrl = clean(link)
        h.homeTrack = clean(homeTrack)
        let starts = Int(knownStarts.trimmingCharacters(in: .whitespaces))
        let wins = Int(knownWins.trimmingCharacters(in: .whitespaces))
        h.known = starts == nil && wins == nil ? nil : Horse.Known(starts: starts, wins: wins)
        h.notes = clean(notes)
        saving = true
        defer { saving = false }
        do {
            try await store.save(h)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func delete() async {
        guard let horse else { return }
        do {
            try await store.delete(horse)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
