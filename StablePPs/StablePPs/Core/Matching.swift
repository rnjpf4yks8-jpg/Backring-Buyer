import Foundation

/// How a condition-book race suits a horse.
struct RaceFit: Hashable {
    enum Status: Int, Hashable { case eligible = 0, check = 1, notEligible = 2 }
    struct Chip: Hashable { var text: String; var warn: Bool }

    var status: Status
    var score: Int              // 0–100
    var blockers: [String]      // why it can't run
    var checks: [String]        // what the app can't tell from what it knows
    var reasons: [String]       // plain sentences for the race card
    var chips: [Chip]
}

/// A book race within reach of the horse, with how well it fits.
struct RaceMatch: Hashable, Identifiable {
    var race: BookRace
    var book: ConditionBook
    var track: Track
    var miles: Int
    var fit: RaceFit

    var id: String { "\(book.id)|\(race.date)|\(race.raceNo ?? "")|\(race.type)|\(race.distanceF ?? 0)|\(race.claim ?? 0)|\(race.sex ?? "")|\(race.ages ?? "")" }
}

enum Matching {
    static let claimingTypes = ["CLM", "MCL"]

    static func ageOn(_ horse: Horse, _ iso: String) -> Int? {
        guard let foal = horse.foalYear, let y = Int(iso.prefix(4)) else { return nil }
        return y - foal
    }

    static func wins(_ horse: Horse, _ lines: [RaceLine]) -> Int {
        max(lines.filter(\.won).count, horse.known?.wins ?? 0)
    }

    static func starts(_ horse: Horse, _ lines: [RaceLine]) -> Int {
        max(lines.count, horse.known?.starts ?? 0)
    }

    /// Wins that count against "never won a race other than maiden, claiming, starter or optional claiming".
    static func allowanceWins(_ lines: [RaceLine]) -> Int {
        lines.filter { $0.won && !["MSW", "MCL", "CLM", "STR", "AOC"].contains($0.type ?? "") }.count
    }

    /// How a race went for the horse, 0 (poor) to 1 (won or very close).
    static func effort(_ l: RaceLine) -> Double {
        let field = (l.fieldSize ?? 0) > 0 ? l.fieldSize! : 8
        guard let f = l.finish?.pos, f > 0 else { return 0.3 }
        if f == 1 { return 1 }
        let beaten = DRF.lenNumber(l.finish?.lengths)
        if f <= 3 && beaten <= 3 { return 0.85 }
        if beaten <= 4 { return 0.7 }
        if f <= Int((Double(field) / 2).rounded(.up)) || beaten <= 7 { return 0.5 }
        return 0.2
    }

    private static func agesNumber(_ ages: String) -> Int? {
        Int(ages.prefix { $0.isNumber })
    }

    /// Scores one condition-book race for a horse.
    static func evaluate(horse: Horse, lines: [RaceLine], race: BookRace, raceTrack: String?, lastTrack: Track?) -> RaceFit {
        let sorted = Records.sorted(lines)
        let last = sorted.first
        var blockers: [String] = [], checks: [String] = [], reasons: [String] = [], chips: [RaceFit.Chip] = []
        let age = ageOn(horse, race.date)
        let wins = Matching.wins(horse, lines)
        let starts = Matching.starts(horse, lines)

        // Who may run
        let ages = race.ages ?? ""
        if let age {
            let n = agesNumber(ages)
            let andUp = ages.hasSuffix("U")
            if let n, andUp ? age < n : age != n {
                blockers.append("For \(andUp ? "\(n)-year-olds and up" : "\(n)-year-olds"); \(horse.name) is \(age).")
            }
        } else {
            checks.append("Foaling year not set")
        }
        if race.sex == "F" && !horse.isFemale { blockers.append("Fillies and mares only.") }
        if let bred = race.stateBred, !bred.isEmpty {
            if let mine = horse.bredIn {
                if mine != bred { blockers.append("\(bred)-breds only.") }
            } else {
                checks.append("\(bred)-bred only; set where \(horse.name) was bred")
            }
        }
        if race.maiden == true && wins > 0 { blockers.append("For maidens; already a winner.") }
        if let nw = race.nw, let n = nw.n {
            switch nw.kind {
            case "lifetime" where wins >= n:
                blockers.append("Never won \(n == 1 ? "a race" : "\(n) races"); has \(wins) win\(wins == 1 ? "" : "s").")
            case "otherThan" where allowanceWins(lines) >= n:
                blockers.append("Allowance condition: has \(allowanceWins(lines)) win(s) other than maiden, claiming or starter.")
            case "since":
                if let since = nw.since, !since.isEmpty, lines.contains(where: { $0.won && ($0.date ?? "") >= since }) {
                    blockers.append("Has won since \(since).")
                }
            default: break
            }
        }
        if let claim = race.starter?.claim, claim > 0 {
            let since = race.starter?.since ?? ""
            let ranFor = lines.contains { l in
                claimingTypes.contains(l.type ?? "") && (l.claimPrice ?? 0) <= claim && (since.isEmpty || (l.date ?? "") >= since)
            }
            if !ranFor {
                blockers.append("Starter allowance: must have started for \(DRF.money(claim)) or less\(since.isEmpty ? "" : " since " + since).")
            }
        }
        if starts > lines.count { checks.append("Only \(lines.count) of \(starts) starts are in the app") }

        // Class
        var cls = 0.0
        let recent = Array(sorted.prefix(3))
        let lastClaim = sorted.first { ($0.claimPrice ?? 0) > 0 && ["CLM", "MCL", "AOC"].contains($0.type ?? "") }?.claimPrice
        let form: Double? = recent.isEmpty ? nil : recent.map(effort).reduce(0, +) / Double(recent.count)
        let claim = (race.claim ?? 0) > 0 ? race.claim : nil
        if starts == 0 {
            switch race.type {
            case "MSW": cls = 30; reasons.append("First-time starter: maiden special weight is the usual debut.")
            case "MCL": cls = 22; reasons.append("First-time starter: maiden claiming is an option if you'd risk a claim.")
            case "STK": cls = 8
            default: cls = 10
            }
        } else if wins == 0 {
            let bestMsw = lines.filter { $0.type == "MSW" }.map(effort).reduce(0, max)
            if race.type == "MSW" {
                cls = bestMsw >= 0.7 ? 32 : bestMsw >= 0.5 ? 22 : 10
                reasons.append(bestMsw >= 0.7 ? "Has run well against maiden special weight company."
                               : "Maiden special weight; form so far suggests dropping into maiden claiming.")
            } else if race.type == "MCL" {
                let target = lastClaim ?? (bestMsw >= 0.5 ? 50000 : 25000)
                let r = (claim ?? target) / target
                if let form, form < 0.5 { cls = r <= 1.05 ? 32 : 20 } else { cls = r >= 0.8 && r <= 1.3 ? 30 : 18 }
                reasons.append("Maiden claiming\(claim.map { " for " + DRF.money($0) } ?? "")\(lastClaim.map { "; last ran for " + DRF.money($0) } ?? "").")
            } else {
                cls = 6
            }
        } else {
            if race.type == "CLM", let claim, lastClaim == nil {
                cls = 18
                reasons.append("Would be the first time running for a claiming price (\(DRF.money(claim))); another stable could claim the horse.")
            } else if race.type == "CLM", let claim, let base = lastClaim {
                let lastEff = last.map(effort) ?? 0.5
                let lo = lastEff >= 1 ? 1.0 : lastEff >= 0.7 ? 0.8 : 0.5
                let hi = lastEff >= 1 ? 1.6 : lastEff >= 0.7 ? 1.25 : 0.95
                let r = claim / base
                cls = r >= lo && r <= hi ? 33 : r < lo ? 22 : 10
                let note = lastEff >= 1 ? " (won last out, a step up is fair)" : lastEff < 0.5 ? " (last effort was flat, a drop helps)" : ""
                reasons.append("Claiming for \(DRF.money(claim)) vs. last tag \(DRF.money(base))\(note).")
            } else if ["ALW", "AOC"].contains(race.type) {
                let good = recent.contains { effort($0) >= 0.85 && ["ALW", "AOC", "STK", "CLM", "MSW"].contains($0.type ?? "") }
                cls = good ? 28 : 14
                reasons.append(good ? "Recent top-three or winning form fits allowance company." : "Allowance is a class test on current form.")
            } else if race.type == "STR" {
                cls = 26
                reasons.append("Starter allowance: protected spot if eligible.")
            } else if race.type == "STK" {
                let top = recent.contains { $0.won && ["ALW", "AOC", "STK"].contains($0.type ?? "") }
                cls = top ? 24 : 8
                reasons.append(top ? "Has won at allowance or stakes level." : "Stakes would be a big class jump.")
            } else if ["MSW", "MCL"].contains(race.type) {
                cls = 0
            } else {
                cls = 12
            }
        }

        // Distance and surface
        var dist = 12.0, surf = 10.0
        if !lines.isEmpty, let rd = race.distanceF, rd > 0 {
            let near = lines.filter { abs(($0.distanceF ?? 0) - rd) <= 1 }
            let goodNear = near.filter { effort($0) >= 0.7 }
            if !goodNear.isEmpty {
                dist = 25
                reasons.append("\(goodNear.count) good effort\(goodNear.count == 1 ? "" : "s") within a furlong of \(DRF.dist(rd)).")
            } else if !near.isEmpty {
                dist = 15
            } else {
                dist = 8
                reasons.append("New distance type: has not run near \(DRF.dist(rd)).")
            }
        }
        if !lines.isEmpty, let rs = race.surface, !rs.isEmpty {
            let on = lines.filter { $0.surface == rs }
            let word = DRF.surfaceWord(rs)
            if on.contains(where: { effort($0) >= 0.7 }) {
                surf = 20
            } else if !on.isEmpty {
                surf = 6
                reasons.append("Hasn't run well on \(word) yet.")
            } else {
                surf = 10
                reasons.append("Would be first time on \(word).")
            }
        }

        // Timing and travel
        var timing = 7.0, travel = 6.0
        if let lastDate = last?.date, let gap = Dates.daysBetween(lastDate, race.date) {
            timing = gap < 10 ? 0 : gap < 21 ? 5 : gap <= 60 ? 10 : gap <= 120 ? 7 : 5
            chips.append(RaceFit.Chip(text: "\(gap) days after last race", warn: gap < 14))
            if gap < 10 { checks.append("Less than 10 days after the last race") }
        }
        if let lastTrack, let t = Track.find(raceTrack) {
            travel = max(2, (10 - Track.miles(lastTrack, t) / 25).rounded())
        }

        let total = Int((cls + dist + surf + timing + travel).rounded())
        let score = max(0, min(100, total))
        let status: RaceFit.Status = !blockers.isEmpty ? .notEligible : !checks.isEmpty ? .check : .eligible
        return RaceFit(status: status, score: blockers.isEmpty ? score : min(score, 30),
                       blockers: blockers, checks: checks, reasons: reasons, chips: chips)
    }

    /// The track to search from: where the horse last ran, or its home track if unraced.
    static func searchTrack(horse: Horse, lines: [RaceLine]) -> Track? {
        Track.find(Records.sorted(lines).first?.track) ?? Track.find(horse.homeTrack)
    }

    /// Every upcoming book race within `radius` miles of the horse's last track, best first.
    static func bestRaces(horse: Horse, lines: [RaceLine], books: [ConditionBook], today: String,
                          radius: Double = 200) -> (from: Track?, matches: [RaceMatch]) {
        guard let from = searchTrack(horse: horse, lines: lines) else { return (nil, []) }
        var out: [RaceMatch] = []
        for book in books {
            guard let t = Track.find(book.track) else { continue }
            let miles = Track.miles(from, t)
            if miles > radius { continue }
            for race in book.races where race.date >= today {
                let fit = evaluate(horse: horse, lines: lines, race: race, raceTrack: book.track, lastTrack: from)
                out.append(RaceMatch(race: race, book: book, track: t, miles: Int(miles.rounded()), fit: fit))
            }
        }
        out.sort { a, b in
            if a.fit.status != b.fit.status { return a.fit.status.rawValue < b.fit.status.rawValue }
            if a.fit.score != b.fit.score { return a.fit.score > b.fit.score }
            return a.race.date < b.race.date
        }
        return (from, out)
    }

    static func title(_ r: BookRace) -> String {
        var parts: [String] = []
        if r.type == "STK", let name = r.name, !name.isEmpty { parts.append(name) }
        else { parts.append(DRF.typeWord[r.type] ?? (r.type.isEmpty ? "Race" : r.type)) }
        if let claim = r.claim, claim > 0, ["CLM", "MCL", "AOC"].contains(r.type) {
            if let low = r.claimLow, low > 0, low != claim { parts.append("\(DRF.money(low))–\(DRF.money(claim))") }
            else { parts.append(DRF.money(claim)) }
        }
        return parts.joined(separator: " ")
    }

    static func who(_ r: BookRace) -> String {
        let a = r.ages ?? ""
        let n = agesNumber(a)
        let andUp = a.hasSuffix("U")
        var who = ""
        if let n { who = andUp ? "\(n)yo & up" : "\(n)yo" }
        if r.sex == "F" {
            if who.isEmpty { who = "Fillies & mares" }
            else { who += (n ?? 0) >= 3 && andUp ? " fillies & mares" : " fillies" }
        }
        if let bred = r.stateBred, !bred.isEmpty { who += " · \(bred)-bred" }
        if r.maiden == true { who += " · maidens" }
        if let nw = r.nw, let k = nw.n {
            switch nw.kind {
            case "lifetime": who += k == 1 ? " · non-winners" : " · NW\(k)L"
            case "otherThan": who += " · NW\(k)X"
            case "since": who += " · NW\(k) since \(nw.since ?? "")"
            default: break
            }
        }
        return who.trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
    }
}
