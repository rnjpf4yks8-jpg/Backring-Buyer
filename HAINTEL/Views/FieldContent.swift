import AVKit
import SwiftUI
import WebKit

struct FieldContent: View {
    let field: HipField
    let hip: Hip

    var body: some View {
        switch field {
        case .hipNumber: HipNumberPanel(hip: hip)
        case .vetReport: VetReportPanel(report: hip.vetReport)
        case .pedigree: PedigreePanel(hip: hip)
        case .auctionHistory: AuctionHistoryPanel(records: hip.auctionHistory)
        case .vetOpinions, .bloodstockOpinions: OpinionGroupContent(field: field, hip: hip)
        case .reserve: ReservePanel(hip: hip)
        case .saleWalkVideo: VideoPanel(url: hip.walkVideoURL, length: hip.walkVideoLength)
        case .salePicture: PhotoPanel(url: hip.photoURL)
        case .hp: PhysicalPanel(physical: hip.physical)
        }
    }
}

/// Vet Opinions (Vet 1, Vet 2) and Bloodstock Opinions (BS1, BS2): a menu of the panel members with an
/// opinion on this hip, then the picked one's opinion, its paywall, or where it stands in review.
private struct OpinionGroupContent: View {
    @Environment(SaleStore.self) private var store
    let field: HipField
    let hip: Hip

    var body: some View {
        let slots = store.availableSlots(field, hip: hip)
        if let selected = store.selectedSlot(field, hip: hip) {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    ForEach(slots, id: \.self) { slot in
                        Button {
                            store.selectedSlots[field] = slot
                        } label: {
                            if slot == selected {
                                Label(store.slotMenuTitle(slot, hip: hip), systemImage: "checkmark")
                            } else {
                                Text(store.slotMenuTitle(slot, hip: hip))
                            }
                        }
                    }
                } label: {
                    picker(selected, count: slots.count)
                }
                .accessibilityLabel("Showing \(store.slotMenuTitle(selected, hip: hip)). Pick another \(noun)")
                OpinionContent(slot: selected, hip: hip)
                    .id(selected)
            }
        } else {
            Card {
                Text("No \(noun) opinions yet").font(Theme.sans(17, .semibold)).foregroundStyle(Theme.ink)
                Text("They show up here once the sale’s \(noun)s post them and Backring Buyer approves them.")
                    .font(Theme.sans(15)).foregroundStyle(Theme.slate)
            }
        }
    }

    private var noun: String { field == .vetOpinions ? "vet" : "bloodstock agent" }

    private func picker(_ slot: OpinionSlot, count: Int) -> some View {
        let status = store.slotStatus(slot, hip: hip)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: count == 1 ? "1 \(noun) opinion" : "\(count) \(noun) opinions")
                Text(store.sale.member(slot)?.name ?? slot.title)
                    .font(Theme.sans(17, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(status.summary)
                    .font(Theme.sans(14, status.locked ? .semibold : .regular))
                    .foregroundStyle(status.locked ? Theme.orange : Theme.slate)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.blue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .contentShape(Rectangle())
    }
}

/// One of Vet 1, Vet 2, BS1 and BS2: not posted yet, locked behind a purchase, or the opinion itself.
private struct OpinionContent: View {
    @Environment(SaleStore.self) private var store
    let slot: OpinionSlot
    let hip: Hip

    var body: some View {
        let member = store.sale.member(slot)
        // Staff and the opinion's author see it at every stage; buyers only once it's approved.
        let reviewer = store.isStaff || store.isAuthor(slot)
        if reviewer, let opinion = store.opinion(slot, hip: hip) {
            VStack(spacing: 12) {
                ReviewBanner(status: opinion.reviewStatus, slot: slot, hip: hip)
                opinionPanel(opinion, member: member)
            }
        } else if reviewer, hip.pendingSlots.contains(slot) || hip.opinionsIn.contains(slot) {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        } else if !hip.opinionsIn.contains(slot) {
            Card {
                Text("Not posted yet").font(Theme.sans(17, .semibold)).foregroundStyle(Theme.ink)
                Text(store.isAuthor(slot)
                     ? "Tap Post to add your opinion on this hip. Backring Buyer approves it before buyers can see it."
                     : "\(member?.name ?? "The \(slot.isVet ? "vet" : "agent")") hasn’t posted an opinion on this hip yet.")
                    .font(Theme.sans(15)).foregroundStyle(Theme.slate)
            }
        } else if !store.canRead(slot, hip: hip) {
            Paywall(slot: slot, hip: hip)
        } else if let opinion = store.opinion(slot, hip: hip) {
            opinionPanel(opinion, member: member)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    @ViewBuilder
    private func opinionPanel(_ opinion: Opinion, member: PanelMember?) -> some View {
        if slot.isVet {
            VetOpinionPanel(opinion: opinion, member: member)
        } else {
            AgentOpinionPanel(opinion: opinion, member: member)
        }
    }
}

/// Where an opinion stands in Backring Buyer's review. Staff approve or return pending opinions here.
private struct ReviewBanner: View {
    @Environment(SaleStore.self) private var store
    let status: OpinionStatus
    let slot: OpinionSlot
    let hip: Hip
    @State private var working = false

    var body: some View {
        Card {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(status == .approved ? "Approved · buyers can see it" : status.label)
                    .font(Theme.sans(15, .semibold))
                    .foregroundStyle(Theme.ink)
            }
            if store.isStaff, status != .approved {
                HStack(spacing: 10) {
                    Button { review(true) } label: {
                        Text("Approve").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                    if status == .pending {
                        Button { review(false) } label: {
                            Text("Return").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.red)
                    }
                }
                .disabled(working)
                .padding(.top, 4)
            } else if store.isStaff {
                Button("Hide from buyers", role: .destructive) { review(false) }
                    .disabled(working)
            } else if status == .rejected {
                Text("Edit and post it again to resubmit.")
                    .font(Theme.sans(14)).foregroundStyle(Theme.slate)
            }
        }
    }

    private var symbol: String {
        switch status {
        case .pending: "clock.fill"
        case .approved: "checkmark.seal.fill"
        case .rejected: "arrow.uturn.backward.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .pending: Theme.orange
        case .approved: Theme.green
        case .rejected: Theme.red
        }
    }

    private func review(_ approve: Bool) {
        working = true
        Task {
            await store.review(slot, hip: hip, approve: approve)
            working = false
        }
    }
}

// MARK: - 01 Hip Number

private struct HipNumberPanel: View {
    @Environment(SaleStore.self) private var store
    let hip: Hip
    @State private var query = ""

    private var matches: [Hip] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.hips }
        return store.hips.filter {
            String($0.number).hasPrefix(q) || $0.pedigree.sire.lowercased().contains(q)
                || $0.pedigree.dam.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Hip", color: Theme.amber)
                Text("\(hip.number)")
                    .font(Theme.mono(56, .bold))
                    .foregroundStyle(.white)
                Text(hip.name.isEmpty ? hip.title : "\(hip.name) · \(hip.title)")
                    .font(Theme.sans(16, .medium))
                    .foregroundStyle(Theme.mist)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.navy, in: RoundedRectangle(cornerRadius: 12))

            if hip.isGraded {
                HStack(spacing: 12) {
                    GradeTile(label: "Conformation", grade: hip.conformationGrade, outOf: 10,
                              rank: store.conformationRank(hip), graded: store.conformationGradedCount)
                    GradeTile(label: "Pedigree", grade: hip.pedigreeGrade, outOf: 5,
                              rank: store.pedigreeRank(hip), graded: store.pedigreeGradedCount)
                }
                if let notes = hip.gradeNotes, !notes.isEmpty {
                    Card {
                        Eyebrow(text: "Backring Buyer grades")
                        Text(notes).font(Theme.sans(15)).foregroundStyle(Theme.slate).lineSpacing(3)
                    }
                }
            }

            Card {
                InfoRow(label: "Foaled", value: hip.foaled)
                InfoRow(label: "Session", value: hip.session)
                InfoRow(label: "Barn", value: hip.barn)
                InfoRow(label: "Consignor", value: hip.consignor)
            }

            Eyebrow(text: "Switch hip").padding(.top, 4)
            TextField("Hip number, sire or dam", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))

            LazyVStack(spacing: 0) {
                ForEach(matches) { other in
                    Button {
                        store.currentHipNumber = other.number
                        query = ""
                    } label: {
                        HStack(spacing: 14) {
                            Text("\(other.number)")
                                .font(Theme.mono(17, .semibold))
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.title).font(Theme.sans(15, .medium))
                                Text(other.cross).font(Theme.sans(13)).foregroundStyle(Theme.slate)
                            }
                            Spacer()
                            if other.number == hip.number {
                                Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                    }
                    if other.id != matches.last?.id { Divider().padding(.leading, 14) }
                }
                if matches.isEmpty {
                    Text("No hip matches “\(query)”.")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.slate)
                        .padding(14)
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }
    }
}

// MARK: - 02 Vet Report

private struct VetReportPanel: View {
    let report: VetReport

    var body: some View {
        if !report.isEntered {
            Card {
                Text("Not entered yet").font(Theme.sans(17, .semibold)).foregroundStyle(Theme.ink)
                Text("Backring Buyer staff haven’t summarized the repository report for this hip yet.")
                    .font(Theme.sans(15)).foregroundStyle(Theme.slate)
            }
        } else {
            entered
        }
    }

    private var entered: some View {
        VStack(spacing: 12) {
            section("Radiographs", grade: report.radiographs, notes: report.radiographNotes)
            section("Throat scope", grade: report.scope, notes: report.scopeNotes)
            Card { InfoRow(label: "Filed in repository", value: report.filed) }
            AttachmentList(attachments: report.attachments ?? [])
        }
    }

    private func section(_ title: String, grade: Grade, notes: String) -> some View {
        Card {
            HStack {
                Text(title).font(Theme.sans(17, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                GradeBadge(grade: grade)
            }
            Text(notes).font(Theme.sans(15)).foregroundStyle(Theme.slate).lineSpacing(3)
        }
    }
}

// MARK: - 03 Pedigree

private struct PedigreePanel: View {
    @Environment(SaleStore.self) private var store
    let hip: Hip

    private var pedigree: Pedigree { hip.pedigree }
    private var catalogPage: URL? { hip.pedigreeURL }

    var body: some View {
        VStack(spacing: 12) {
            if let grade = hip.pedigreeGrade {
                GradeTile(label: "Backring Buyer pedigree grade", grade: grade, outOf: 5,
                          rank: store.pedigreeRank(hip), graded: store.pedigreeGradedCount)
            }
            parent(role: "Sire", name: pedigree.sire, sire: pedigree.sireSire, dam: pedigree.sireDam)
            parent(role: "Dam", name: pedigree.dam, sire: pedigree.damSire, dam: pedigree.damDam)
            if let catalogPage {
                Link(destination: catalogPage) {
                    Card {
                        HStack {
                            Label("Full catalog page", systemImage: "doc.text")
                                .font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(Theme.slate)
                        }
                    }
                }
            }
        }
    }

    private func parent(role: String, name: String, sire: String, dam: String) -> some View {
        Card {
            Eyebrow(text: role)
            Text(name).font(Theme.sans(20, .bold)).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                ancestor("by", sire)
                ancestor("out of", dam)
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 2) }
        }
    }

    private func ancestor(_ relation: String, _ name: String) -> some View {
        HStack(spacing: 6) {
            Text(relation).font(Theme.sans(14)).foregroundStyle(Theme.slate)
            Text(name).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
        }
    }
}

/// One of Backring Buyer's grades (C or P) as a navy hero tile: the grade, out of what, and its rank in the sale.
private struct GradeTile: View {
    let label: String
    let grade: Double?
    let outOf: Int
    let rank: Int?
    let graded: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: label, color: Theme.amber)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(grade.map(Hip.gradeText) ?? "–").font(Theme.mono(28, .bold)).foregroundStyle(.white)
                Text("/ \(outOf)").font(Theme.sans(15)).foregroundStyle(Theme.mist)
            }
            Text(rank.map { "Rank \($0) of \(graded)" } ?? "Not graded")
                .font(Theme.sans(13)).foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.navy, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(grade.map { "\(label) \(Hip.gradeText($0)) of \(outOf), rank \(rank ?? 0) of \(graded)" } ?? "\(label) not graded")
    }
}

// MARK: - 04 Auction History

private struct AuctionHistoryPanel: View {
    let records: [AuctionRecord]

    var body: some View {
        if records.isEmpty {
            Card {
                Text("First time through the ring").font(Theme.sans(17, .semibold))
                Text("This horse has no earlier auction records.")
                    .font(Theme.sans(15)).foregroundStyle(Theme.slate)
            }
        } else {
            VStack(spacing: 12) {
                ForEach(records) { record in
                    Card {
                        HStack(alignment: .firstTextBaseline) {
                            Text(record.sale).font(Theme.sans(17, .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(record.date).font(Theme.mono(13)).foregroundStyle(Theme.slate)
                        }
                        InfoRow(label: "Hip", value: "\(record.hip)", mono: true)
                        InfoRow(label: "Result", value: record.result)
                    }
                }
            }
        }
    }
}

// MARK: - 05 Vet Opinions (Vet 1, Vet 2)

private struct VetOpinionPanel: View {
    let opinion: Opinion
    let member: PanelMember?

    var body: some View {
        VStack(spacing: 12) {
            Card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member?.name ?? "Vet").font(Theme.sans(18, .semibold)).foregroundStyle(Theme.ink)
                        Text(member?.org ?? "").font(Theme.sans(14)).foregroundStyle(Theme.slate)
                    }
                    Spacer()
                    if let grade = opinion.grade { GradeBadge(grade: grade) }
                }
                Divider()
                if let basis = opinion.basis { BasisRow(basis: basis) }
                InfoRow(label: "Date", value: opinion.date)
                Text(opinion.notes).font(Theme.sans(15)).foregroundStyle(Theme.slate).lineSpacing(3)
            }
            AttachmentList(attachments: opinion.attachments ?? [])
        }
    }
}

// MARK: - 06 Bloodstock Opinions (BS1, BS2)

private struct AgentOpinionPanel: View {
    let opinion: Opinion
    let member: PanelMember?

    var body: some View {
        VStack(spacing: 12) {
            if let rank = opinion.rank, let outOf = opinion.outOf, outOf > 0 {
                let topPercent = max(1, Int((Double(rank) / Double(outOf) * 100).rounded(.up)))
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Bloodstock agent rank", color: Theme.amber)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("#\(rank)").font(Theme.mono(52, .bold)).foregroundStyle(.white)
                        Text("of \(outOf)").font(Theme.sans(17)).foregroundStyle(Theme.mist)
                    }
                    ProgressView(value: Double(max(0, outOf - rank + 1)), total: Double(outOf))
                        .tint(Theme.amber)
                    Text("Top \(topPercent)% of the session")
                        .font(Theme.sans(14)).foregroundStyle(Theme.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.navy, in: RoundedRectangle(cornerRadius: 12))
            }

            Card {
                VStack(alignment: .leading, spacing: 2) {
                    Text(member?.name ?? "Bloodstock agent").font(Theme.sans(18, .semibold)).foregroundStyle(Theme.ink)
                    Text(member?.org ?? "").font(Theme.sans(14)).foregroundStyle(Theme.slate)
                }
                Divider()
                if let score = opinion.score {
                    InfoRow(label: "Score", value: String(format: "%.1f / 10", score), mono: true)
                }
                InfoRow(label: "Date", value: opinion.date)
                Text(opinion.notes).font(Theme.sans(15)).foregroundStyle(Theme.slate).lineSpacing(3)
            }
            AttachmentList(attachments: opinion.attachments ?? [])
        }
    }
}

// MARK: - 07 Reserve

private struct ReservePanel: View {
    let hip: Hip

    var body: some View {
        Card {
            Eyebrow(text: "Reserve")
            Text(hip.reserve.map(usd) ?? "No reserve")
                .font(Theme.mono(36, .bold))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text("Private to your team. Bidders never see it.")
            }
            .font(Theme.sans(14))
            .foregroundStyle(Theme.slate)
        }
    }
}

// MARK: - 08 Sale Walk Video

private struct VideoPanel: View {
    let url: URL?
    let length: String
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url, let embed = WebVideo.embedURL(for: url) {
                // Sale company walk videos are Vimeo or YouTube pages, which AVPlayer can't open.
                WebVideo(url: embed)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Link(destination: url) {
                    Card {
                        HStack {
                            Label("Open in \(url.host()?.contains("vimeo") == true ? "Vimeo" : "YouTube")",
                                  systemImage: "play.rectangle")
                                .font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(Theme.slate)
                        }
                    }
                }
                if !length.isEmpty { Card { InfoRow(label: "Length", value: length, mono: true) } }
            } else if let url {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onAppear { if player == nil { player = AVPlayer(url: url) } }
                    .onDisappear { player?.pause() }
                if !length.isEmpty { Card { InfoRow(label: "Length", value: length, mono: true) } }
            } else {
                MediaPlaceholder(symbol: "play.rectangle", text: "No walk video posted for this hip yet.")
            }
        }
    }
}

/// A Vimeo or YouTube player, played inline.
private struct WebVideo: UIViewRepresentable {
    let url: URL

    /// The embeddable player for a Vimeo or YouTube page link, or nil for a direct video file.
    static func embedURL(for url: URL) -> URL? {
        let host = (url.host() ?? "").replacingOccurrences(of: "www.", with: "")
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "vimeo.com", "player.vimeo.com":
            guard let id = parts.first(where: { Int($0) != nil }) else { return nil }
            var embed = URLComponents(string: "https://player.vimeo.com/video/\(id)")!
            embed.queryItems = [URLQueryItem(name: "playsinline", value: "1")]
            // Unlisted videos carry a privacy hash after the id.
            if let i = parts.firstIndex(of: id), i + 1 < parts.count {
                embed.queryItems?.append(URLQueryItem(name: "h", value: parts[i + 1]))
            }
            return embed.url
        case "youtu.be", "youtube.com", "m.youtube.com":
            let id = host == "youtu.be" ? parts.first
                : parts.first == "shorts" ? parts.dropFirst().first
                : URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value
            guard let id else { return nil }
            return URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1")
        default:
            return nil
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        var request = URLRequest(url: url)
        // YouTube refuses embeds that don't name the app they're shown in.
        request.setValue("https://\((Bundle.main.bundleIdentifier ?? "haintel").lowercased())", forHTTPHeaderField: "Referer")
        view.load(request)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

// MARK: - 09 Sale Picture

private struct PhotoPanel: View {
    let url: URL?

    var body: some View {
        if let url {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            MediaPlaceholder(symbol: "figure.equestrian.sports", text: "No sale picture posted for this hip yet.")
        }
    }
}

private struct MediaPlaceholder: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(Theme.amber)
            Text(text).font(Theme.sans(15)).foregroundStyle(Theme.mist).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(Theme.navyCard, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 10 HP (horse physical)

private struct PhysicalPanel: View {
    let physical: HorsePhysical?

    var body: some View {
        if let physical {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    measure("Height", physical.heightHands, detail: "\(formatted(physical.heightInches)) in")
                    measure("Length", "\(formatted(physical.lengthInches)) in",
                            detail: "\(Int((physical.lengthInches * 2.54).rounded())) cm")
                }
                Card {
                    InfoRow(label: "Measured by", value: "\(physical.measuredBy), Backring Buyer")
                    InfoRow(label: "Date", value: physical.date)
                }
            }
        } else {
            Card {
                Text("Not measured yet").font(Theme.sans(17, .semibold))
                Text("A Backring Buyer field team member hasn’t measured this hip yet.")
                    .font(Theme.sans(15)).foregroundStyle(Theme.slate)
            }
        }
    }

    private func measure(_ label: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: label, color: Theme.amber)
            Text(value).font(Theme.mono(28, .bold)).foregroundStyle(.white)
            Text(detail).font(Theme.sans(13)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.navy, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatted(_ inches: Double) -> String {
        inches.formatted(.number.precision(.fractionLength(0...1)))
    }
}

// MARK: - Paid opinions

private struct BasisRow: View {
    let basis: ExamBasis

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: basis == .physicalExam ? "hand.raised.fill" : "film.stack")
                .foregroundStyle(Theme.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Based on").font(Theme.sans(13)).foregroundStyle(Theme.slate)
                Text(basis.label).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
            }
        }
    }
}

/// Shown in place of a vet or bloodstock opinion until the user buys it.
private struct Paywall: View {
    @Environment(SaleStore.self) private var store
    let slot: OpinionSlot
    let hip: Hip
    @State private var buying = false
    @State private var showAccount = false

    var body: some View {
        let member = store.sale.member(slot)
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text("Unlock the \(slot.isVet ? "vet opinion" : "bloodstock agent opinion") for hip \(hip.number)")
                .font(Theme.sans(20, .bold))
                .foregroundStyle(.white)
            if let member {
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name).font(Theme.sans(16, .semibold)).foregroundStyle(.white)
                    Text(member.org).font(Theme.sans(14)).foregroundStyle(Theme.mist)
                }
            }
            Text(slot.isVet
                 ? "Their grade and full notes, and whether they read the repository films and scope or examined the horse in person."
                 : "Their rank for this hip in the session, a score out of 10, and their notes.")
                .font(Theme.sans(15))
                .foregroundStyle(Theme.mist)
                .lineSpacing(3)
            Button {
                if store.user == nil {
                    showAccount = true
                } else {
                    buying = true
                    Task {
                        await store.buy(slot, hip: hip)
                        buying = false
                    }
                }
            } label: {
                Group {
                    if buying {
                        ProgressView().tint(Theme.navy)
                    } else {
                        Text(store.user == nil ? "Sign in to buy · \(store.price(slot))" : "Buy for \(store.price(slot))")
                    }
                }
                .font(Theme.sans(16, .semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(Theme.navy)
                .background(Theme.amber, in: RoundedRectangle(cornerRadius: 8))
            }
            .disabled(buying)
            Text(store.isDemo ? "One-time purchase for this hip." : "One-time purchase for this hip, charged to the card on your Apple ID.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.navy, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showAccount) { AccountView() }
    }
}
