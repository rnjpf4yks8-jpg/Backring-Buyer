import SwiftUI

/// Past performances laid out like DRF: one line per race, newest first, scrolling sideways.
struct PPTable: View {
    let lines: [RaceLine]
    let onTap: (RaceLine) -> Void

    /// Column widths, shared by the header and every line.
    private enum W {
        static let date: CGFloat = 88, cond: CGFloat = 40, dist: CGFloat = 44, times: CGFloat = 196
        static let age: CGFloat = 32, cls: CGFloat = 118, beyer: CGFloat = 38, small: CGFloat = 24
        static let call: CGFloat = 36, fin: CGFloat = 42, jockey: CGFloat = 92, wt: CGFloat = 56
        static let odds: CGFloat = 50, top: CGFloat = 300, comment: CGFloat = 220, money: CGFloat = 72
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.turfSoft)
                ForEach(lines) { line in
                    Button { onTap(line) } label: {
                        row(line).padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.line).frame(height: 0.5)
                }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func cell<V: View>(_ view: V, _ width: CGFloat, _ alignment: Alignment = .leading) -> some View {
        view.lineLimit(1).frame(width: width, alignment: alignment)
    }

    private var header: some View {
        HStack(spacing: 6) {
            cell(Text("Date Trk"), W.date)
            cell(Text("Cond"), W.cond)
            cell(Text("Dist"), W.dist)
            cell(Text("Fractions · Final"), W.times)
            cell(Text("Age"), W.age)
            cell(Text("Race type"), W.cls)
            cell(Text("Beyer"), W.beyer)
            cell(Text("PP"), W.small)
            cell(Text("St"), W.small)
            cell(Text("1c"), W.call)
            cell(Text("2c"), W.call)
            cell(Text("Str"), W.call)
            cell(Text("Fin"), W.fin)
            cell(Text("Jockey"), W.jockey)
            cell(Text("Wt"), W.wt)
            cell(Text("Odds"), W.odds)
            cell(Text("Top finishers"), W.top)
            cell(Text("Comment"), W.comment)
            cell(Text("#"), W.small)
            cell(Text("Won"), W.money, .trailing)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.turf)
    }

    private func row(_ l: RaceLine) -> some View {
        let calls = DRF.calls(l)
        let padded: [Call?] = Array(repeating: nil, count: max(0, 3 - calls.count)) + calls.map { Optional($0) }
        let times = (l.fractions ?? []).prefix(3).map { DRF.time($0) } + [DRF.time(l.final)]
        let won = l.earnings ?? 0
        return HStack(spacing: 6) {
            cell(dateText(l), W.date)
            cell(conditionText(l), W.cond)
            cell(Text(verbatim: DRF.dist(l.distanceF, about: l.about ?? false)), W.dist)
            cell(raisedRow(times), W.times)
            cell(Text(verbatim: (l.ages ?? "") + (l.fillies == true ? "f" : "")), W.age)
            cell(Text(verbatim: (l.classText ?? "").isEmpty ? (l.type ?? "") : (l.classText ?? "")), W.cls)
            cell(Text(verbatim: l.beyer.map(String.init) ?? "–").foregroundStyle(l.beyer == nil ? Theme.muted : Theme.ink), W.beyer)
            cell(Text(verbatim: l.postPosition.map(String.init) ?? ""), W.small)
            cell(Text(verbatim: l.start.map(String.init) ?? ""), W.small)
            ForEach(0..<3, id: \.self) { i in
                cell(padded[i].map { raisedText(DRF.pos($0.pos, $0.lengths)) } ?? Text(verbatim: ""), W.call)
            }
            cell(raisedText(DRF.pos(l.finish?.pos, l.finish?.lengths), weight: .bold)
                    .foregroundStyle(l.won ? Theme.good : Theme.ink), W.fin)
            cell(Text(verbatim: DRF.jockey(l.jockey)), W.jockey)
            cell(Text(verbatim: "\(l.medEq ?? "")\(l.weight.map(String.init) ?? "")"), W.wt)
            cell(Text(verbatim: DRF.odds(l.odds, favorite: l.favorite)), W.odds)
            cell(topText(l), W.top)
            cell(Text(verbatim: l.comment ?? ""), W.comment)
            cell(Text(verbatim: l.fieldSize.map(String.init) ?? ""), W.small)
            cell(Text(verbatim: DRF.money(won)).foregroundStyle(won > 0 ? Theme.good : Theme.muted), W.money, .trailing)
        }
        .font(Theme.data(13))
        .foregroundStyle(Theme.ink)
    }

    private func dateText(_ l: RaceLine) -> Text {
        let date = Text(verbatim: Dates.pp(l.date)).font(Theme.data(13, .semibold))
        let race = Text(verbatim: l.race.map { " \($0)" } ?? " ").font(Theme.data(11)).foregroundStyle(Theme.muted)
        let track = Text(verbatim: DRF.trk(l.track)).font(Theme.data(13, .semibold))
        return Text("\(date)\(race)\(track)")
    }

    private func conditionText(_ l: RaceLine) -> Text {
        let cond = Text(verbatim: (l.condition ?? "") + " ")
        let letter = Text(verbatim: l.surface == "T" ? "T" : l.surface == "A" ? "A" : "D")
            .font(Theme.data(11, .heavy))
            .foregroundStyle(Theme.surfaceColor(l.surface))
        return Text("\(cond)\(letter)")
    }

    private func topText(_ l: RaceLine) -> Text {
        let parts = (l.top3 ?? []).map { t in
            Raised(main: "\(t.name ?? "")\(t.weight.map(String.init) ?? "")", raised: DRF.len(t.lengths))
        }
        return raisedRow(parts)
    }
}

/// The same lines as cards, easier to read on a phone held upright.
struct PPCards: View {
    let lines: [RaceLine]
    let onTap: (RaceLine) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(lines) { l in
                Button { onTap(l) } label: { card(l) }.buttonStyle(.plain)
            }
        }
    }

    private func card(_ l: RaceLine) -> some View {
        let calls = DRF.calls(l).map { DRF.pos($0.pos, $0.lengths) }
        let head = "\(Dates.pp(l.date)) \(l.race.map(String.init) ?? "")\(DRF.trk(l.track)) · \(l.condition ?? "") "
            + "\(DRF.dist(l.distanceF, about: l.about ?? false)) \(DRF.surfaceWord(l.surface)) · "
            + ((l.classText ?? "").isEmpty ? (l.type ?? "") : (l.classText ?? ""))
        let place = l.finish?.pos.map { DRF.ordinal($0) } ?? "?"
        let beaten = DRF.len(l.finish?.lengths)
        let field = l.fieldSize.map(String.init) ?? "?"
        let running = [Raised(main: l.postPosition.map(String.init) ?? "?"), Raised(main: l.start.map(String.init) ?? "")]
            + calls + [DRF.pos(l.finish?.pos, l.finish?.lengths)]
        var tail = "Won \(DRF.money(l.earnings ?? 0))"
        if let comment = l.comment, !comment.isEmpty { tail += " · \(comment)" }
        if let beyer = l.beyer { tail += " · Beyer \(beyer)" }
        return Card {
            Text(verbatim: head).font(Theme.data(14, .semibold)).foregroundStyle(Theme.ink)
            Text("Finished **\(place)**\(beaten.isEmpty ? "" : " (\(beaten))") of \(field)")
                .font(.subheadline)
            HStack(spacing: 6) {
                raisedRow(running, size: 14)
                Text(verbatim: "· \(DRF.jockey(l.jockey)) \(l.weight.map(String.init) ?? "") · \(DRF.odds(l.odds, favorite: l.favorite))")
                    .font(Theme.data(14))
            }
            .lineLimit(1)
            Text(verbatim: tail).font(.footnote).foregroundStyle(l.won ? Theme.good : Theme.muted)
        }
    }
}
