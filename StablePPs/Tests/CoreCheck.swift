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
