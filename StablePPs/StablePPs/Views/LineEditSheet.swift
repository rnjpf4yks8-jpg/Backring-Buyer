import SwiftUI

/// Add a race line by hand, or correct one Claude read (and add a Beyer figure).
struct LineEditSheet: View {
    let horse: Horse
    let line: RaceLine?
    @Environment(StableStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var track = "DED"
    @State private var race = ""
    @State private var surface = "D"
    @State private var distance = ""
    @State private var condition = "fst"
    @State private var type = "MSW"
    @State private var classText = ""
    @State private var claim = ""
    @State private var finish = ""
    @State private var lengths = ""
    @State private var field = ""
    @State private var earnings = ""
    @State private var odds = ""
    @State private var jockey = ""
    @State private var weight = ""
    @State private var beyer = ""
    @State private var speed = ""
    @State private var comment = ""
    @State private var loaded = false
    @State private var saving = false
    @State private var problem: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if let line, let url = Equibase.chart(date: line.date, track: line.track, race: line.race) {
                    Section {
                        Link(destination: url) { Label("Open this race's chart on Equibase", systemImage: "safari") }
                    }
                }
                Section("Race") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Track", selection: $track) {
                        ForEach(Track.byName) { t in Text(t.name).tag(t.code) }
                        if Track.find(track) == nil { Text(track).tag(track) }
                    }
                    TextField("Race number", text: $race).keyboardType(.numberPad)
                    Picker("Surface", selection: $surface) {
                        Text("Dirt").tag("D")
                        Text("Turf").tag("T")
                        Text("Synthetic").tag("A")
                    }
                    TextField("Distance in furlongs (1 mile = 8)", text: $distance).keyboardType(.decimalPad)
                    TextField("Track condition (fst, gd, sly, fm, yl)", text: $condition)
                        .textInputAutocapitalization(.never)
                    Picker("Race type", selection: $type) {
                        ForEach(DRF.typeOrder, id: \.self) { k in Text(DRF.typeWord[k] ?? k).tag(k) }
                    }
                    TextField("Class as DRF prints it (Clm 16000N2L)", text: $classText)
                    TextField("Claiming price", text: $claim).keyboardType(.numberPad)
                }
                Section("Result") {
                    TextField("Finish position", text: $finish).keyboardType(.numberPad)
                    TextField("Lengths won by or beaten (2 1/2, Head)", text: $lengths)
                    TextField("Field size", text: $field).keyboardType(.numberPad)
                    TextField("Money won ($)", text: $earnings).keyboardType(.numberPad)
                    TextField("Odds", text: $odds).keyboardType(.decimalPad)
                    TextField("Jockey", text: $jockey)
                    TextField("Weight", text: $weight).keyboardType(.numberPad)
                    TextField("Beyer figure", text: $beyer).keyboardType(.numberPad)
                    TextField("Equibase Speed Figure", text: $speed).keyboardType(.numberPad)
                    TextField("Comment", text: $comment)
                }
                if line != nil {
                    Section {
                        Button("Delete this line", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(line == nil ? "Add a race" : "Edit race line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save") { Task { await save() } } }
                }
            }
            .confirmationDialog("Delete this race line?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await delete() } }
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

    private static func whole(_ s: String) -> Int? {
        number(s).map { Int($0.rounded()) }
    }

    private static func text(_ n: Double?) -> String {
        n.map { DRF.trimmed($0) } ?? ""
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let l = line else {
            track = Track.find(horse.lastRace?.track)?.code ?? Track.find(horse.homeTrack)?.code ?? "DED"
            return
        }
        date = Dates.date(l.date) ?? Date()
        track = l.track ?? "DED"
        race = l.race.map(String.init) ?? ""
        surface = l.surface ?? "D"
        distance = Self.text(l.distanceF)
        condition = l.condition ?? ""
        type = l.type ?? "OTHER"
        classText = l.classText ?? ""
        claim = Self.text(l.claimPrice)
        finish = l.finish?.pos.map(String.init) ?? ""
        lengths = l.finish?.lengths ?? ""
        field = l.fieldSize.map(String.init) ?? ""
        earnings = Self.text(l.earnings)
        odds = Self.text(l.odds)
        jockey = l.jockey ?? ""
        weight = l.weight.map(String.init) ?? ""
        beyer = l.beyer.map(String.init) ?? ""
        speed = l.speed.map(String.init) ?? ""
        comment = l.comment ?? ""
    }

    private func save() async {
        let day = Dates.from(date)
        let raceNo = Self.whole(race)
        var l = line ?? RaceLine(id: RaceLine.key(date: day, track: track, race: raceNo))
        l.date = day
        l.track = track
        l.trackName = Track.find(track)?.name
        l.race = raceNo
        l.surface = surface
        l.distanceF = Self.number(distance)
        l.condition = condition.trimmingCharacters(in: .whitespaces).lowercased()
        l.type = type
        l.classText = classText.trimmingCharacters(in: .whitespaces)
        l.claimPrice = Self.number(claim)
        l.finish = Finish(pos: Self.whole(finish), lengths: lengths.trimmingCharacters(in: .whitespaces))
        l.fieldSize = Self.whole(field)
        l.earnings = Self.number(earnings)
        l.odds = Self.number(odds)
        l.jockey = jockey.trimmingCharacters(in: .whitespaces)
        l.weight = Self.whole(weight)
        l.beyer = Self.whole(beyer)
        l.speed = Self.whole(speed)
        l.comment = comment.trimmingCharacters(in: .whitespaces)
        if l.source == nil { l.source = "hand" }
        saving = true
        defer { saving = false }
        do {
            try await store.save(l, for: horse)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func delete() async {
        guard let line else { return }
        do {
            try await store.delete(line, for: horse)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
