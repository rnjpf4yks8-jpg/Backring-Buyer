import Foundation

// Firestore layout (see StablePPs/README.md):
//   stables/{uid}/horses/{horseId}                  Horse
//   stables/{uid}/horses/{horseId}/races/{lineId}   RaceLine
//   stables/{uid}/books/{bookId}                    ConditionBook
// Every field but the ids is optional, because a chart doesn't always say.

/// One of your horses. `record` and `lastRace` are kept current from its race lines,
/// so the horse list doesn't have to load every line.
struct Horse: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var sex: String?            // F filly, C colt, G gelding, R ridgling, M mare, H horse
    var foalYear: Int?
    var color: String?
    var stateBred: String?      // two-letter state where it was bred
    var sire: String?
    var dam: String?
    var damSire: String?
    var breeder: String?
    var trainer: String?
    var owner: String?
    var homeTrack: String?      // Equibase code; where an unraced horse is stabled
    var notes: String?
    var equibaseUrl: String?    // the horse's Equibase page
    var known: Known?           // lifetime record when not every start is in the app
    var record: Record?
    var lastRace: LastRace?
    var createdAt: String?
    var updatedAt: String?
    var source: String?

    struct Known: Codable, Hashable {
        var starts: Int?
        var wins: Int?
    }

    struct LastRace: Codable, Hashable {
        var date: String?
        var track: String?
        var race: Int?
        var distanceF: Double?
        var surface: String?
        var finish: Int?
        var classText: String?
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    var isFemale: Bool { sex == "F" || sex == "M" }
    var bredIn: String? { stateBred.flatMap { $0.isEmpty ? nil : $0 } }
}

/// Starts, wins, places, shows and money won.
struct Record: Codable, Hashable {
    var starts = 0
    var w = 0
    var p = 0
    var s = 0
    var earn: Double = 0
}

/// A point of call in a race: position and lengths ahead (or behind) as the chart prints them.
struct Call: Codable, Hashable {
    var label: String?
    var pos: Int?
    var lengths: String?
}

struct Finish: Codable, Hashable {
    var pos: Int?
    var lengths: String?
}

struct TopFinisher: Codable, Hashable {
    var name: String?
    var weight: Int?
    var lengths: String?
}

/// One past-performance line: the horse's run in one race, as read from the Equibase chart
/// or entered by hand.
struct RaceLine: Codable, Identifiable, Hashable {
    var id: String
    var date: String?           // YYYY-MM-DD
    var track: String?          // Equibase code
    var trackName: String?
    var race: Int?
    var surface: String?        // D dirt, T turf, A synthetic
    var distanceF: Double?      // furlongs
    var about: Bool?
    var condition: String?      // fst, gd, my, sly, wf, sys, fm, yl, sf, hy
    var fractions: [String]?
    var final: String?
    var ages: String?           // 2, 3, 2U, 3U, 4U
    var fillies: Bool?
    var stateBred: String?
    var type: String?           // MSW, MCL, CLM, STR, ALW, AOC, STK, HCP, OTHER
    var claimPrice: Double?
    var purse: Double?
    var classText: String?      // "Clm 16000N2L", "MdSpWt 60k"
    var stakesName: String?
    var grade: Int?
    var fieldSize: Int?
    var program: String?
    var postPosition: Int?
    var start: Int?
    var calls: [Call]?
    var finish: Finish?
    var jockey: String?
    var weight: Int?
    var medEq: String?
    var odds: Double?
    var favorite: Bool?
    var comment: String?
    var top3: [TopFinisher]?
    var earnings: Double?
    var claimed: String?
    var trainer: String?
    var owner: String?
    var conditions: String?
    var beyer: Int?
    var source: String?         // chart or hand
    var updatedAt: String?

    init(id: String) {
        self.id = id
    }

    var finishPos: Int? { finish?.pos }
    var won: Bool { finish?.pos == 1 }
    var money: Double { earnings ?? 0 }

    /// The document id for a line: date, track and race, so the same chart read twice replaces itself.
    static func key(date: String?, track: String?, race: Int?) -> String {
        let raw = "\(date ?? "")-\((track ?? "trk").uppercased())-\(race ?? 0)"
        return String(raw.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "-" })
    }
}

/// Who may run in a "non-winners" race.
struct NWCondition: Codable, Hashable {
    var kind: String            // lifetime, otherThan, since
    var n: Int?
    var since: String?
}

/// A starter allowance: must have started for this claiming price or less (since a date).
struct StarterCondition: Codable, Hashable {
    var claim: Double?
    var since: String?
}

/// One race printed in a track's condition book.
struct BookRace: Codable, Hashable {
    var date: String
    var raceNo: String?
    var type: String
    var name: String?
    var purse: Double?
    var claim: Double?
    var claimLow: Double?
    var ages: String?
    var sex: String?            // F fillies (and mares) only, O open
    var stateBred: String?
    var maiden: Bool?
    var nw: NWCondition?
    var starter: StarterCondition?
    var distanceF: Double?
    var distanceText: String?
    var surface: String?
    var sub: Bool?
    var text: String?
}

/// A condition book: every race a track's racing office plans for a stretch of dates.
struct ConditionBook: Codable, Identifiable, Hashable {
    var id: String
    var track: String
    var trackName: String?
    var title: String?
    var year: Int?
    var from: String?
    var to: String?
    var races: [BookRace]
    var loadedAt: String?
    var file: String?
}
