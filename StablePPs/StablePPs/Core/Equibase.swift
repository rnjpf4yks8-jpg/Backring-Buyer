import Foundation

/// Links that open Equibase in Safari, where you're signed in. The app never reads Equibase itself:
/// you copy or share a chart into it.
enum Equibase {
    static let home = URL(string: "https://www.equibase.com/")!

    static func isEquibase(_ link: String?) -> Bool {
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: link), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "equibase.com" || host == "www.equibase.com"
    }

    /// The horse's Equibase page if one is saved, else the Equibase home page.
    static func page(for horse: Horse) -> URL {
        if let link = horse.equibaseUrl, isEquibase(link),
           let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url
        }
        return home
    }

    /// Equibase's chart PDF for one race. Built from the pattern Equibase uses for chart links;
    /// if Equibase changes it, the horse's page still has every chart.
    static func chart(date: String?, track: String?, race: Int?) -> URL? {
        guard let date, let (y, m, d) = Dates.parts(date), let track, !track.isEmpty, let race, race > 0 else { return nil }
        let code = track.uppercased().filter { $0.isLetter }
        guard !code.isEmpty else { return nil }
        let country = Track.find(code)?.isCanadian == true ? "CAN" : "USA"
        let day = String(format: "%02d/%02d/%04d", m, d, y)
        return URL(string: "https://www.equibase.com/premium/eqbPDFChartPlus.cfm?RACE=\(race)&BorP=P&TID=\(code)&CTRY=\(country)&DT=\(day)&DAY=D&STYLE=EQB")
    }
}
