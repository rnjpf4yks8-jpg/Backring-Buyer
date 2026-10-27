import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLSession on Linux, for Tests/FasigTiptonCheck.swift
#endif

/// Loads a sale's catalog straight from fasigtipton.com, from the same public data its own online
/// catalogue page uses: every hip with its pedigree, consignor, barn, foaling date, sale photo, walk
/// video, and a link to its catalog page (PDF). The hips go through the same import as a spreadsheet.
///
/// Foundation only, so Tests/FasigTiptonCheck.swift can test it on its own.
enum FasigTipton {
    static let site = "https://www.fasigtipton.com"
    static let api = "https://www.fasigtipton.com/django/api"

    /// One sale as the Fasig-Tipton API lists it.
    struct Sale: Decodable, Equatable {
        var id: Int
        var saleIdentifier: String
        /// "2026-10-27"
        var saleStartDay: String
    }

    /// One hip as the Fasig-Tipton API lists it. Only what Backring Buyer uses.
    struct Horse: Decodable, Equatable {
        struct Photo: Decodable, Equatable { var photo: String? }

        var hip: Int
        var name: String?
        var sex: String?
        var color: String?
        var sire: String?
        var dam: String?
        var sireOfDam: String?
        var propertyLine: String?
        var consignor: String?
        /// "04/28/2025"
        var yearOfBirth: String?
        /// Where it was foaled, like "KY" or "MD".
        var foaled: String?
        var barn: String?
        /// Withdrawn from the sale.
        var out: Bool?
        /// The consignor's walk video (Vimeo or YouTube), despite the name.
        var youtubeUrl: String?
        var generalhorsephotoSet: [Photo]?
        var enhancedhorsephotoSet: [Photo]?
    }

    /// What was found for one sale.
    struct Catalog {
        /// "Eastern Fall Yearlings (2026)"
        var title: String
        var sale: Sale
        var horses: [Horse]

        var outs: [Int] { horses.filter { $0.out == true }.map(\.hip).sorted() }

        /// The hips to import, in catalog order. Outs are left off unless asked for.
        func rows(includingOuts: Bool) -> [CatalogImport.Row] {
            horses.filter { includingOuts || $0.out != true }
                .sorted { $0.hip < $1.hip }
                .map { FasigTipton.row($0, saleStartDay: sale.saleStartDay) }
        }
    }

    enum Problem: LocalizedError {
        case notASalePage, saleNotFound, noHips, offline(String)
        var errorDescription: String? {
            switch self {
            case .notASalePage:
                "That page doesn’t have a Fasig-Tipton catalogue. On fasigtipton.com, open the sale (its page shows the Catalogue tab), copy its link and paste it here."
            case .saleNotFound: "Fasig-Tipton didn’t find that sale. Check the link and try again."
            case .noHips: "Fasig-Tipton hasn’t posted any hips for this sale yet."
            case .offline(let detail): "Couldn’t reach fasigtipton.com (\(detail)). Check the connection and try again."
            }
        }
    }

    // MARK: Finding the sale

    /// The sale's page as Fasig-Tipton names it: "Eastern Fall Yearlings" in 2026 →
    /// https://www.fasigtipton.com/2026/Eastern-Fall-Yearlings
    static func guessPage(saleName: String, year: Int?) -> String {
        let words = saleName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let slug = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
        guard let year else { return "\(site)/\(slug)" }
        return "\(site)/\(year)/\(slug)"
    }

    /// The sale code on a Fasig-Tipton sale page, like "M26B" (it's in the page's settings).
    static func saleCode(inPage html: String) -> String? {
        firstMatch(#""sale_identifier"\s*:\s*"([A-Za-z0-9]+)""#, in: html)
    }

    /// The catalogue's title on the page, like "Eastern Fall Yearlings (2026)".
    static func title(inPage html: String) -> String? {
        firstMatch(#""catalogues"\s*:\s*\{.*?"title"\s*:\s*"([^"]+)""#, in: html)
    }

    /// A pasted sale code ("M26B") instead of a link.
    static func looksLikeSaleCode(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z]\d{2}[A-Za-z]$"#, options: .regularExpression) != nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: Turning a hip into a catalog row

    /// The hip's catalog page: Fasig-Tipton files them under the sale's first day, e.g.
    /// https://www.fasigtipton.com/catalogs/2026/1027/12.pdf for a sale starting Oct 27, 2026.
    static func catalogPage(hip: Int, saleStartDay: String) -> URL? {
        let parts = saleStartDay.split(separator: "-")
        guard parts.count == 3 else { return nil }
        return URL(string: "\(site)/catalogs/\(parts[0])/\(parts[1])\(parts[2])/\(hip).pdf")
    }

    static func row(_ horse: Horse, saleStartDay: String) -> CatalogImport.Row {
        var row = CatalogImport.Row(number: horse.hip)
        // Unnamed yearlings are listed as "2025-RAVER" (year and dam).
        let name = clean(horse.name)
        row.name = name.range(of: #"^\d{4}-"#, options: .regularExpression) == nil ? name : ""
        if let sex = horse.sex, !clean(sex).isEmpty { row.sex = CatalogImport.sexWord(clean(sex)) }
        row.color = colorWord(clean(horse.color))
        row.foaled = foaledText(birth: horse.yearOfBirth, place: horse.foaled)
        row.barn = clean(horse.barn)
        row.consignor = clean(horse.propertyLine).isEmpty ? clean(horse.consignor) : clean(horse.propertyLine)
        row.sire = clean(horse.sire)
        row.dam = clean(horse.dam)
        row.damSire = clean(horse.sireOfDam)
        row.pedigreeURL = catalogPage(hip: horse.hip, saleStartDay: saleStartDay)
        let photos = (horse.generalhorsephotoSet ?? []) + (horse.enhancedhorsephotoSet ?? [])
        row.photoURL = photos.lazy.compactMap { $0.photo.flatMap(webURL) }.first
        row.walkVideoURL = horse.youtubeUrl.flatMap(webURL)
        return row
    }

    /// "04/28/2025" and "KY" → "Apr 28, 2025 (KY)".
    static func foaledText(birth: String?, place: String?) -> String {
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.dateFormat = "MM/dd/yyyy"
        let writer = DateFormatter()
        writer.locale = Locale(identifier: "en_US_POSIX")
        writer.dateFormat = "MMM d, yyyy"
        let state = clean(place)
        let day = clean(birth)
        let date = reader.date(from: day).map(writer.string(from:)) ?? day
        if date.isEmpty { return state }
        return state.isEmpty ? date : "\(date) (\(state))"
    }

    /// Fasig-Tipton's colors ("B", "CH", "DK B/", "GR/RO") as the words the app shows.
    static func colorWord(_ text: String) -> String {
        switch CatalogImport.normalize(text) {
        case "dkb", "dkbbr", "dkbr": "Dark Bay/Brown"
        default: CatalogImport.colorWord(text)
        }
    }

    private static func clean(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func webURL(_ text: String) -> URL? {
        let trimmed = clean(text)
        guard !trimmed.isEmpty else { return nil }
        return CatalogImport.webLink(trimmed)
    }

    // MARK: Loading

    /// Reads the sale from a link to its page on fasigtipton.com (or its sale code, like "M26B"),
    /// then its hips.
    static func load(_ pageOrCode: String) async throws -> Catalog {
        let input = pageOrCode.trimmingCharacters(in: .whitespacesAndNewlines)
        var code = looksLikeSaleCode(input) ? input.uppercased() : nil
        var title: String?
        if code == nil {
            let link = input.lowercased().hasPrefix("http") ? input : "https://\(input)"
            guard let url = URL(string: link), url.host?.contains("fasigtipton") == true else {
                throw Problem.notASalePage
            }
            let page = try await get(url)
            let html = String(decoding: page, as: UTF8.self)
            code = saleCode(inPage: html)
            title = self.title(inPage: html)
        }
        guard let code else { throw Problem.notASalePage }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let saleQuery = URL(string: "\(api)/sales/?sale_identifier=\(code)") else { throw Problem.notASalePage }
        let saleData = try await get(saleQuery)
        guard let sale = try decoder.decode([Sale].self, from: saleData).first else { throw Problem.saleNotFound }
        guard let horseQuery = URL(string: "\(api)/horses/?sale=\(sale.id)") else { throw Problem.saleNotFound }
        let horseData = try await get(horseQuery)
        let horses = try decoder.decode([Horse].self, from: horseData)
        guard !horses.isEmpty else { throw Problem.noHips }
        return Catalog(title: title ?? "Fasig-Tipton sale \(code)", sale: sale, horses: horses)
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Problem.offline(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw Problem.saleNotFound }
        guard (200..<300).contains(status) else { throw Problem.offline("error \(status)") }
        return data
    }
}
