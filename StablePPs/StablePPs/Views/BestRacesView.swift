import SwiftUI

/// Upcoming condition-book races within 200 miles of where the horse last ran, best first.
struct BestRacesView: View {
    let horse: Horse
    let lines: [RaceLine]
    @Environment(StableStore.self) private var store
    @State private var showAll = false

    var body: some View {
        let result = Matching.bestRaces(horse: horse, lines: lines, books: store.books, today: Dates.today())
        let eligible = result.matches.filter { $0.fit.status == .eligible }.count
        let toCheck = result.matches.filter { $0.fit.status == .check }.count
        let hidden = result.matches.filter { $0.fit.status == .notEligible }.count
        let shown = showAll ? result.matches : result.matches.filter { $0.fit.status != .notEligible }

        VStack(alignment: .leading, spacing: 10) {
            if let from = result.from {
                if store.books.isEmpty {
                    Card {
                        Text("No condition books loaded yet").font(.headline)
                        Text("Add the current condition book PDFs for tracks near \(from.name) under **Condition books** (the book button on the horse list), and the best races show up here.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("Within 200 miles of \(from.name) · \(eligible) eligible · \(toCheck) to check")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.muted).textCase(.uppercase)
                    if hidden > 0 {
                        Button(showAll ? "Hide races \(horse.name) can’t run in" : "Show \(hidden) race\(hidden == 1 ? "" : "s") not eligible") {
                            showAll.toggle()
                        }
                        .buttonStyle(ActionButtonStyle())
                    }
                    if result.matches.isEmpty {
                        Note(text: "No upcoming book races within 200 miles of \(from.name). Load the condition books for tracks nearer to it.")
                    }
                    ForEach(shown.prefix(60)) { match in RaceCard(match: match) }
                }
            } else {
                Card {
                    Text("Add \(horse.name)'s latest chart first").font(.headline)
                    Text("Best races are searched within 200 miles of the track where the horse last ran. For an unraced horse, set its home track under Edit.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            Note(text: "Ranked from the horse's lines in the app: eligibility (age, sex, state-bred, conditions), class against recent claiming level and form, distance and surface where it has run well, days since its last race, and travel. Condition-book races may not fill or may be changed by the racing office.")
        }
    }
}

struct RaceCard: View {
    let match: RaceMatch

    var body: some View {
        let r = match.race
        let fit = match.fit
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(Dates.nice(r.date)).font(Theme.display(20)).foregroundStyle(Theme.ink)
                Text(match.track.name + (r.raceNo.map { " · book race \($0)" } ?? ""))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(fit.score)")
                    .font(Theme.data(16, .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 34, minHeight: 28)
                    .background(scoreColor, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("Score \(fit.score) of 100")
            }
            Text("\(Matching.title(r)) · \((r.distanceText ?? "").isEmpty ? DRF.dist(r.distanceF) : (r.distanceText ?? "")) \(DRF.surfaceWord(r.surface))")
                .font(.headline)
            Text(whoLine).font(.subheadline).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    switch fit.status {
                    case .eligible: Chip(text: "Eligible", color: Theme.good, fill: Theme.turfSoft)
                    case .check: Chip(text: "Check", color: Theme.warn, fill: Color(hex: 0xFBF1DC))
                    case .notEligible: Chip(text: "Not eligible", color: Theme.bad, fill: Color(hex: 0xF8E3E1))
                    }
                    ForEach(fit.chips, id: \.self) { chip in
                        Chip(text: chip.text, color: chip.warn ? Theme.warn : Theme.muted)
                    }
                    ForEach(fit.checks, id: \.self) { check in
                        Chip(text: check, color: Theme.warn, fill: Color(hex: 0xFBF1DC))
                    }
                }
            }
            let bullets = fit.blockers.isEmpty ? fit.reasons : fit.blockers
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(bullets, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(line)
                        }
                        .font(.subheadline)
                        .foregroundStyle(fit.blockers.isEmpty ? Theme.ink : Theme.bad)
                    }
                }
            }
            if let text = r.text, !text.isEmpty {
                Text(text).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .opacity(fit.status == .notEligible ? 0.75 : 1)
    }

    private var whoLine: String {
        var parts = [Matching.who(match.race)]
        if let purse = match.race.purse, purse > 0 { parts.append("purse \(DRF.money(purse))") }
        parts.append("\(match.miles) miles away")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var scoreColor: Color {
        switch match.fit.status {
        case .eligible: match.fit.score >= 70 ? Theme.good : Theme.turf
        case .check: Theme.warn
        case .notEligible: Theme.muted
        }
    }
}
