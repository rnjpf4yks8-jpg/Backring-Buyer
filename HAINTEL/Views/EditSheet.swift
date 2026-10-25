import PhotosUI
import SwiftUI

/// Entry form for one button. Staff edit hip data; each vet and bloodstock agent posts only their own opinion.
struct EditSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let field: HipField
    let original: Hip
    let isNew: Bool

    @State private var draft: Hip
    @State private var hasReserve: Bool
    @State private var reserve: Int
    @State private var measured: Bool
    @State private var physical: HorsePhysical
    @State private var opinion = Opinion()
    @State private var saving = false
    @State private var uploading = false
    @State private var pickedMedia: PhotosPickerItem?
    @State private var problem: String?

    init(field: HipField, hip: Hip, isNew: Bool) {
        self.field = field
        self.original = hip
        self.isNew = isNew
        _draft = State(initialValue: hip)
        _hasReserve = State(initialValue: hip.reserve != nil)
        _reserve = State(initialValue: hip.reserve ?? 0)
        _measured = State(initialValue: hip.physical != nil)
        _physical = State(initialValue: hip.physical
            ?? HorsePhysical(heightInches: 60, lengthInches: 60, measuredBy: "", date: today))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch field {
                case .hipNumber: hipInfo
                case .vetReport: vetReport
                case .pedigree: pedigree
                case .auctionHistory: auctionHistory
                case .reserve: reserveForm
                case .saleWalkVideo: media(.walkVideo)
                case .salePicture: media(.photo)
                case .hp: physicalForm
                case .vet1, .vet2: vetOpinion
                case .bs1Rank, .bs2Rank: agentOpinion
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(Theme.red) }
                }
            }
            .navigationTitle(isNew ? "Add hip" : (field.slot == nil ? "Edit \(field.title)" : field.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(field.slot == nil ? "Save" : "Post") { Task { await save() } }
                            .disabled(uploading)
                    }
                }
            }
            .onAppear(perform: loadOpinion)
        }
    }

    // MARK: Staff forms

    private var hipInfo: some View {
        Section {
            TextField("Hip number", value: $draft.number, format: .number.grouping(.never))
                .keyboardType(.numberPad)
            TextField("Name (blank if unnamed)", text: $draft.name)
            Picker("Sex", selection: $draft.sex) {
                ForEach(["colt", "filly", "gelding", "horse", "mare"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            TextField("Color", text: $draft.color)
            TextField("Foaled", text: $draft.foaled)
            TextField("Session", text: $draft.session)
            TextField("Barn", text: $draft.barn)
            TextField("Consignor", text: $draft.consignor)
            TextField("Sold as (breeding stock sales)", text: optionalText(\.soldAs))
            TextField("Covering sire (mares)", text: optionalText(\.coveringSire))
        } footer: {
            Text("Copy these from the sale catalog.")
        }
    }

    private var pedigree: some View {
        Group {
            Section("Sire") {
                TextField("Sire", text: $draft.pedigree.sire)
                TextField("Sire’s sire", text: $draft.pedigree.sireSire)
                TextField("Sire’s dam", text: $draft.pedigree.sireDam)
            }
            Section("Dam") {
                TextField("Dam", text: $draft.pedigree.dam)
                TextField("Dam’s sire", text: $draft.pedigree.damSire)
                TextField("Dam’s dam", text: $draft.pedigree.damDam)
            }
            Section {
                TextField("https://…", text: link(\.pedigreeURL))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Catalog page link")
            } footer: {
                Text("The hip's pedigree page on the sale company's website.")
            }
        }
    }

    private var vetReport: some View {
        Group {
            Section("Radiographs") {
                gradePicker($draft.vetReport.radiographs)
                TextField("Notes", text: $draft.vetReport.radiographNotes, axis: .vertical).lineLimit(2...6)
            }
            Section("Throat scope") {
                gradePicker($draft.vetReport.scope)
                TextField("Notes", text: $draft.vetReport.scopeNotes, axis: .vertical).lineLimit(2...6)
            }
            Section {
                TextField("Filed in repository (date)", text: $draft.vetReport.filed)
            }
        }
    }

    private var auctionHistory: some View {
        Group {
            ForEach($draft.auctionHistory) { $record in
                Section {
                    TextField("Sale", text: $record.sale)
                    TextField("Date", text: $record.date)
                    TextField("Hip", value: $record.hip, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    TextField("Result (e.g. Sold $185,000, RNA, Outs)", text: $record.result)
                    Button("Remove this sale", role: .destructive) {
                        let id = record.id
                        draft.auctionHistory.removeAll { $0.id == id }
                    }
                }
            }
            Section {
                Button("Add earlier sale") {
                    draft.auctionHistory.append(AuctionRecord(sale: "", date: "", hip: 0, result: ""))
                }
            }
        }
    }

    private var reserveForm: some View {
        Section {
            Toggle("Has a reserve", isOn: $hasReserve)
            if hasReserve {
                TextField("Reserve ($)", value: $reserve, format: .number)
                    .keyboardType(.numberPad)
            }
        }
    }

    private var physicalForm: some View {
        Section {
            Toggle("Measured", isOn: $measured)
            if measured {
                LabeledContent("Height (inches)") {
                    TextField("62", value: $physical.heightInches, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Length (inches)") {
                    TextField("64", value: $physical.lengthInches, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("In hands", value: physical.heightHands)
                TextField("Measured by", text: $physical.measuredBy)
                TextField("Date", text: $physical.date)
            }
        } footer: {
            Text("Height at the withers. 4 inches = 1 hand.")
        }
    }

    private func media(_ kind: MediaKind) -> some View {
        Section {
            PhotosPicker(selection: $pickedMedia, matching: kind == .photo ? .images : .videos) {
                Label(kind == .photo ? "Choose sale picture" : "Choose walk video",
                      systemImage: kind == .photo ? "photo" : "video")
            }
            if uploading {
                HStack { ProgressView(); Text("Uploading…").foregroundStyle(Theme.slate) }
            } else if (kind == .photo ? draft.photoURL : draft.walkVideoURL) != nil {
                Label("Uploaded", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
            }
            TextField("Or paste a link", text: link(kind == .photo ? \.photoURL : \.walkVideoURL))
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            if kind == .walkVideo {
                TextField("Length (e.g. 0:42)", text: $draft.walkVideoLength)
            }
        }
        .onChange(of: pickedMedia) { _, item in
            guard let item else { return }
            Task { await upload(item, kind: kind) }
        }
    }

    // MARK: Opinion forms

    private var vetOpinion: some View {
        Group {
            Section {
                Picker("Based on", selection: Binding(
                    get: { opinion.basis ?? .repository }, set: { opinion.basis = $0 })) {
                    Text("Repository films and scope").tag(ExamBasis.repository)
                    Text("Physical exam").tag(ExamBasis.physicalExam)
                }
                gradePicker(Binding(get: { opinion.grade ?? .clean }, set: { opinion.grade = $0 }))
                TextField("Date", text: $opinion.date)
            }
            Section("Opinion") {
                TextField("What buyers should know", text: $opinion.notes, axis: .vertical).lineLimit(4...12)
            }
        }
    }

    private var agentOpinion: some View {
        Group {
            Section {
                LabeledContent("Rank") {
                    TextField("1", value: Binding(get: { opinion.rank ?? 1 }, set: { opinion.rank = $0 }), format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Out of") {
                    TextField("186", value: Binding(get: { opinion.outOf ?? store.hips.count }, set: { opinion.outOf = $0 }), format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Score (out of 10)") {
                    TextField("8.0", value: Binding(get: { opinion.score ?? 7 }, set: { opinion.score = $0 }), format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                TextField("Date", text: $opinion.date)
            }
            Section("Opinion") {
                TextField("What buyers should know", text: $opinion.notes, axis: .vertical).lineLimit(4...12)
            }
        }
    }

    /// Edits an optional URL on the draft as text. Blank clears it.
    private func link(_ keyPath: WritableKeyPath<Hip, URL?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath]?.absoluteString ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : URL(string: trimmed)
            }
        )
    }

    /// Edits optional text on the draft. Blank clears it.
    private func optionalText(_ keyPath: WritableKeyPath<Hip, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func gradePicker(_ selection: Binding<Grade>) -> some View {
        Picker("Grade", selection: selection) {
            ForEach(Grade.allCases, id: \.self) { Text($0.label).tag($0) }
        }
    }

    // MARK: Actions

    private func loadOpinion() {
        guard let slot = field.slot else { return }
        if let existing = store.opinion(slot, hip: original) {
            opinion = existing
        } else {
            opinion = slot.isVet
                ? Opinion(date: today, basis: .repository, grade: .clean)
                : Opinion(date: today, rank: 1, outOf: store.hips.count, score: 7)
        }
        if physical.measuredBy.isEmpty, let name = store.user?.name { physical.measuredBy = name }
    }

    private func upload(_ item: PhotosPickerItem, kind: MediaKind) async {
        uploading = true
        defer { uploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            problem = "Couldn’t read that file. Try another one."
            return
        }
        guard let url = await store.upload(data, kind: kind, hip: draft) else {
            problem = store.errorMessage ?? "Upload failed."
            return
        }
        if kind == .photo { draft.photoURL = url } else { draft.walkVideoURL = url }
    }

    private func save() async {
        problem = nil
        if let slot = field.slot {
            guard !opinion.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                problem = "Write your opinion before posting."
                return
            }
            saving = true
            await store.save(opinion, slot: slot, hip: original)
        } else {
            guard draft.number > 0 else {
                problem = "Enter a hip number."
                return
            }
            if (isNew || draft.number != original.number), store.hip(draft.number) != nil {
                problem = "Hip \(draft.number) is already in this sale."
                return
            }
            draft.reserve = hasReserve ? reserve : nil
            draft.physical = measured ? physical : nil
            saving = true
            await store.save(draft, replacing: isNew ? nil : original.number)
        }
        saving = false
        if store.errorMessage == nil { dismiss() } else { problem = store.errorMessage }
    }
}

private var today: String {
    Date().formatted(.dateTime.month(.abbreviated).day().year())
}
