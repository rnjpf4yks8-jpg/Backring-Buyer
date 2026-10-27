// Checks the Fasig-Tipton catalog loader (HAINTEL/FasigTipton.swift) without the app. Run on a Mac:
//   swiftc -parse-as-library HAINTEL/Models.swift HAINTEL/CatalogImport.swift HAINTEL/FasigTipton.swift Tests/FasigTiptonCheck.swift -o /tmp/ft && /tmp/ft
// Add --live <sale page link> to read a real sale from fasigtipton.com. GitHub Actions runs the offline checks.
import Foundation

var failures = 0
func check(_ condition: Bool, _ what: String, line: Int = #line) {
    if condition { print("ok   \(what)") } else { failures += 1; print("FAIL \(what) (line \(line))") }
}

@main
struct FasigTiptonCheck {
    static func main() async throws {
        // 1. Finding the sale page and its code
        check(FasigTipton.guessPage(saleName: "Eastern Fall Yearlings", year: 2026)
              == "https://www.fasigtipton.com/2026/Eastern-Fall-Yearlings", "guess: Eastern Fall Yearlings 2026")
        check(FasigTipton.guessPage(saleName: "kentucky october yearlings", year: 2026)
              == "https://www.fasigtipton.com/2026/Kentucky-October-Yearlings", "guess: capitalizes words")
        let page = #"<script data-drupal-selector="drupal-settings-json">{"path":{},"catalogues":{"is_admin":false,"#
            + #""sale_identifier":"M26B","title":"Eastern Fall Yearlings (2026)","sale_name":"Midlantic Fall Yearlings"}}</script>"#
        check(FasigTipton.saleCode(inPage: page) == "M26B", "page: sale code")
        check(FasigTipton.title(inPage: page) == "Eastern Fall Yearlings (2026)", "page: catalogue title")
        check(FasigTipton.saleCode(inPage: "<html>No catalogue here</html>") == nil, "page: none on other pages")
        check(FasigTipton.looksLikeSaleCode("m26b") && !FasigTipton.looksLikeSaleCode("https://x"), "sale code typed in")

        // 2. Hips from the API (snake_case, as the site sends it)
        let json = #"""
        [{"id":103114,"sale":319,"hip":1,"color":"B","name":"2025-RAVER","sex":"C","sire":"JACKIE'S WARRIOR",
          "dam":"RAVER","sire_of_dam":"TIZNOW","property_line":"GRACIE BLOODSTOCK, AGENT","consignor":"GRACIE BLOODSTOCK, AGENT",
          "year_of_birth":"04/28/2025","foaled":"KY","barn":"I&J","out":false,"youtube_url":null,
          "generalhorsephoto_set":[{"photo":"https://fasigtipton.blob.core.windows.net/public-media/194/89587/a.jpg"}],
          "enhancedhorsephoto_set":[],"repository":{"hasXray":true}},
         {"hip":2,"color":"DK B/","name":"QUIET STORM","sex":"F","sire":"MANDALOUN","dam":"SANDSARITA","sire_of_dam":"STREET BOSS",
          "property_line":" ","consignor":"MARSHALL W. SILVERMAN, AGENT","year_of_birth":"03/26/2025","foaled":"MD","barn":"C&D",
          "out":false,"youtube_url":" https://vimeo.com/1236413772 ","generalhorsephoto_set":[],"enhancedhorsephoto_set":null},
         {"hip":3,"color":"GR/RO","name":"2025-ZED","sex":"G","sire":"A","dam":"B","sire_of_dam":"C","year_of_birth":null,
          "foaled":"PA","barn":null,"out":true,"youtube_url":null,"generalhorsephoto_set":[]}]
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let horses = try decoder.decode([FasigTipton.Horse].self, from: Data(json.utf8))
        let sale = FasigTipton.Sale(id: 319, saleIdentifier: "M26B", saleStartDay: "2026-10-27")
        let catalog = FasigTipton.Catalog(title: "Eastern Fall Yearlings (2026)", sale: sale, horses: horses)
        check(catalog.outs == [3], "outs found")
        let rows = catalog.rows(includingOuts: false)
        check(rows.map(\.number) == [1, 2], "outs left off by default")
        check(catalog.rows(includingOuts: true).count == 3, "outs included when asked")
        let one = rows[0]
        check(one.name == "", "unnamed yearling (2025-RAVER) has no name")
        check(one.sex == "colt" && one.color == "Bay", "C → colt, B → Bay")
        check(one.foaled == "Apr 28, 2025 (KY)", "foaled date and state")
        check(one.sire == "JACKIE'S WARRIOR" && one.dam == "RAVER" && one.damSire == "TIZNOW", "pedigree")
        check(one.consignor == "GRACIE BLOODSTOCK, AGENT" && one.barn == "I&J", "consignor and barn")
        check(one.pedigreeURL?.absoluteString == "https://www.fasigtipton.com/catalogs/2026/1027/1.pdf", "catalog page under the first sale day")
        check(one.photoURL?.absoluteString == "https://fasigtipton.blob.core.windows.net/public-media/194/89587/a.jpg", "sale photo")
        check(one.walkVideoURL == nil, "no video, none set")
        let two = rows[1]
        check(two.name == "QUIET STORM" && two.sex == "filly" && two.color == "Dark Bay/Brown", "named filly, DK B/ → Dark Bay/Brown")
        check(two.consignor == "MARSHALL W. SILVERMAN, AGENT", "consignor when the property line is blank")
        check(two.walkVideoURL?.absoluteString == "https://vimeo.com/1236413772", "walk video trimmed")
        check(two.photoURL == nil, "no photo, none set")
        let three = catalog.rows(includingOuts: true)[2]
        check(three.color == "Gray/Roan" && three.sex == "gelding" && three.foaled == "PA", "GR/RO, G, foaled place only")
        check(three.reserve == nil && three.conformationGrade == nil && three.gradeNotes == nil, "never touches reserve or grades")

        // 3. Optional: a real sale from fasigtipton.com
        if let i = CommandLine.arguments.firstIndex(of: "--live"), i + 1 < CommandLine.arguments.count {
            let live = try await FasigTipton.load(CommandLine.arguments[i + 1])
            let liveRows = live.rows(includingOuts: false)
            print("live: \(live.title), starts \(live.sale.saleStartDay), \(live.horses.count) hips, \(live.outs.count) outs")
            print("live: \(liveRows.filter { $0.photoURL != nil }.count) photos, \(liveRows.filter { $0.walkVideoURL != nil }.count) videos")
            if let first = liveRows.first { print("live first: \(first)") }
            check(!liveRows.isEmpty, "live: hips loaded")
        }

        print(failures == 0 ? "All Fasig-Tipton checks passed." : "\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
