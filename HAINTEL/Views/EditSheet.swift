import PhotosUI
import SwiftUI

/// Entry form for one button. Staff edit hip data; each vet and bloodstock agent posts only their own opinion.
struct EditSheet: View {
    @Environment(SaleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let field: HipField
    let original: Hip
    let isNew: Bool
    /// On Vet Opinions and Bloodstock Opinions: the opinion being posted (the signed-in vet's or agent's own).
    let slot: OpinionSlot?

    @State private var draft: Hip
    @State private var hasReserve: Bool
    @State private var reserve: Int
    @State private var measured: Bool
    @State private var physical: HorsePhysical
    @State private var conformationText: String
    @State private var pedigreeText: String
    @State private var opinion = Opinion()
    @State private var saving = false
    @State private var uploading = false
    @State private var pickedMedia: PhotosPickerItem?
    @State private var problem: String?
    @State private var suggestion: ConformationSuggestion?
    @State private var suggesting = false
    @State private var suggestionProblem: String?
    /// Files uploaded during this visit (removed again on Cancel) and the ones saved before it.
    @State private var uploadedAttachments: [Attachment] = []
    @State private var savedAttachments: [Attachment] = []
    @State private var attachmentsBusy = false

    init(field: HipField, hip: Hip, isNew: Bool, slot: OpinionSlot? = nil) {
        self.field = field
        self.original = hip
        self.isNew = isNew
        self.slot = field.isOpinionGroup ? slot : nil
        _draft = State(initialValue: hip)
        _hasReserve = State(initialValue: hip.reserve != nil)
        _reserve = State(initialValue: hip.reserve ?? 0)
        _measured = State(initialValue: hip.physical != nil)
        _physical = State(initialValue: hip.physical
            ?? HorsePhysical(heightInches: 60, lengthInches: 60, measuredBy: "", date: today))
        _conformationText = State(initialValue: hip.conformationGrade.map(Hip.gradeText) ?? "")
        _pedigreeText = State(initialValue: hip.pedigreeGrade.map(Hip.gradeText) ?? "")
        _savedAttachments = State(initialValue: field == .vetReport ? (hip.vetReport.attachments ?? []) : [])
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
                case .vetOpinions: vetOpinion
                case .bloodstockOpinions: agentOpinion
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(Theme.red) }
                }
            }
            .navigationTitle(isNew ? "Add hip" : (slot?.title ?? "Edit \(field.title)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task {
                            await store.deleteAttachments(uploadedAttachments)
                            dismiss()
                        }
                    }
                    .disabled(attachmentsBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(field.isOpinionGroup ? "Post" : "Save") { Task { await save() } }
                            .disabled(uploading || attachmentsBusy)
                    }
                }
            }
            .interactiveDismissDisabled(attachmentsBusy || !uploadedAttachments.isEmpty)
            .onAppear(perform: loadOpinion)
        }
    }

    // MARK: Staff forms

    private var hipInfo: some View {
        Group {
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
            } footer: {
                Text("Copy these from the sale catalog.")
            }
            Section {
                LabeledContent("C · Conformation (1–10)") {
                    TextField("8.0", text: $conformationText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("P · Pedigree (1–5)") {
                    TextField("4.5", text: $pedigreeText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                TextField("Why (one line)", text: Binding(
                    get: { draft.gradeNotes ?? "" }, set: { draft.gradeNotes = $0 }))
            } header: {
                Text("Backring Buyer grades")
            } footer: {
                Text("Half points, like 8.0 or 4.5. Leave blank if not graded yet. Ranks in the sale are worked out from these.")
            }
            if store.isStaff && !isNew { aiConformation }
        }
    }

    /// Staff ask the AI for a C grade from the saved walk video, then use it (or not) before saving.
    private var aiConformation: some View {
        Section {
            if let suggestion {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("C \(Hip.gradeText(suggestion.grade))").font(.title3.bold())
                        Spacer()
                        Text("\(suggestion.confidence.capitalized) confidence")
                            .font(.footnote)
                            .foregroundStyle(suggestion.confidence == "low" ? Theme.red : Theme.slate)
                    }
                    if !suggestion.summary.isEmpty { Text(suggestion.summary) }
                }
                if !suggestion.strengths.isEmpty {
                    points("Strengths", suggestion.strengths, symbol: "plus.circle.fill", color: Theme.green)
                }
                if !suggestion.faults.isEmpty {
                    points("Faults", suggestion.faults, symbol: "minus.circle.fill", color: Theme.red)
                }
                if !suggestion.limits.isEmpty {
                    Text(suggestion.limits).font(.footnote).foregroundStyle(Theme.slate)
                }
                Button {
                    use(suggestion)
                } label: {
                    Label("Use C \(Hip.gradeText(suggestion.grade))", systemImage: "checkmark.circle")
                }
                .disabled(conformationText == Hip.gradeText(suggestion.grade))
            }
            if suggesting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Watching the walk video. This can take a minute.").foregroundStyle(Theme.slate)
                }
            } else {
                Button {
                    Task { await suggest() }
                } label: {
                    Label(suggestion == nil ? "Suggest C grade from walk video" : "Ask again", systemImage: "sparkles")
                }
                .disabled(original.walkVideoURL == nil)
            }
            if let suggestionProblem {
                Text(suggestionProblem).foregroundStyle(Theme.red)
            }
        } header: {
            Text("AI conformation check")
        } footer: {
            Text(original.walkVideoURL == nil
                 ? "Add this hip’s walk video on the Sale Walk Video button first. The AI needs an uploaded video file, not a Vimeo or YouTube link."
                 : "The AI looks at still frames from the sale walk video. Nothing changes until you use its grade and tap Save.")
        }
    }

    private func points(_ title: String, _ items: [String], symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.slate)
            ForEach(items, id: \.self) { item in
                Label {
                    Text(item)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(color)
                }
            }
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
            AttachmentEditor(
                attachments: Binding(get: { draft.vetReport.attachments ?? [] },
                                     set: { draft.vetReport.attachments = $0.isEmpty ? nil : $0 }),
                uploaded: $uploadedAttachments, busy: $attachmentsBusy,
                folder: .vetReport(saleID: store.sale.id, hip: original.number),
                footer: "The repository report, radiographs or scope images, as PDF or photos. Anyone signed in can open them.")
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
            opinionAttachments
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
            opinionAttachments
        }
    }

    /// The vet's or agent's own report files. Only the author posts here.
    @ViewBuilder
    private var opinionAttachments: some View {
        if let slot {
            AttachmentEditor(
                attachments: Binding(get: { opinion.attachments ?? [] },
                                     set: { opinion.attachments = $0.isEmpty ? nil : $0 }),
                uploaded: $uploadedAttachments, busy: $attachmentsBusy,
                folder: .opinion(saleID: store.sale.id, hip: original.number, slot: slot),
                footer: "Your written report, radiographs or scope images, as PDF or photos. Buyers can open them once they’ve bought your opinion.")
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

    private func gradePicker(_ selection: Binding<Grade>) -> some View {
        Picker("Grade", selection: selection) {
            ForEach(Grade.allCases, id: \.self) { Text($0.label).tag($0) }
        }
    }

    // MARK: Actions

    private func loadOpinion() {
        guard let slot else { return }
        if let existing = store.opinion(slot, hip: original) {
            opinion = existing
            savedAttachments = existing.attachments ?? []
        } else {
            opinion = slot.isVet
                ? Opinion(date: today, basis: .repository, grade: .clean)
                : Opinion(date: today, rank: 1, outOf: store.hips.count, score: 7)
        }
        if physical.measuredBy.isEmpty, let name = store.user?.name { physical.measuredBy = name }
    }

    private func suggest() async {
        suggesting = true
        suggestionProblem = nil
        defer { suggesting = false }
        do {
            suggestion = try await store.suggestConformation(for: original)
        } catch {
            suggestionProblem = error.localizedDescription
        }
    }

    /// Puts the AI's grade in the C box, and its one-line reason in "Why" if that's empty. Saved on Save.
    private func use(_ suggestion: ConformationSuggestion) {
        conformationText = Hip.gradeText(suggestion.grade)
        if (draft.gradeNotes ?? "").trimmingCharacters(in: .whitespaces).isEmpty, !suggestion.summary.isEmpty {
            draft.gradeNotes = suggestion.summary
        }
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
        if field.isOpinionGroup {
            guard let slot else {
                problem = "Only the vet or agent on this sale’s panel can post here."
                return
            }
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
            if field == .hipNumber {
                let conformation = parseGrade(conformationText, max: 10)
                let pedigree = parseGrade(pedigreeText, max: 5)
                guard conformation.valid else {
                    problem = "Conformation grade is 1 to 10 in half points, like 8.0 or 7.5. Leave it blank if not graded."
                    return
                }
                guard pedigree.valid else {
                    problem = "Pedigree grade is 1 to 5 in half points, like 4.5. Leave it blank if not graded."
                    return
                }
                draft.conformationGrade = conformation.value
                draft.pedigreeGrade = pedigree.value
                let notes = (draft.gradeNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                draft.gradeNotes = notes.isEmpty ? nil : notes
            }
            draft.reserve = hasReserve ? reserve : nil
            draft.physical = measured ? physical : nil
            saving = true
            await store.save(draft, replacing: isNew ? nil : original.number)
        }
        saving = false
        if store.errorMessage == nil {
            // Files taken off this opinion or report are deleted once the change is saved.
            let kept = Set(((field.isOpinionGroup ? opinion.attachments : draft.vetReport.attachments) ?? []).map(\.path))
            await store.deleteAttachments(savedAttachments.filter { !kept.contains($0.path) })
            dismiss()
        } else {
            problem = store.errorMessage
        }
    }

    /// A grade typed by staff. Blank is valid and means not graded; otherwise 1 to `max` in half points.
    private func parseGrade(_ text: String, max: Double) -> (valid: Bool, value: Double?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty { return (true, nil) }
        guard let value = Double(trimmed), value >= 1, value <= max, (value * 2).rounded() == value * 2 else {
            return (false, nil)
        }
        return (true, value)
    }
}

private var today: String {
    Date().formatted(.dateTime.month(.abbreviated).day().year())
}
