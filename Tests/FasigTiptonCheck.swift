// Checks the Fasig-Tipton reader (HAINTEL/FasigTipton.swift) without the app or the network. On a Mac:
//   swiftc -parse-as-library HAINTEL/Models.swift HAINTEL/CatalogImport.swift HAINTEL/FasigTipton.swift Tests/FasigTiptonCheck.swift -o /tmp/ft && /tmp/ft
// GitHub Actions runs it on every push. The samples follow fasigtipton.com's /django/api/horses/ format.
import Foundation

var failures = 0
func check(_ condition: Bool, _ what: String, line: Int = #line) {
    if condition { print("ok   \(what)") } else { failures += 1; print("FAIL \(what) (line \(line))") }
}

let horsesJSON = #"""
[
 {"id":103114,"sale":319,"session":"2026-10-27","hip":1,"color":"B","name":"2025-RAVER","sex":"C","sire":"JACKIE'S WARRIOR",
  "dam":"RAVER","sire_of_dam":"TIZNOW","property_line":"GRACIE BLOODSTOCK, AGENT","purchaser":null,"price":null,
  "year_of_birth":"04/28/2025","foaled":"KY","barn":"I&J","consignor":"GRACIE BLOODSTOCK, AGENT","out":false,"youtube_url":null,
  "enhancedhorsephoto_set":[],"generalhorsephoto_set":[{"photo":"https://fasigtipton.blob.core.windows.net/public-media/194/89587/9923.jpg"}],
  "repository":{"hasXray":true}},
 {"id":103115,"sale":319,"session":"2026-10-27","hip":2,"color":"DK B/","name":"SCORPIO'S PRIDE","sex":"F","sire":"MANDALOUN",
  "dam":"SANDSARITA","sire_of_dam":"STREET BOSS","year_of_birth":"03/26/2025","foaled":"MD","barn":"C&D",
  "consignor":"MARSHALL W. SILVERMAN, AGENT","out":true,"youtube_url":"https://vimeo.com/1236413772",
  "enhancedhorsephoto_set":[],"generalhorsephoto_set":[]},
 {"id":103116,"sale":319,"session":"2026-10-27","hip":"3","color":"GR/RO","name":"2025-MCPEEK'S LADY","sex":"G","sire":"O'BRIEN II",
  "dam":"MCPEEK'S LADY","sire_of_dam":"I'M A CHATTERBOX","year_of_birth":"bad date","foaled":"","barn":"",
  "consignor":"HILL 'N' DALE FARMS LLC","out":false,"youtube_url":"https://youtu.be/abc123",
  "enhancedhorsephoto_set":[{"photo":"https://example.com/enhanced.jpg"}],"generalhorsephoto_set":[{"photo":"https://example.com/general.jpg"}]},
 {"id":103117,"sale":319,"hip":null,"name":"BROKEN ROW"},
 {"id":103118,"sale":319,"session":"2026-10-27","hip":4,"color":"CH","name":"2025-X","sex":"C","sire":"A","dam":"B","out":"not a bool","youtube_url":5}
]
"""#

let page = #"""
<html><head><title>Eastern Fall Yearlings (2026) | Fasig-Tipton</title>
<script type="application/json" data-drupal-selector="drupal-settings-json">{"path":{"baseUrl":"\/"},"catalogues":{"is_admin":false,"token":null,"sale_identifier":"M26B","title":"Eastern Fall Yearlings (2026)","sale_name":"Midlantic Fall Yearlings","sale_start_date":"10-27-2026","sale_end_date":""}}</script>
</head><body></body></html>
"""#

let cataloguesPage = #"""
<div class="view-content">
    <div class="row catalogue-list-item">
<div class="col-lg-2">
  <div class="sale-cover">
    <a href="/2026/The-November-Sale">
              <img src="/sites/default/files/styles/catalogue_cover_400x/public/2026-09/Nov.jpg?itok=abc" alt="">
          </a>
  </div>
</div>
<div class="col-lg-10">
  <div class="row">
    <div class="col-sm-12">
      <h3 class="sale-name">
        <a href="/2026/The-November-Sale">The November Sale</a>
      </h3>
    </div>
    <div class="col-sm-12 clearfix">
      <div class="sale-date">
                  Nov 02, 2026
              </div>
      <div class="sale-location">

            <div class="field field--name-dynamic-token-fieldnode-sale-location field--type-ds field--label-hidden field--item">Lexington, Kentucky
</div>

                </div>
    </div>
    <div class="col-sm-12">
      <div class="sale-description">
            <div class="field field--name-body"><p>The world&rsquo;s premier breeding stock event.</p></div>
      </div>
    </div>
  </div>
</div>
</div>
    <div class="row catalogue-list-item">
<div class="col-lg-2">
  <div class="sale-cover">
    <a href="/2026/Kentucky-October-Yearlings">
              <img src="/sites/default/files/styles/catalogue_cover_400x/public/2026-09/BLANK%20Cover.jpg?itok=x" alt="">
          </a>
  </div>
</div>
<div class="col-lg-10">
  <div class="row">
    <div class="col-sm-12">
      <h3 class="sale-name">
        <a href="/2026/Kentucky-October-Yearlings">Kentucky October Yearlings &amp; More</a>
      </h3>
    </div>
    <div class="col-sm-12 clearfix">
      <div class="sale-date">
                  Oct 19 - 22, 2026
              </div>
      <div class="sale-location">
            <div class="field field--item">Lexington, Kentucky
</div>
                </div>
    </div>
  </div>
</div>
</div>
</div>
"""#

@main
struct FasigTiptonCheck {
    static func main() throws {
        // What the administrator pastes
        check(FasigTipton.input(from: "https://www.fasigtipton.com/2026/Eastern-Fall-Yearlings#/") ==
              .page(URL(string: "https://www.fasigtipton.com/2026/Eastern-Fall-Yearlings")!), "page link, #/ dropped")
        check(FasigTipton.input(from: "Eastern Fall Yearlings (2026) | Fasig-Tipton https://www.fasigtipton.com/2026/Eastern-Fall-Yearlings#/?section=8338") ==
              .page(URL(string: "https://www.fasigtipton.com/2026/Eastern-Fall-Yearlings")!), "Safari share text with title in front")
        check(FasigTipton.input(from: "fasigtipton.com/2026/Eastern-Fall-Yearlings") ==
              .page(URL(string: "https://fasigtipton.com/2026/Eastern-Fall-Yearlings")!), "link without https")
        check(FasigTipton.input(from: " m26b ") == .code("M26B"), "sale code")
        check(FasigTipton.input(from: "https://keeneland.com/sales") == nil, "other sites refused")

        // The sale page
        let info = FasigTipton.pageInfo(fromHTML: page)
        check(info == FasigTipton.PageInfo(code: "M26B", title: "Eastern Fall Yearlings (2026)", startDate: "10-27-2026"), "page settings read")
        let fallback = FasigTipton.pageInfo(fromHTML: #"var x = {"catalogues":{"sale_identifier":"K26C","title":"October Yearlings (2026)"}}"#)
        check(fallback?.code == "K26C" && fallback?.title == "October Yearlings (2026)", "fallback when settings aren't in a script tag")
        check(FasigTipton.pageInfo(fromHTML: "<html>no sale</html>") == nil, "page without a sale")
        check(FasigTipton.saleName(fromTitle: "Eastern Fall Yearlings (2026)", code: "M26B") == "Eastern Fall Yearlings", "sale name without year")
        check(FasigTipton.saleName(fromTitle: nil, code: "M26B") == "Fasig-Tipton sale M26B", "sale name from code")

        // The list of sales
        let list = FasigTipton.catalogues(fromHTML: cataloguesPage)
        check(list.count == 2, "two sales listed")
        check(list.first?.name == "The November Sale" && list.first?.url.absoluteString == "https://www.fasigtipton.com/2026/The-November-Sale", "name and full link")
        check(list.first?.dates == "Nov 02, 2026" && list.first?.location == "Lexington, Kentucky", "date and place")
        check(list.first?.cover?.absoluteString.hasPrefix("https://www.fasigtipton.com/sites/default/files/") == true, "cover picture")
        check(list.first.flatMap(\.firstDay).map(Sale.dateText) == "Nov 2, 2026", "first day of a one-day sale")
        check(list[1].name == "Kentucky October Yearlings & More" && list[1].dates == "Oct 19 - 22, 2026", "entity decoded, date range kept")
        check(list[1].firstDay.map(Sale.dateText) == "Oct 19, 2026", "first day of a multi-day sale")
        let plain = FasigTipton.catalogues(fromHTML: #"<p><a href="https://www.fasigtipton.com/2027/The-July-Sale">The July Sale</a> <a href="/about-us">About</a></p>"#)
        check(plain.map(\.name) == ["The July Sale"], "fallback finds sale links only")
        check(FasigTipton.catalogues(fromHTML: "<html></html>").isEmpty, "no sales on an empty page")

        // Dates and catalog pages
        let day = FasigTipton.saleDay(apiDay: "2026-10-27", pageDate: nil)!
        check(Sale.dateText(day) == "Oct 27, 2026", "sale day from the data, as the app writes dates")
        check(Sale.dateText(FasigTipton.saleDay(apiDay: nil, pageDate: "10-27-2026")!) == "Oct 27, 2026", "sale day from the page")
        check(FasigTipton.catalogPage(hip: 2, saleDay: day).absoluteString == "https://www.fasigtipton.com/catalogs/2026/1027/2.pdf", "catalog page link")

        // The hips
        let list = try FasigTipton.decoder.decode([FasigTipton.Lenient<FasigTipton.Horse>].self, from: Data(horsesJSON.utf8))
        let horses = list.compactMap(\.value)
        check(list.count == 5 && horses.map(\.hip) == [1, 2, 3, 4], "4 hips read, the broken one skipped (hip \"3\" as text ok)")
        check(horses[3].out == false && horses[3].youtubeUrl == "5", "odd field types don't stop the sale")
        check(FasigTipton.row(horses[3], saleDay: day).walkVideoURL == nil, "a nonsense video link is ignored")

        let r1 = FasigTipton.row(horses[0], saleDay: day)
        check(r1.number == 1 && r1.name == "", "unnamed yearling (2025-RAVER) has no name")
        check(r1.sex == "colt" && r1.color == "Bay", "C → colt, B → Bay")
        check(r1.sire == "Jackie's Warrior" && r1.dam == "Raver" && r1.damSire == "Tiznow", "pedigree in title case")
        check(r1.foaled == "Apr 28, 2025 (KY)", "foaled date and state")
        check(r1.session == "Tue, Oct 27", "session day")
        check(r1.barn == "Barn I&J", "barn")
        check(r1.consignor == "Gracie Bloodstock, Agent", "consignor")
        check(r1.photoURL?.absoluteString == "https://fasigtipton.blob.core.windows.net/public-media/194/89587/9923.jpg", "photo")
        check(r1.walkVideoURL == nil && r1.isOut == false, "no video, not out")
        check(r1.pedigreeURL?.absoluteString == "https://www.fasigtipton.com/catalogs/2026/1027/1.pdf", "catalog page")

        let r2 = FasigTipton.row(horses[1], saleDay: day)
        check(r2.name == "Scorpio's Pride" && r2.sex == "filly" && r2.color == "Dark Bay/Brown", "named filly, DK B/ → Dark Bay/Brown")
        check(r2.walkVideoURL?.absoluteString == "https://vimeo.com/1236413772" && r2.photoURL == nil, "Vimeo walk video")
        check(r2.isOut == true, "out")
        check(r2.consignor == "Marshall W. Silverman, Agent", "middle initial")

        let r3 = FasigTipton.row(horses[2], saleDay: day)
        check(r3.color == "Gray/Roan" && r3.sex == "gelding", "GR/RO, G")
        check(r3.sire == "O'Brien II" && r3.dam == "McPeek's Lady" && r3.damSire == "I'm A Chatterbox", "O'Brien II, McPeek's, I'm")
        check(r3.consignor == "Hill 'n' Dale Farms LLC", "Hill 'n' Dale Farms LLC")
        check(r3.foaled == "bad date" && r3.barn == nil, "unreadable date kept as written, blank barn left alone")
        check(r3.photoURL?.absoluteString == "https://example.com/enhanced.jpg", "enhanced photo first")
        check(r3.walkVideoURL?.absoluteString == "https://youtu.be/abc123", "YouTube walk video")

        // Into the app
        var hip = Hip(number: 2)
        hip.vetReport.filed = "Oct 20, 2026"
        hip.conformationGrade = 7.5
        CatalogImport.apply(r2, to: &hip)
        check(hip.isOut == true && hip.walkVideoURL == r2.walkVideoURL, "applied: out and video")
        check(hip.vetReport.filed == "Oct 20, 2026" && hip.conformationGrade == 7.5, "staff entries kept")
        let fields = CatalogImport.fieldUpdates(r2)
        check(fields["isOut"] as? Bool == true && fields["pedigree.damSire"] as? String == "Street Boss", "Firestore updates include out")
        check(fields["photoURL"] == nil && fields["pedigree.sireSire"] == nil, "missing photo and grandsire not written")

        print(failures == 0 ? "\nAll Fasig-Tipton checks passed." : "\n\(failures) Fasig-Tipton check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
