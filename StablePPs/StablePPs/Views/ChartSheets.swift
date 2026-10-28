import SwiftUI
import UIKit

/// Paste a chart copied from Equibase. Optionally open a race's chart first by date, track and race number.
struct PasteChartSheet: View {
    let horse: Horse
    @Environment(StableStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var track = ""
    @State private var race = ""
    @State private var text = ""
    @State private var working = false
    @State private var status: String?
    @State private var good = false

    private var chartLink: URL? {
        Equibase.chart(date: Dates.from(date), track: track, race: Int(race.trimmingCharacters(in: .whitespaces)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Link(destination: Equibase.page(for: horse)) {
                        Label("Open \(horse.name) on Equibase", systemImage: "safari")
                    }
                } footer: {
                    Text("In Safari open the race's **Chart**, select all its text and copy it, then come back and paste it below. Or tap Safari's Share button on the chart and pick **Stable PPs**.")
                }
                Section {
                    DatePicker("Race date", selection: $date, displayedComponents: .date)
                    Picker("Track", selection: $track) {
                        Text("Pick a track").tag("")
                        ForEach(Track.byName) { t in Text(t.name).tag(t.code) }
                    }
                    TextField("Race number", text: $race).keyboardType(.numberPad)
                    if let chartLink {
                        Link(destination: chartLink) { Label("Open this chart", systemImage: "doc.text.magnifyingglass") }
                    }
                } header: {
                    Text("Or go straight to one chart")
                }
                Section("Chart text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .font(.footnote.monospaced())
                    Button {
                        if let pasted = UIPasteboard.general.string { text = pasted }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                }
                if let status {
                    Section { Text(status).foregroundStyle(good ? Theme.good : Theme.bad) }
                }
            }
            .navigationTitle("Paste a chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Read and add") { Task { await read() } }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(working)
            .onAppear {
                if track.isEmpty { track = Track.find(horse.lastRace?.track)?.code ?? "" }
            }
        }
    }

    private func read() async {
        let chart = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chart.count >= 200 else {
            good = false
            status = "Paste the whole chart first: it should include the race conditions, the horses and the fractional times."
            return
        }
        working = true
        good = false
        status = "Claude is reading the chart… about half a minute."
        defer { working = false }
        do {
            let outcome = try await store.readChart(pdf: nil, text: String(chart.prefix(150_000)), horses: [horse])
            if outcome.added.isEmpty {
                status = "Not added: " + (outcome.skipped.first ?? "\(horse.name) isn’t in this chart.")
            } else {
                good = true
                status = "Added " + outcome.added.joined(separator: "; ") + ". Paste another chart, or close."
                text = ""
            }
        } catch {
            status = error.localizedDescription
        }
    }
}

/// Reads chart PDFs (picked in Files or shared from Safari). For one horse, or for whichever of
/// your horses are named in each chart.
struct ChartImportSheet: View {
    let batch: ChartBatch
    @Environment(StableStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable {
        let id: UUID
        var name: String
        var state = "Waiting"
        var detail = ""
        var ok: Bool?
    }
    @State private var rows: [Row] = []
    @State private var running = false
    @State private var started = false

    private var horse: Horse? { batch.horseID.flatMap { store.horse($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.state)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(row.ok == true ? Theme.good : row.ok == false ? Theme.bad : Theme.muted)
                                    .frame(width: 74, alignment: .leading)
                                Text(row.name).font(.subheadline).lineLimit(1)
                                if row.ok == nil && row.state != "Waiting" { Spacer(); ProgressView() }
                            }
                            if !row.detail.isEmpty {
                                Text(row.detail).font(.footnote).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                } footer: {
                    Text(horse.map { "Claude reads each chart and writes \($0.name)'s line. About half a minute a chart." }
                         ?? "Claude finds your horses in each chart and writes their lines. About half a minute a chart.")
                }
            }
            .navigationTitle(batch.files.count == 1 ? "Reading a chart" : "Reading \(batch.files.count) charts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(running ? "Stop" : "Done") { dismiss() } }
            }
            .task {
                guard !started else { return }
                started = true
                rows = batch.files.map { Row(id: $0.id, name: $0.name) }
                await run()
            }
        }
    }

    private func set(_ i: Int, _ state: String, _ detail: String = "", ok: Bool? = nil) {
        guard rows.indices.contains(i) else { return }
        rows[i].state = state
        rows[i].detail = detail
        rows[i].ok = ok
    }

    private func run() async {
        running = true
        defer { running = false }
        // Shared from Safari into a closed app: give sign-in and the horse list a moment to load.
        for _ in 0..<50 where store.phase == .starting || (store.phase == .signedIn && !store.horsesLoaded) {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if store.phase != .signedIn {
            for i in rows.indices { set(i, "Not added", "Sign in first, then share the chart again.", ok: false) }
            return
        }
        for (i, file) in batch.files.enumerated() {
            if Task.isCancelled { return }
            set(i, "Opening")
            var list: [Horse]
            if let horse {
                list = [horse]
            } else {
                let text = StableStore.text(ofPDF: file.data)
                list = store.horsesNamed(in: text)
                if list.isEmpty {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 200 {
                        set(i, "Skipped", "None of your horses are named in this chart.", ok: false)
                        continue
                    }
                    list = store.horses   // no readable text: let Claude look for all of them
                }
            }
            if list.isEmpty {
                set(i, "Not added", "Add your horses first.", ok: false)
                continue
            }
            set(i, "Reading", list.count == 1 ? "Looking for \(list[0].name)…" : "Looking for \(list.count) of your horses…")
            do {
                let outcome = try await store.readChart(pdf: file.data, text: nil, horses: list)
                if outcome.added.isEmpty {
                    set(i, "Skipped", outcome.skipped.first ?? "None of your horses ran in this chart.", ok: false)
                } else {
                    set(i, "Added", outcome.added.joined(separator: "\n"), ok: true)
                }
            } catch {
                if Task.isCancelled { return }
                set(i, "Not added", error.localizedDescription, ok: false)
            }
        }
    }
}
