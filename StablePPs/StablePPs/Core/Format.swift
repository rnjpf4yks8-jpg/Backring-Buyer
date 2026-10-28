import Foundation

/// Text with a small raised part, the way DRF prints beaten lengths ("2" + "½") and hundredths
/// of a second (":22" + "45"). Views draw `raised` smaller and higher.
struct Raised: Hashable {
    var main: String
    var raised: String = ""
    var plain: String { main + raised }
}

// MARK: Dates (kept as "YYYY-MM-DD" strings, like Firestore and the charts)

enum Dates {
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func today(_ now: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return iso(c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    static func iso(_ y: Int, _ m: Int, _ d: Int) -> String {
        String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func parts(_ iso: String) -> (y: Int, m: Int, d: Int)? {
        let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        return (p[0], p[1], p[2])
    }

    /// Days since 1970-01-01 (proleptic Gregorian), with no time zones involved.
    static func dayNumber(_ iso: String) -> Int? {
        guard let (y0, m, d) = parts(iso) else { return nil }
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let x = dayNumber(a), let y = dayNumber(b) else { return nil }
        return y - x
    }

    /// "2026-10-25" → "25Oct26", the way DRF dates a race.
    static func pp(_ iso: String?) -> String {
        guard let iso, let (y, m, d) = parts(iso) else { return "" }
        return String(format: "%02d", d) + months[m - 1] + String(format: "%02d", y % 100)
    }

    /// "2026-11-14" → "Sat Nov 14".
    static func nice(_ iso: String?) -> String {
        guard let iso, let (_, m, d) = parts(iso), let n = dayNumber(iso) else { return "" }
        let weekdays = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"]   // 1970-01-01 was a Thursday
        return "\(weekdays[((n % 7) + 7) % 7]) \(months[m - 1]) \(d)"
    }

    static func from(_ date: Date) -> String { today(date) }

    static func date(_ iso: String?) -> Date? {
        guard let iso, let (y, m, d) = parts(iso) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }

    static func stamp(_ now: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: now)
    }
}

// MARK: DRF-style pieces

enum DRF {
    /// Track abbreviations as DRF prints them ("DeD", "EvD"); others in the same style.
    static let trackAbbr: [String: String] = [
        "DED": "DeD", "EVD": "EvD", "LAD": "LaD", "TUP": "TuP", "EMD": "EmD", "ELP": "ElP", "BTP": "BtP",
        "CNL": "CnL", "PID": "PID", "WRD": "WRD", "GPW": "GPW", "ARP": "ArP", "AZD": "AzD", "SHD": "ShD",
        "MVR": "Mvr", "FAN": "FAN",
    ]

    static func trk(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return "" }
        let c = code.uppercased()
        if let a = trackAbbr[c] { return a }
        return c.count <= 2 ? c : String(c.prefix(1)) + c.dropFirst().lowercased()
    }

    static let distNames: [Double: String] = [
        4: "4f", 4.5: "4½f", 5: "5f", 5.5: "5½f", 6: "6f", 6.5: "6½f", 7: "7f", 7.5: "7½f", 8: "1m",
        8.5: "1¹⁄₁₆", 9: "1⅛", 9.5: "1³⁄₁₆", 10: "1¼", 10.5: "1⁵⁄₁₆", 11: "1⅜", 12: "1½", 13: "1⅝",
        14: "1¾", 16: "2m",
    ]

    /// Furlongs → DRF distance: 6 → "6f", 8.318 → "1m70", 8.5 → "1¹⁄₁₆".
    static func dist(_ furlongs: Double?, about: Bool = false) -> String {
        guard let f = furlongs, f > 0 else { return "" }
        var t: String? = (f * 2).rounded() / 2 == f ? distNames[f] : nil
        if t == nil, abs(f - 8.318) < 0.03 { t = "1m70" }
        if t == nil, abs(f - 8.182) < 0.03 { t = "1m40" }
        if t == nil { t = trimmed(f) + "f" }
        return (about ? "a" : "") + (t ?? "")
    }

    static func surfaceWord(_ s: String?) -> String {
        switch s { case "T": "turf"; case "A": "synthetic"; default: "dirt" }
    }

    /// "22.45" → ":22" + "45", "1:11.32" → "1:11" + "32".
    static func time(_ t: String?) -> Raised {
        guard let s = t?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return Raised(main: "") }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count >= 1, parts[1].count <= 2, parts[1].allSatisfy(\.isNumber) else {
            return Raised(main: s)
        }
        let head = parts[0]
        if let colon = head.firstIndex(of: ":") {
            let minutes = head[..<colon], seconds = head[head.index(after: colon)...]
            guard minutes.allSatisfy(\.isNumber), seconds.allSatisfy(\.isNumber), !seconds.isEmpty else { return Raised(main: s) }
            return Raised(main: "\(minutes):" + pad2(String(seconds)), raised: String(parts[1]))
        }
        guard head.allSatisfy(\.isNumber), !head.isEmpty, head.count <= 2 else { return Raised(main: s) }
        return Raised(main: ":" + pad2(String(head)), raised: String(parts[1]))
    }

    private static func pad2(_ s: String) -> String { s.count < 2 ? String(repeating: "0", count: 2 - s.count) + s : s }

    /// Chart lengths → DRF: "1 1/2" → "1½", "Head" → "hd", "Neck" → "nk", "Nose" → "no".
    static func len(_ raw: String?) -> String {
        guard var s = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return "" }
        switch s {
        case "head", "hd": return "hd"
        case "neck", "nk": return "nk"
        case "nose", "no", "ns": return "no"
        case "dh", "dead heat": return "dh"
        default: break
        }
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        s = s.replacingOccurrences(of: "1/4", with: "¼").replacingOccurrences(of: "1/2", with: "½")
            .replacingOccurrences(of: "3/4", with: "¾")
        return s.replacingOccurrences(of: " ", with: "")
    }

    /// Lengths as a number, for the race-matching math.
    static func lenNumber(_ raw: String?) -> Double {
        let s = len(raw)
        switch s {
        case "": return 0
        case "no": return 0.05
        case "hd": return 0.1
        case "nk": return 0.25
        case "dh": return 0
        default: break
        }
        var whole = "", frac = 0.0, ok = true
        for ch in s {
            if ch.isASCII, ch.isNumber, frac == 0 { whole.append(ch) }
            else if ch == "¼", frac == 0 { frac = 0.25 }
            else if ch == "½", frac == 0 { frac = 0.5 }
            else if ch == "¾", frac == 0 { frac = 0.75 }
            else { ok = false; break }
        }
        if ok { return (Double(whole) ?? 0) + frac }
        return Double(s.prefix { $0.isNumber || $0 == "." }) ?? 0
    }

    /// Position with its lengths raised: 2 + "½".
    static func pos(_ pos: Int?, _ lengths: String?) -> Raised {
        guard let pos else { return Raised(main: "") }
        return Raised(main: "\(pos)", raised: len(lengths))
    }

    static func money(_ n: Double?) -> String {
        guard let n, n.isFinite else { return "" }
        return (n < 0 ? "-$" : "$") + grouped(Int(abs(n).rounded()))
    }

    static func grouped(_ n: Int) -> String {
        let digits = String(n)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return out
    }

    static func jockey(_ j: String?) -> String {
        guard let s = j?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return "" }
        if s.contains(",") {
            let parts = s.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let first = parts.count > 1 ? parts[1].prefix(1).uppercased() : ""
            return "\(parts[0]) \(first)".trimmingCharacters(in: .whitespaces)
        }
        let words = s.split(whereSeparator: \.isWhitespace)
        guard words.count > 1, let last = words.last, let first = words.first else { return s }
        return "\(last) \(first.prefix(1).uppercased())"
    }

    static func odds(_ o: Double?, favorite: Bool?) -> String {
        guard let o else { return "" }
        return String(format: "%.2f", o) + (favorite == true ? "*" : "")
    }

    static func ordinal(_ n: Int) -> String {
        let v = n % 100
        if (11...13).contains(v) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    static func trimmed(_ x: Double) -> String {
        var s = String(format: "%.2f", x)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// The calls DRF prints between the start and the finish: the last three chart calls before the finish.
    static func calls(_ line: RaceLine) -> [Call] {
        let middle = (line.calls ?? []).filter { call in
            let label = (call.label ?? "").lowercased()
            return !label.hasPrefix("start") && !label.hasPrefix("fin")
        }
        return Array(middle.suffix(3))
    }

    static let sexWord: [String: String] = ["C": "colt", "F": "filly", "G": "gelding", "R": "ridgling", "H": "horse", "M": "mare"]

    static let typeWord: [String: String] = [
        "MSW": "Maiden special weight", "MCL": "Maiden claiming", "CLM": "Claiming", "STR": "Starter allowance",
        "ALW": "Allowance", "AOC": "Allowance optional claiming", "STK": "Stakes", "HCP": "Handicap", "OTHER": "Race",
    ]
    static let typeOrder = ["MSW", "MCL", "CLM", "STR", "ALW", "AOC", "STK", "HCP", "OTHER"]

    static let wet: Set<String> = ["gd", "my", "sly", "wf", "sys", "hy", "sf", "yl"]
}

// MARK: Records

enum Records {
    /// Newest first; the higher race number first on the same day.
    static func sorted(_ lines: [RaceLine]) -> [RaceLine] {
        lines.sorted { a, b in
            let da = a.date ?? "", db = b.date ?? ""
            if da != db { return da > db }
            return (a.race ?? 0) > (b.race ?? 0)
        }
    }

    static func of(_ lines: [RaceLine]) -> Record {
        var r = Record()
        for l in lines {
            r.starts += 1
            switch l.finish?.pos {
            case 1: r.w += 1
            case 2: r.p += 1
            case 3: r.s += 1
            default: break
            }
            r.earn += l.earnings ?? 0
        }
        return r
    }

    static func text(_ r: Record) -> String { "\(r.starts) \(r.w)-\(r.p)-\(r.s) \(DRF.money(r.earn))" }

    /// The record boxes over the past performances: life, this year and last, by surface, at the
    /// last track and at about the last distance.
    static func boxes(_ lines: [RaceLine], horse: Horse?) -> [(String, Record)] {
        let sorted = Records.sorted(lines)
        var years: [String] = []
        for l in sorted {
            let y = String((l.date ?? "").prefix(4))
            if !y.isEmpty, !years.contains(y) { years.append(y) }
        }
        var boxes: [(String, Record)] = [("Life", of(lines))]
        for y in years.prefix(2) { boxes.append((y, of(lines.filter { ($0.date ?? "").hasPrefix(y) }))) }
        boxes.append(("D.Fst", of(lines.filter { $0.surface == "D" && !DRF.wet.contains($0.condition ?? "") })))
        boxes.append(("Wet", of(lines.filter { $0.surface == "D" && DRF.wet.contains($0.condition ?? "") })))
        boxes.append(("Turf", of(lines.filter { $0.surface == "T" })))
        boxes.append(("Synth", of(lines.filter { $0.surface == "A" })))
        if let last = sorted.first {
            boxes.append((DRF.trk(last.track), of(lines.filter { $0.track == last.track })))
            let near = lines.filter { abs(($0.distanceF ?? 0) - (last.distanceF ?? 0)) <= 0.5 && $0.surface == last.surface }
            boxes.append(("Dst", of(near)))
        }
        if let known = horse?.known, let starts = known.starts, starts > lines.count {
            boxes.insert(("Known", Record(starts: starts, w: known.wins ?? 0, p: 0, s: 0, earn: 0)), at: 0)
        }
        return boxes
    }

    /// What the horse list shows for a horse's latest race.
    static func lastRace(_ lines: [RaceLine]) -> Horse.LastRace? {
        guard let last = Records.sorted(lines).first else { return nil }
        return Horse.LastRace(date: last.date, track: last.track, race: last.race, distanceF: last.distanceF,
                              surface: last.surface ?? "D", finish: last.finish?.pos, classText: last.classText)
    }
}
