import SwiftUI

/// Every horse in the stable with its record and last race. Tap one for its PPs and best races.
struct HorseListView: View {
    @Environment(StableStore.self) private var store
    @State private var search = ""
    @State private var adding = false
    @State private var deleting: Horse?
    @State private var filling = false

    private var shown: [Horse] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? store.horses : store.horses.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var bookRaces: Int { store.books.reduce(0) { $0 + $1.races.count } }

    var body: some View {
        List {
            if !store.horsesLoaded {
                HStack { Spacer(); ProgressView("Loading your stable…"); Spacer() }
                    .listRowBackground(Color.clear)
            } else if store.horses.isEmpty {
                emptyStable
            } else {
                Section {
                    ForEach(shown) { horse in
                        NavigationLink(value: horse.id) { HorseRow(horse: horse) }
                            .swipeActions {
                                Button("Delete", role: .destructive) { deleting = horse }
                            }
                    }
                } header: {
                    Text("\(store.horses.count) horse\(store.horses.count == 1 ? "" : "s")"
                         + (bookRaces > 0 ? " · \(bookRaces) condition-book races loaded" : ""))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .searchable(text: $search, prompt: "Find a horse")
        .navigationTitle("Stable PPs")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if let email = store.email { Text(email) }
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { store.signOut() }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    BooksView()
                } label: {
                    Label("Condition books", systemImage: "book")
                }
                Button { adding = true } label: { Label("Add horse", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) { HorseEditSheet(horse: nil) }
        .confirmationDialog("Delete \(deleting?.name ?? "this horse")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let horse = deleting else { return }
                Task {
                    do { try await store.delete(horse) } catch { store.show(error) }
                }
            }
        } message: {
            Text("The horse and its race lines come out of your stable. This can’t be undone.")
        }
    }

    private var emptyStable: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("No horses yet").font(.headline)
                Text("Add your 33 horses from your Equibase Virtual Stable list in one tap, or add horses one at a time.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Button {
                    Task {
                        filling = true
                        defer { filling = false }
                        do { try await store.addStableList() } catch { store.show(error) }
                    }
                } label: {
                    HStack {
                        Text("Add my 33 horses")
                        if filling { ProgressView().tint(.white) }
                    }
                }
                .buttonStyle(ActionButtonStyle(primary: true))
                .disabled(filling)
                Button("Add one horse") { adding = true }
                    .buttonStyle(ActionButtonStyle())
            }
            .padding(.vertical, 6)
        }
    }
}

struct HorseRow: View {
    let horse: Horse

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(horse.name).font(Theme.display(21)).foregroundStyle(Theme.ink)
                Spacer()
                if let record = horse.record, record.starts > 0 {
                    Text(Records.text(record)).font(Theme.data(13, .semibold)).foregroundStyle(Theme.turf)
                }
            }
            Text(subtitle).font(.footnote).foregroundStyle(Theme.muted)
            if let last = horse.lastRace, let date = last.date {
                Text(lastText(last, date))
                    .font(Theme.data(13))
                    .foregroundStyle(Theme.ink)
            } else {
                Text("No races in the app yet").font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let age = Matching.ageOn(horse, Dates.today()) { parts.append("\(age)yo") }
        if let sex = horse.sex, let word = DRF.sexWord[sex] { parts.append(word) }
        if let trainer = horse.trainer, !trainer.isEmpty { parts.append("Tr: \(trainer)") }
        return parts.joined(separator: " · ")
    }

    private func lastText(_ last: Horse.LastRace, _ date: String) -> String {
        var parts = ["\(Dates.pp(date)) \(last.race.map(String.init) ?? "")\(DRF.trk(last.track))"]
        parts.append("\(DRF.dist(last.distanceF)) \(DRF.surfaceWord(last.surface))")
        if let finish = last.finish { parts.append(DRF.ordinal(finish)) }
        if let cls = last.classText, !cls.isEmpty { parts.append(cls) }
        return parts.joined(separator: " · ")
    }
}
