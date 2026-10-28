import SwiftUI

/// Type in (or correct) the race the horse is entered in, or remove it.
struct EntrySheet: View {
    let horse: Horse
    @Environment(StableStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var track = "DED"
    @State private var race = ""
    @State private var postTime = ""
    @State private var post = ""
    @State private var morningLine = ""
    @State private var jockey = ""
    @State private var weight = ""
    @State private var distance = ""
    @State private var surface = "D"
    @State private var type = "MSW"
    @State private var classText = ""
    @State private var purse = ""
    @State private var field = ""
    @State private var conditions = ""
    @State private var scratched = false
    @State private var loaded = false
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Race") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Track", selection: $track) {
                        ForEach(Track.byName) { t in Text(t.name).tag(t.code) }
                        if Track.find(track) == nil { Text(track).tag(track) }
                    }
                    TextField("Race number", text: $race).keyboardType(.numberPad)
                    TextField("Post time (e.g. 3:45 PM)", text: $postTime)
                    TextField("Distance in furlongs (1 mile = 8)", text: $distance).keyboardType(.decimalPad)
                    Picker("Surface", selection: $surface) {
                        Text("Dirt").tag("D")
                        Text("Turf").tag("T")
                        Text("Synthetic").tag("A")
                    }
                    Picker("Race type", selection: $type) {
                        ForEach(DRF.typeOrder, id: \.self) { k in Text(DRF.typeWord[k] ?? k).tag(k) }
                    }
                    TextField("Class (e.g. Md 30000)", text: $classText)
                    TextField("Purse ($)", text: $purse).keyboardType(.numberPad)
                    TextField("Horses entered", text: $field).keyboardType(.numberPad)
                }
                Section(horse.name) {
                    TextField("Post position", text: $post).keyboardType(.numberPad)
                    TextField("Morning line (e.g. 5-2)", text: $morningLine)
                    TextField("Jockey", text: $jockey)
                    TextField("Weight", text: $weight).keyboardType(.numberPad)
                    Toggle("Scratched", isOn: $scratched)
                }
                Section("Conditions") {
                    TextField("Conditions", text: $conditions, axis: .vertical).lineLimit(2...6)
                }
                if horse.entry != nil {
                    Section {
                        Button("Remove this entry", role: .destructive) { Task { await save(nil) } }
                    }
                }
            }
            .navigationTitle("Entry for \(horse.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save") { Task { await save(entry()) } } }
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .onAppear(perform: load)
        }
    }

    private static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces))
    }

    private static func whole(_ s: String) -> Int? { number(s).map { Int($0.rounded()) } }

    private static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let e = horse.entry else {
            track = Track.find(horse.lastRace?.track)?.code ?? Track.find(horse.homeTrack)?.code ?? "DED"
            return
        }
        date = Dates.date(e.date) ?? Date()
        track = e.track ?? "DED"
        race = e.race.map(String.init) ?? ""
        postTime = e.postTime ?? ""
        post = e.postPosition.map(String.init) ?? ""
        morningLine = e.morningLine ?? ""
        jockey = e.jockey ?? ""
        weight = e.weight.map(String.init) ?? ""
        distance = e.distanceF.map { DRF.trimmed($0) } ?? ""
        surface = e.surface ?? "D"
        type = e.type ?? "OTHER"
        classText = e.classText ?? ""
        purse = e.purse.map { DRF.trimmed($0) } ?? ""
        field = e.fieldSize.map(String.init) ?? ""
        conditions = e.conditions ?? ""
        scratched = e.scratched ?? false
    }

    private func entry() -> Entry {
        var e = horse.entry ?? Entry(date: Dates.from(date))
        e.date = Dates.from(date)
        e.track = track
        e.trackName = Track.find(track)?.name
        e.race = Self.whole(race)
        e.postTime = Self.clean(postTime)
        e.postPosition = Self.whole(post)
        e.morningLine = Self.clean(morningLine)
        e.jockey = Self.clean(jockey)
        e.weight = Self.whole(weight)
        e.distanceF = Self.number(distance)
        e.surface = surface
        e.type = type
        e.classText = Self.clean(classText)
        e.purse = Self.number(purse)
        e.fieldSize = Self.whole(field)
        e.conditions = Self.clean(conditions)
        e.scratched = scratched
        e.source = e.source ?? "hand"
        e.updatedAt = Dates.stamp()
        return e
    }

    private func save(_ entry: Entry?) async {
        saving = true
        defer { saving = false }
        do {
            try await store.save(entry: entry, for: horse.id)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
