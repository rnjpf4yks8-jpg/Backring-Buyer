import Foundation

/// Loads a Fasig-Tipton sale's catalog from fasigtipton.com: every hip with its pedigree, consignor, barn,
/// walk video, photo, catalog page and whether it's out. Uses the same public data the sale's catalogue
/// page on fasigtipton.com loads (`/django/api/...`). The administrator imports it from the app; re-running
/// it picks up new videos, photos and outs.
///
/// Foundation only, so Tests/FasigTiptonCheck.swift can test it on its own.
enum FasigTipton {
    static let site = URL(string: "https://www.fasigtipton.com")!

    // MARK: What the administrator typed

    /// A sale page link (as copied from Safari, even with a title in front) or a sale code like "M26B".
    enum Input: Equatable {
        case page(URL)
        case code(String)
    }

    static func input(from text: String) -> Input? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[A-Za-z]\d{2}[A-Za-z0-9]{1,3}$"#, options: .regularExpression) != nil {
            return .code(trimmed.uppercased())
        }
        guard let match = trimmed.range(of: #"(https?://)?(www\.)?fasigtipton\.com/[^\s"'<>]*"#,
                                        options: [.regularExpression, .caseInsensitive]) else { return nil }
        var link = String(trimmed[match])
        if !link.lowercased().hasPrefix("http") { link = "https://" + link }
        guard var parts = URLComponents(string: link) else { return nil }
        parts.scheme = "https"
        parts.fragment = nil   // "#/" and "#/?section=…" are only for the page's own app
        parts.query = nil
        return parts.url.map(Input.page)
    }

    // MARK: The sale page

    /// What a sale's catalogue page says about itself (in its embedded settings).
    struct PageInfo: Equatable {
        var code: String
        /// "Eastern Fall Yearlings (2026)"
        var title: String?
        /// "10-27-2026"
        var startDate: String?
    }

    static func pageInfo(fromHTML html: String) -> PageInfo? {
        // Drupal keeps the page settings as JSON in <script data-drupal-selector="drupal-settings-json">.
        if let start = html.range(of: #"<script[^>]*drupal-settings-json[^>]*>"#, options: .regularExpression),
           let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
           let data = String(html[start.upperBound..<end.lowerBound]).data(using: .utf8),
           let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let catalogues = settings["catalogues"] as? [String: Any],
           let code = catalogues["sale_identifier"] as? String, !code.isEmpty {
            return PageInfo(code: code, title: catalogues["title"] as? String, startDate: catalogues["sale_start_date"] as? String)
        }
        // Fallback: pick the values out of the text.
        func value(_ key: String) -> String? {
            guard let r = html.range(of: "\"\(key)\":\"([^\"]+)\"", options: .regularExpression) else { return nil }
            return String(html[r]).components(separatedBy: "\":\"").last.map { String($0.dropLast()) }
        }
        guard let code = value("sale_identifier") else { return nil }
        return PageInfo(code: code, title: value("title"), startDate: value("sale_start_date"))
    }

    // MARK: The data

    struct SaleInfo: Decodable {
        var id: Int
        var saleIdentifier: String
        /// "2026-10-27"
        var saleStartDay: String?
    }

    struct Horse: Decodable, Equatable {
        var hip: Int
        var session: String?
        var color: String?
        var name: String?
        var sex: String?
        var sire: String?
        var dam: String?
        var sireOfDam: String?
        var consignor: String?
        var barn: String?
        var yearOfBirth: String?
        /// The state or country foaled in, like "KY".
        var foaled: String?
        var out: Bool
        var youtubeUrl: String?
        var photos: [String]

        private enum Keys: String, CodingKey {
            case hip, session, color, name, sex, sire, dam, sireOfDam, consignor, barn, yearOfBirth, foaled, out, youtubeUrl
            case generalhorsephotoSet, enhancedhorsephotoSet
        }
        private struct Photo: Decodable { var photo: String? }

        /// Lenient: a field of an unexpected type is treated as missing instead of failing the whole sale.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            func text(_ key: Keys) -> String? {
                if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
                if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return String(n) }
                return nil
            }
            if let n = try? c.decode(Int.self, forKey: .hip) {
                hip = n
            } else if let s = text(.hip), let n = CatalogImport.hipNumber(s) {
                hip = n
            } else {
                throw DecodingError.dataCorruptedError(forKey: .hip, in: c, debugDescription: "no hip number")
            }
            session = text(.session)
            color = text(.color)
            name = text(.name)
            sex = text(.sex)
            sire = text(.sire)
            dam = text(.dam)
            sireOfDam = text(.sireOfDam)
            consignor = text(.consignor)
            barn = text(.barn)
            yearOfBirth = text(.yearOfBirth)
            foaled = text(.foaled)
            out = (try? c.decodeIfPresent(Bool.self, forKey: .out)) ?? false
            youtubeUrl = text(.youtubeUrl)
            let enhanced = (try? c.decodeIfPresent([Photo].self, forKey: .enhancedhorsephotoSet)) ?? nil
            let general = (try? c.decodeIfPresent([Photo].self, forKey: .generalhorsephotoSet)) ?? nil
            photos = ((enhanced ?? []) + (general ?? [])).compactMap(\.photo).filter { !$0.isEmpty }
        }

        init(hip: Int) {
            self.hip = hip
            out = false
            photos = []
        }
    }

    /// Hips that failed to read are skipped (and counted) rather than stopping the import.
    struct Lenient<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    // MARK: Turning a horse into a hip

    /// The sale as the app names it: "Eastern Fall Yearlings (2026)" → "Eastern Fall Yearlings".
    static func saleName(fromTitle title: String?, code: String) -> String {
        let name = (title ?? "")
            .replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Fasig-Tipton sale \(code)" : name
    }

    /// The sale's first day from the data ("2026-10-27") or the page ("10-27-2026").
    static func saleDay(apiDay: String?, pageDate: String?) -> Date? {
        if let apiDay, let day = format("yyyy-MM-dd").date(from: apiDay) { return day }
        if let pageDate, let day = format("MM-dd-yyyy").date(from: pageDate) { return day }
        return nil
    }

    /// Each hip's catalog page, like https://www.fasigtipton.com/catalogs/2026/1027/2.pdf.
    static func catalogPage(hip: Int, saleDay: Date) -> URL {
        site.appendingPathComponent("catalogs/\(format("yyyy/MMdd").string(from: saleDay))/\(hip).pdf")
    }

    static func row(_ horse: Horse, saleDay: Date?) -> CatalogImport.Row {
        var row = CatalogImport.Row(number: horse.hip)
        // Unnamed yearlings are listed as "2025-RAVER" (year and dam): the app shows them as unnamed.
        let name = (horse.name ?? "").trimmingCharacters(in: .whitespaces)
        row.name = name.range(of: #"^\d{4}-"#, options: .regularExpression) != nil ? "" : titleCase(name)
        row.sex = clean(horse.sex).map(CatalogImport.sexWord)
        row.color = clean(horse.color).map(CatalogImport.colorWord)
        if let born = clean(horse.yearOfBirth) {
            let day = format("MM/dd/yyyy").date(from: born).map { format("MMM d, yyyy").string(from: $0) } ?? born
            row.foaled = clean(horse.foaled).map { "\(day) (\($0))" } ?? day
        }
        if let session = clean(horse.session) {
            row.session = format("yyyy-MM-dd").date(from: session).map { format("EEE, MMM d").string(from: $0) } ?? session
        }
        if let barn = clean(horse.barn) {
            row.barn = barn.lowercased().hasPrefix("barn") ? barn : "Barn \(barn)"
        }
        row.consignor = clean(horse.consignor).map(titleCase)
        row.sire = clean(horse.sire).map(titleCase)
        row.dam = clean(horse.dam).map(titleCase)
        row.damSire = clean(horse.sireOfDam).map(titleCase)
        row.walkVideoURL = clean(horse.youtubeUrl).flatMap(CatalogImport.webLink)
        row.photoURL = horse.photos.first.flatMap(CatalogImport.webLink)
        if let saleDay { row.pedigreeURL = catalogPage(hip: horse.hip, saleDay: saleDay) }
        row.isOut = horse.out
        return row
    }

    private static func clean(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Catalog names are in capitals: "JACKIE'S WARRIOR" → "Jackie's Warrior", "MCPEEK" → "McPeek",
    /// "O'BRIEN" → "O'Brien". Roman numerals, LLC and the like stay as they are.
    static func titleCase(_ text: String) -> String {
        let keep: Set<String> = ["II", "III", "IV", "VI", "VII", "VIII", "IX", "LLC", "LP", "LTD", "INC", "USA", "DVM", "TB"]
        return text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let bare = word.trimmingCharacters(in: .punctuationCharacters).uppercased()
            if keep.contains(bare) { return word.uppercased() }
            var result = ""
            var capitalizeNext = true
            var lettersSinceBreak = 0
            var lastLetter: Character = " "
            for ch in word.lowercased() {
                if ch.isLetter {
                    result.append(capitalizeNext ? Character(ch.uppercased()) : ch)
                    capitalizeNext = false
                    lettersSinceBreak += 1
                    lastLetter = ch
                    // "Mc" names: McPeek, McKinzie.
                    if lettersSinceBreak == 2, result.hasSuffix("Mc") || result == "Mc" { capitalizeNext = true }
                } else {
                    result.append(ch)
                    // A new part starts after these; after an apostrophe only for O'Brien, D'Arcy.
                    if "-/(&.".contains(ch) { capitalizeNext = true; lettersSinceBreak = 0 }
                    if ch == "'" || ch == "’" {
                        capitalizeNext = lettersSinceBreak == 1 && (lastLetter == "o" || lastLetter == "d")
                        lettersSinceBreak = 0
                    }
                }
            }
            return result
        }.joined(separator: " ")
    }

    private static func format(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f
    }

    // MARK: The list of sales

    /// One sale on fasigtipton.com/catalogues/<year>.
    struct Catalogue: Equatable, Identifiable {
        var id: String { url.absoluteString }
        var name: String
        var url: URL
        /// As Fasig-Tipton writes them: "Oct 27, 2026" or "Oct 19 - 22, 2026".
        var dates: String
        var location: String
        var cover: URL?
        var firstDay: Date?
    }

    /// Reads the sales listed on a catalogues page. Each sale is a "catalogue-list-item" with its name
    /// and link in an h3.sale-name, then .sale-date and .sale-location.
    static func catalogues(fromHTML html: String) -> [Catalogue] {
        var found: [Catalogue] = []
        for chunk in html.components(separatedBy: "catalogue-list-item").dropFirst() {
            guard let title = groups(#"<h3[^>]*sale-name[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, in: chunk),
                  let url = URL(string: title[0], relativeTo: site)?.absoluteURL else { continue }
            let name = plainText(title[1])
            let dates = groups(#"sale-date[^>]*>(.*?)</div>"#, in: chunk).map { plainText($0[0]) } ?? ""
            var location = ""
            if let start = chunk.range(of: "sale-location") {
                let rest = chunk[start.upperBound...]
                let end = rest.range(of: "sale-description")?.lowerBound ?? rest.endIndex
                var segment = String(rest[..<end])
                // Stop before the half-open tag that holds "sale-description".
                if end != rest.endIndex, let open = segment.range(of: "<", options: .backwards) {
                    segment = String(segment[..<open.lowerBound])
                }
                location = plainText(segment.replacingOccurrences(of: #"^[^>]*>"#, with: "", options: .regularExpression))
            }
            let cover = groups(#"<img[^>]*src="([^"]+)""#, in: chunk).flatMap { URL(string: $0[0], relativeTo: site)?.absoluteURL }
            guard !name.isEmpty, !found.contains(where: { $0.url == url }) else { continue }
            found.append(Catalogue(name: name, url: url, dates: dates, location: location, cover: cover, firstDay: firstDay(of: dates)))
        }
        if !found.isEmpty { return found }
        // Fallback if the page layout changes: any link to a sale page with text.
        let anchor = try! NSRegularExpression(pattern: #"<a[^>]*href="((?:https?://(?:www\.)?fasigtipton\.com)?/20\d\d/[A-Za-z0-9-]+)"[^>]*>([^<]+)</a>"#)
        for m in anchor.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r1 = Range(m.range(at: 1), in: html), let r2 = Range(m.range(at: 2), in: html),
                  let url = URL(string: String(html[r1]), relativeTo: site)?.absoluteURL else { continue }
            let name = plainText(String(html[r2]))
            if !name.isEmpty, !found.contains(where: { $0.url == url }) {
                found.append(Catalogue(name: name, url: url, dates: "", location: "", cover: nil, firstDay: nil))
            }
        }
        return found
    }

    /// "Oct 19 - 22, 2026" → Oct 19, 2026.
    static func firstDay(of dates: String) -> Date? {
        guard let g = groups(#"([A-Z][a-z]{2})\.? (\d{1,2})\D.*?(\d{4})"#, in: dates) else { return nil }
        return format("MMM d yyyy").date(from: "\(g[0]) \(g[1]) \(g[2])")
    }

    /// Text without tags, common entities decoded, spaces tidied.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&#039;", "'"), ("&#39;", "'"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
                               ("&quot;", "\""), ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"), ("&lt;", "<"), ("&gt;", ">")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The capture groups of the first match, or nil.
    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }

    /// This year's sales (and next year's once it's autumn), newest first, as on fasigtipton.com.
    static func catalogueList(now: Date = Date()) async throws -> [Catalogue] {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)
        var years = [year]
        if calendar.component(.month, from: now) >= 9 { years.insert(year + 1, at: 0) }
        var all: [Catalogue] = []
        var lastError: Error?
        for y in years {
            do {
                let html = String(decoding: try await get(site.appendingPathComponent("catalogues/\(y)"), json: false), as: UTF8.self)
                all += catalogues(fromHTML: html).filter { c in !all.contains { $0.url == c.url } }
            } catch {
                lastError = error
            }
        }
        if all.isEmpty, let lastError { throw lastError }
        return all.sorted { ($0.firstDay ?? .distantPast) > ($1.firstDay ?? .distantPast) }
    }

    // MARK: Fetching

    /// Everything found for one sale, before it's imported.
    struct Catalog {
        var code: String
        var name: String
        var day: Date?
        var horses: [Horse]
        /// Hips that came back in a shape we couldn't read.
        var unreadable: Int

        var videoCount: Int { horses.filter { $0.youtubeUrl?.isEmpty == false }.count }
        var photoCount: Int { horses.filter { !$0.photos.isEmpty }.count }
        var outCount: Int { horses.filter(\.out).count }
        var hipRange: ClosedRange<Int>? {
            guard let low = horses.map(\.hip).min(), let high = horses.map(\.hip).max() else { return nil }
            return low...high
        }
    }

    enum Problem: LocalizedError {
        case notALink, noSaleOnPage, unknownSale(String), noHips, offline, site(Int), unexpected
        var errorDescription: String? {
            switch self {
            case .notALink: "Paste the link to the sale’s catalogue page on fasigtipton.com (or its sale code, like M26B)."
            case .noSaleOnPage: "That page doesn’t show a sale catalogue. Open the sale’s catalogue page on fasigtipton.com and copy its link."
            case .unknownSale(let code): "Fasig-Tipton has no sale with the code \(code)."
            case .noHips: "Fasig-Tipton hasn’t posted any hips for this sale yet."
            case .offline: "Couldn’t reach fasigtipton.com. Check the internet connection and try again."
            case .site(let status): "fasigtipton.com didn’t answer as expected (error \(status)). Try again in a minute."
            case .unexpected: "fasigtipton.com sent its catalog in a form the app doesn’t recognise. Use Import spreadsheet instead, and tell the developer."
            }
        }
    }

    static func lookUp(_ text: String) async throws -> Catalog {
        guard let input = input(from: text) else { throw Problem.notALink }
        var info: PageInfo
        switch input {
        case .code(let code):
            info = PageInfo(code: code)
        case .page(let url):
            let html = String(decoding: try await get(url, json: false), as: UTF8.self)
            guard let found = pageInfo(fromHTML: html) else { throw Problem.noSaleOnPage }
            info = found
        }
        var sales = URLComponents(url: site.appendingPathComponent("django/api/sales/"), resolvingAgainstBaseURL: false)!
        sales.queryItems = [URLQueryItem(name: "sale_identifier", value: info.code)]
        let saleList = try decode([Lenient<SaleInfo>].self, from: try await get(sales.url!, json: true))
        guard let sale = saleList.compactMap(\.value).first(where: { $0.saleIdentifier.caseInsensitiveCompare(info.code) == .orderedSame })
                ?? saleList.compactMap(\.value).first else { throw Problem.unknownSale(info.code) }

        var horses = URLComponents(url: site.appendingPathComponent("django/api/horses/"), resolvingAgainstBaseURL: false)!
        horses.queryItems = [URLQueryItem(name: "sale", value: String(sale.id))]
        let list = try decode([Lenient<Horse>].self, from: try await get(horses.url!, json: true))
        let read = list.compactMap(\.value).sorted { $0.hip < $1.hip }
        guard !read.isEmpty else { throw Problem.noHips }
        return Catalog(code: sale.saleIdentifier, name: saleName(fromTitle: info.title, code: sale.saleIdentifier),
                       day: saleDay(apiDay: sale.saleStartDay, pageDate: info.startDate),
                       horses: read, unreadable: list.count - read.count)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) } catch { throw Problem.unexpected }
    }

    private static func get(_ url: URL, json: Bool) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(json ? "application/json" : "text/html", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw Problem.site(status) }
            return data
        } catch let problem as Problem {
            throw problem
        } catch {
            throw Problem.offline
        }
    }
}

extension FasigTipton.PageInfo {
    init(code: String) { self.init(code: code, title: nil, startDate: nil) }
}
