// Checks Stable PPs' DRF formatting and race matching (StablePPs/StablePPs/Core) without the app,
// against results from the web version of Stable PPs (StablePPs/Tests/fixtures.json). From the repo root:
//   swiftc -parse-as-library StablePPs/StablePPs/Core/*.swift StablePPs/Tests/CoreCheck.swift -o /tmp/pp && /tmp/pp
// GitHub Actions runs it on every push.
import Foundation

var failures = 0
func check(_ condition: Bool, _ what: String, line: Int = #line) {
    if condition { print("ok   \(what)") } else { failures += 1; print("FAIL \(what) (line \(line))") }
}
func same<T: Equatable>(_ got: T, _ want: T, _ what: String, line: Int = #line) {
    check(got == want, got == want ? what : "\(what): got \(got), want \(want)", line: line)
}

struct Fixtures: Decodable {
    struct Match: Decodable {
        var book: String
        var date: String
        var raceNo: String?
        var miles: Int
        var status: String
        var score: Int
        var blockers: [String]
        var checks: [String]
        var reasons: [String]
        var chips: [String]
        var title: String
        var who: String
    }
    struct Best: Decodable {
        var from: String?
        var matches: [Match]
    }
    struct Formats: Decodable {
        var dist: [[Double2String]]
        var len: [[StringOrNumber]]
        var ppDate: [[String]]
        var nice: [[String]]
        var jockey: [[String]]
        var odds: [[StringOrNumber]]
        var trk: [[String]]
        var days: [[StringOrNumber]]
        var miles: [[StringOrNumber]]
        var boxes: [String: [[StringOrNumber]]]
    }
    var today: String
    var horses: [Horse]
    var lines: [String: [RaceLine]]
    var books: [ConditionBook]
    var best: [String: Best]
    var fmt: Formats
}

/// A JSON array cell that may be a string, a number or a bool.
enum StringOrNumber: Decodable {
    case s(String), n(Double), b(Bool)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .b(b) }
        else if let n = try? c.decode(Double.self) { self = .n(n) }
        else { self = .s(try c.decode(String.self)) }
    }
    var string: String { if case .s(let s) = self { return s }; return "" }
    var number: Double { if case .n(let n) = self { return n }; return .nan }
    var bool: Bool { if case .b(let b) = self { return b }; return false }
}
typealias Double2String = StringOrNumber

@main
struct CoreCheck {
    static func main() throws {
        let url = URL(fileURLWithPath: "StablePPs/Tests/fixtures.json")
        let fx = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))

        // DRF pieces
        for row in fx.fmt.dist { same(DRF.dist(row[0].number), row[1].string, "distance \(row[0].number)") }
        for row in fx.fmt.len {
            same(DRF.len(row[0].string), row[1].string, "lengths '\(row[0].string)'")
            same(DRF.lenNumber(row[0].string), row[2].number, "lengths number '\(row[0].string)'")
        }
        for row in fx.fmt.ppDate { same(Dates.pp(row[0]), row[1], "DRF date \(row[0])") }
        for row in fx.fmt.nice { same(Dates.nice(row[0]), row[1], "day \(row[0])") }
        for row in fx.fmt.jockey { same(DRF.jockey(row[0]), row[1], "jockey \(row[0])") }
        for row in fx.fmt.odds { same(DRF.odds(row[0].number, favorite: row[1].bool), row[2].string, "odds \(row[0].number)") }
        for row in fx.fmt.trk { same(DRF.trk(row[0]), row[1], "track \(row[0])") }
        for row in fx.fmt.days { same(Dates.daysBetween(row[0].string, row[1].string), Int(row[2].number), "days \(row[0].string)–\(row[1].string)") }
        for row in fx.fmt.miles {
            let a = Track.find(row[0].string)!, b = Track.find(row[1].string)!
            same(Int(Track.miles(a, b).rounded()), Int(row[2].number), "miles \(a.code)–\(b.code)")
        }
        same(DRF.time("22.45"), Raised(main: ":22", raised: "45"), "fraction")
        same(DRF.time("1:11.32"), Raised(main: "1:11", raised: "32"), "final time")
        same(DRF.time("1:38.7"), Raised(main: "1:38", raised: "7"), "final time, tenths")
        same(DRF.money(1234567), "$1,234,567", "money")
        same(DRF.money(0), "$0", "money zero")
        same(DRF.ordinal(1) + DRF.ordinal(2) + DRF.ordinal(3) + DRF.ordinal(11) + DRF.ordinal(22), "1st2nd3rd11th22nd", "ordinals")
        same(RaceLine.key(date: "2026-10-12", track: "ded", race: 2), "2026-10-12-DED-2", "line key")
        same(Track.find("Delta Downs")?.code, "DED", "track by name")
        same(Track.find("Fair Grounds Race Course")?.code, "FG", "track by longer name")

        // Last race and entry summaries
        var line = RaceLine(id: "x")
        line.date = "2026-10-12"; line.track = "DED"; line.race = 2; line.fieldSize = 9
        line.finish = Finish(pos: 2, lengths: "1 1/2"); line.beyer = 72; line.earnings = 4000
        var older = RaceLine(id: "y")
        older.date = "2026-09-01"; older.finish = Finish(pos: 1)
        let last = Records.lastRace([older, line])
        same(last?.lineID, "x", "last race is the newest line")
        same(last.map(Summary.lastResult), "2nd of 9 (1½) · Beyer 72 · Won $4,000", "last race summary")
        var noBeyer = last!
        noBeyer.beyer = nil; noBeyer.earnings = 0; noBeyer.fieldSize = nil; noBeyer.lengths = nil
        same(Summary.lastResult(noBeyer), "2nd · Beyer – · Won $0", "last race without Beyer")
        noBeyer.speed = 68
        same(Summary.lastResult(noBeyer), "2nd · Speed 68 · Won $0", "last race with only an Equibase Speed Figure")
        var entry = Entry(date: "2026-11-14")
        entry.track = "DED"; entry.race = 5; entry.postPosition = 4; entry.morningLine = "5-2"
        entry.jockey = "Gonzalez, Ricardo"; entry.weight = 122; entry.medEq = "L"; entry.fieldSize = 9
        entry.distanceF = 6; entry.surface = "D"; entry.classText = "Md 30000"; entry.purse = 28000
        same(Summary.entryWhen(entry), "Sat Nov 14 · Delta Downs · Race 5", "entry when")
        same(Summary.entryRace(entry), "6f dirt · Md 30000 · purse $28,000", "entry race")
        same(Summary.entryHorse(entry), "Post 4 · ML 5-2 · Gonzalez R · 122 L · 9 entered", "entry horse")
        same(Summary.entryShort(entry), "Entered Sat Nov 14 DeD R5", "entry one-liner")
        check(entry.isUpcoming(today: "2026-11-14") && !entry.isUpcoming(today: "2026-11-15"), "entry upcoming through race day")

        // Record boxes
        for horse in fx.horses {
            let want = fx.fmt.boxes[horse.id] ?? []
            let got = Records.boxes(fx.lines[horse.id] ?? [], horse: horse)
            same(got.count, want.count, "\(horse.name): record boxes")
            for (g, w) in zip(got, want) {
                same("\(g.0) \(g.1.starts) \(g.1.w)-\(g.1.p)-\(g.1.s) \(Int(g.1.earn))",
                     "\(w[0].string) \(Int(w[1].number)) \(Int(w[2].number))-\(Int(w[3].number))-\(Int(w[4].number)) \(Int(w[5].number))",
                     "\(horse.name): \(g.0) box")
            }
        }

        // Best races, every field, in order
        let statusWord: [RaceFit.Status: String] = [.eligible: "eligible", .check: "check", .notEligible: "not"]
        for horse in fx.horses {
            guard let want = fx.best[horse.id] else { continue }
            let got = Matching.bestRaces(horse: horse, lines: fx.lines[horse.id] ?? [], books: fx.books, today: fx.today)
            same(got.from?.code, want.from, "\(horse.name): searched from")
            same(got.matches.count, want.matches.count, "\(horse.name): races within 200 miles")
            for (i, (g, w)) in zip(got.matches, want.matches).enumerated() {
                let label = "\(horse.name) #\(i + 1) \(w.book) \(w.date) race \(w.raceNo ?? "-")"
                same("\(g.book.id) \(g.race.date) \(g.race.raceNo ?? "-")", "\(w.book) \(w.date) \(w.raceNo ?? "-")", "\(label): order")
                same(g.miles, w.miles, "\(label): miles")
                same(statusWord[g.fit.status] ?? "", w.status, "\(label): status")
                same(g.fit.score, w.score, "\(label): score")
                same(g.fit.blockers, w.blockers, "\(label): blockers")
                same(g.fit.checks, w.checks, "\(label): checks")
                same(g.fit.reasons, w.reasons, "\(label): reasons")
                same(g.fit.chips.map { $0.text + ($0.warn ? "!" : "") }, w.chips, "\(label): chips")
                same(Matching.title(g.race), w.title, "\(label): title")
                same(Matching.who(g.race), w.who.trimmingCharacters(in: CharacterSet(charactersIn: " ·")), "\(label): who")
            }
        }

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        if failures > 0 { exit(1) }
    }
}
