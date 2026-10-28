import SwiftUI
import UniformTypeIdentifiers

/// One horse: breeding and record boxes, then its past performances or its best races.
struct HorseView: View {
    let horseID: String
    @Environment(StableStore.self) private var store

    enum Tab: Hashable { case pps, races }
    @State private var tab = Tab.pps
    @State private var asCards = false
    @State private var editing = false
    @State private var pasting = false
    @State private var picking = false
    @State private var addingLine = false
    @State private var editingLine: RaceLine?
    @State private var charts: ChartBatch?

    var body: some View {
        if let horse = store.horse(horseID) {
            let lines = store.lines(for: horseID)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HorseHeader(horse: horse, lines: lines)
                    Picker("Show", selection: $tab) {
                        Text("Past performances (\(lines.count))").tag(Tab.pps)
                        Text("Best races").tag(Tab.races)
                    }
                    .pickerStyle(.segmented)
                    if tab == .pps {
                        ppSection(horse, lines)
                    } else {
                        BestRacesView(horse: horse, lines: lines)
                    }
                }
                .padding(16)
            }
            .background(Theme.page)
            .navigationTitle(horse.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
            }
            .onAppear { store.watchLines(horseID) }
            .sheet(isPresented: $editing) { HorseEditSheet(horse: horse) }
            .sheet(isPresented: $pasting) { PasteChartSheet(horse: horse) }
            .sheet(isPresented: $addingLine) { LineEditSheet(horse: horse, line: nil) }
            .sheet(item: $editingLine) { line in LineEditSheet(horse: horse, line: line) }
            .sheet(item: $charts) { batch in ChartImportSheet(batch: batch) }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    let files = urls.compactMap { url -> ChartFile? in
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        guard let data = try? Data(contentsOf: url) else { return nil }
                        return ChartFile(name: url.lastPathComponent, data: data)
                    }
                    if !files.isEmpty { charts = ChartBatch(files: files, horseID: horseID) }
                case .failure(let error):
                    store.show(error)
                }
            }
        } else {
            ContentUnavailableView("Not in your stable", systemImage: "questionmark.circle",
                                   description: Text("This horse has been deleted."))
        }
    }

    @ViewBuilder
    private func ppSection(_ horse: Horse, _ lines: [RaceLine]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Link(destination: Equibase.page(for: horse)) {
                    Label("Open on Equibase", systemImage: "safari")
                }
                .buttonStyle(ActionButtonStyle())
                Button { pasting = true } label: { Label("Paste chart", systemImage: "doc.on.clipboard") }
                    .buttonStyle(ActionButtonStyle(primary: true))
                Button { picking = true } label: { Label("Chart PDFs", systemImage: "doc.richtext") }
                    .buttonStyle(ActionButtonStyle())
                Button { addingLine = true } label: { Label("By hand", systemImage: "square.and.pencil") }
                    .buttonStyle(ActionButtonStyle())
                Button { asCards.toggle() } label: {
                    Label(asCards ? "DRF lines" : "Cards", systemImage: asCards ? "tablecells" : "rectangle.grid.1x2")
                }
                .buttonStyle(ActionButtonStyle())
            }
        }
        if (horse.equibaseUrl ?? "").isEmpty {
            Note(text: "Tip: copy \(horse.name)'s Equibase page link and paste it under Edit → Equibase page. Then Open on Equibase goes straight to the horse.")
        }
        if lines.isEmpty {
            Card {
                Text("No races yet for \(horse.name)").font(.headline)
                Text("Tap **Open on Equibase**, open a race's **Chart**, and either copy its text and tap **Paste chart**, or tap Safari's Share button and pick **Stable PPs**. Each chart becomes a DRF-style line. Saved chart PDFs work too: **Chart PDFs**.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        } else if asCards {
            PPCards(lines: lines) { editingLine = $0 }
        } else {
            PPTable(lines: lines) { editingLine = $0 }
            Note(text: "Newest first. Scroll sideways for the full line; tap a line to correct it or add a Beyer figure. D dirt · T turf · A synthetic. Lengths are raised: hd head, nk neck, no nose.")
        }
    }
}

/// Name, breeding, and the record boxes over the past performances.
struct HorseHeader: View {
    let horse: Horse
    let lines: [RaceLine]

    var body: some View {
        Card {
            Text(horse.name).font(Theme.display(30)).foregroundStyle(Theme.ink)
            Text(breeding).font(.subheadline).foregroundStyle(Theme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(Records.boxes(lines, horse: horse).enumerated()), id: \.offset) { _, box in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(box.0).font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
                            Text(Records.text(box.1)).font(Theme.data(13, .semibold)).foregroundStyle(Theme.ink)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            if let notes = horse.notes, !notes.isEmpty {
                Text(notes).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    private var breeding: String {
        var parts: [String] = []
        let age = Matching.ageOn(horse, Dates.today())
        let kind = [horse.color, horse.sex.flatMap { DRF.sexWord[$0] }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let first = [kind, age.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        if !first.isEmpty { parts.append(first + (horse.foalYear.map { " (foaled \($0))" } ?? "")) }
        if let sire = horse.sire, !sire.isEmpty { parts.append("Sire: \(sire)") }
        if let dam = horse.dam, !dam.isEmpty {
            parts.append("Dam: \(dam)" + ((horse.damSire ?? "").isEmpty ? "" : " (\(horse.damSire ?? ""))"))
        }
        if let breeder = horse.breeder, !breeder.isEmpty {
            parts.append("Br: \(breeder)" + (horse.bredIn.map { " (\($0))" } ?? ""))
        } else if let bred = horse.bredIn {
            parts.append("Bred in \(bred)")
        }
        if let trainer = horse.trainer, !trainer.isEmpty { parts.append("Tr: \(trainer)") }
        if let owner = horse.owner, !owner.isEmpty { parts.append("Own: \(owner)") }
        return parts.isEmpty ? "Breeding fills in from the first chart, or tap Edit." : parts.joined(separator: " · ")
    }
}
