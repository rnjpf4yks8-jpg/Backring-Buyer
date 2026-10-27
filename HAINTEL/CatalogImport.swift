import Foundation

/// Reads a sale catalog spreadsheet saved as CSV (or tab/semicolon separated) into hips.
/// Does in the app what `node admin.js import-hips` does. Column names are matched loosely, so both
/// our template (firebase/hips-template.csv) and typical sale-company exports work:
/// "number" or "Hip" or "Hip No", "damSire" or "Dam Sire" or "Broodmare Sire", and so on.
///
/// Foundation only, so Tests/CatalogImportCheck.swift can test it on its own.
struct CatalogImport {
    /// One hip from the spreadsheet. A nil field means the column wasn't there (or the cell was blank
    /// where blank means "leave it"), so importing never wipes what staff entered in the app.
    struct Row: Equatable {
        var number: Int
        var name: String?
        var sex: String?
        var color: String?
        var foaled: String?
        var session: String?
        var barn: String?
        var consignor: String?
        var sire: String?
        var sireSire: String?
        var sireDam: String?
        var dam: String?
        var damSire: String?
        var damDam: String?
        var reserve: Int?
        var pedigreeURL: URL?
        var walkVideoURL: URL?
        var photoURL: URL?
        var walkVideoLength: String?
        var conformationGrade: Double?
        var pedigreeGrade: Double?
        var gradeNotes: String?
        /// Scratched from the sale.
        var isOut: Bool?
    }

    var rows: [Row]
    /// Things worth telling staff: skipped rows, grades that didn't fit, repeated hip numbers.
    var warnings: [String]
    /// Columns we didn't recognise (ignored).
    var ignoredColumns: [String]

    enum Problem: LocalizedError {
        case unreadable, empty, missingColumn(String)
        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn’t read that file. In Excel or Numbers, save or export the spreadsheet as CSV and pick that file."
            case .empty: "That spreadsheet has no hips in it."
            case .missingColumn(let name): "The spreadsheet needs a \(name) column. Get the template to see the column names."
            }
        }
    }

    // MARK: Columns

    /// Our field name for each accepted column heading, compared in lowercase without spaces or punctuation.
    private static let aliases: [String: [String]] = [
        "number": ["number", "hip", "hipno", "hipnumber", "hipnum", "hipnbr"],
        "name": ["name", "horsename", "horse"],
        "sex": ["sex", "gender"],
        "color": ["color", "colour"],
        "foaled": ["foaled", "foalingdate", "foaldate", "dob", "dateofbirth", "birthdate", "yob", "yearofbirth", "year"],
        "session": ["session", "day"],
        "barn": ["barn", "barnno", "barnnumber", "location"],
        "consignor": ["consignor", "consigner"],
        "sire": ["sire"],
        "sireSire": ["siresire", "sireofsire", "paternalgrandsire"],
        "sireDam": ["siredam", "damofsire", "paternalgranddam"],
        "dam": ["dam", "mare"],
        "damSire": ["damsire", "broodmaresire", "bms", "sireofdam", "maternalgrandsire"],
        "damDam": ["damdam", "damofdam", "maternalgranddam", "seconddam", "2nddam"],
        "reserve": ["reserve", "reserveprice"],
        "pedigreeURL": ["pedigreeurl", "catalogurl", "catalogpage", "pedigreelink", "cataloglink", "pedigreepage"],
        "walkVideoURL": ["walkvideourl", "walkvideo", "videourl", "video", "videolink"],
        "photoURL": ["photourl", "photo", "picture", "pictureurl", "image", "imageurl", "photolink"],
        "walkVideoLength": ["walkvideolength", "videolength", "videoduration"],
        "conformationGrade": ["conformationgrade", "conformation", "cgrade"],
        "pedigreeGrade": ["pedigreegrade", "pgrade"],
        "gradeNotes": ["gradenotes", "notes", "comments", "why"],
        "isOut": ["out", "isout", "scratched", "withdrawn"],
    ]

    static func normalize(_ heading: String) -> String {
        heading.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }

    // MARK: Reading

    static func read(_ data: Data) throws -> CatalogImport {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1) else { throw Problem.unreadable }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> CatalogImport {
        // A binary file (like an .xlsx picked by mistake) isn't a table at all.
        if text.contains("\u{0}") { throw Problem.unreadable }
        let table = cells(of: text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        func isBlank(_ cells: [String]) -> Bool { cells.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let headerIndex = table.firstIndex(where: { !isBlank($0) }) else { throw Problem.empty }

        let header = table[headerIndex]
        var columnOf: [String: Int] = [:]
        var ignored: [String] = []
        for (i, heading) in header.enumerated() {
            let key = normalize(heading)
            if let field = aliases.first(where: { $0.value.contains(key) })?.key, columnOf[field] == nil {
                columnOf[field] = i
            } else if !key.isEmpty {
                ignored.append(heading.trimmingCharacters(in: .whitespaces))
            }
        }
        for required in [("number", "hip number"), ("sire", "sire"), ("dam", "dam")] where columnOf[required.0] == nil {
            throw Problem.missingColumn(required.1)
        }

        var warnings: [String] = []
        var rows: [Row] = []
        var seen: [Int: Int] = [:]
        for (index, cells) in table.enumerated() where index > headerIndex && !isBlank(cells) {
            let line = index + 1  // the row number the spreadsheet app shows
            func cell(_ field: String) -> String? {
                guard let i = columnOf[field] else { return nil }
                return i < cells.count ? cells[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
            /// Text columns: present means set it (blank clears it), like admin.js.
            func text(_ field: String) -> String? { cell(field) }
            /// Optional columns where blank means "leave as it is".
            func filled(_ field: String) -> String? { cell(field).flatMap { $0.isEmpty ? nil : $0 } }

            guard let number = hipNumber(cell("number") ?? "") else {
                warnings.append("Row \(line): no hip number, skipped.")
                continue
            }
            var row = Row(number: number)
            row.name = text("name")
            row.sex = filled("sex").map(sexWord)
            row.color = text("color").map(colorWord)
            row.foaled = text("foaled")
            row.session = text("session")
            row.barn = text("barn")
            row.consignor = text("consignor")
            row.sire = text("sire")
            row.sireSire = text("sireSire")
            row.sireDam = text("sireDam")
            row.dam = text("dam")
            row.damSire = text("damSire")
            row.damDam = text("damDam")
            row.reserve = filled("reserve").flatMap(dollars)
            row.pedigreeURL = filled("pedigreeURL").flatMap(webLink)
            row.walkVideoURL = filled("walkVideoURL").flatMap(webLink)
            row.photoURL = filled("photoURL").flatMap(webLink)
            row.walkVideoLength = filled("walkVideoLength")
            row.gradeNotes = filled("gradeNotes")
            row.isOut = filled("isOut").map { ["y", "yes", "x", "true", "out", "1"].contains($0.lowercased()) }
            for (field, max, label) in [("conformationGrade", 10.0, "conformation"), ("pedigreeGrade", 5.0, "pedigree")] {
                guard let value = filled(field) else { continue }
                if let grade = halfPointGrade(value, max: max) {
                    if field == "conformationGrade" { row.conformationGrade = grade } else { row.pedigreeGrade = grade }
                } else {
                    warnings.append("Hip \(number): \(label) grade “\(value)” isn’t 1 to \(Int(max)) in half points, left as it was.")
                }
            }
            if let earlier = seen[number] {
                warnings.append("Hip \(number) is on rows \(earlier) and \(line); row \(line) is used.")
                rows.removeAll { $0.number == number }
            }
            seen[number] = line
            rows.append(row)
        }
        guard !rows.isEmpty else { throw Problem.empty }
        return CatalogImport(rows: rows, warnings: warnings, ignoredColumns: ignored)
    }

    /// Splits CSV text into rows of cells: quoted cells may hold commas, quotes ("") and line breaks.
    /// The separator is a comma, or a semicolon or tab when the heading row uses those instead.
    static func cells(of text: String) -> [[String]] {
        let firstLine = text.prefix { !$0.isNewline }
        let separator: Character = [";", "\t"].first { s in
            firstLine.filter { $0 == s }.count > firstLine.filter { $0 == "," }.count
        } ?? ","
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var chars = Array(text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { cell.append("\""); i += 1 } else { quoted = false }
                } else {
                    cell.append(c)
                }
            } else if c == "\"" && cell.trimmingCharacters(in: .whitespaces).isEmpty {
                cell = ""
                quoted = true
            } else if c == separator {
                row.append(cell); cell = ""
            } else if c.isNewline {
                // Swift reads Windows line endings ("\r\n") as one character.
                row.append(cell); cell = ""
                rows.append(row); row = []
            } else {
                cell.append(c)
            }
            i += 1
        }
        if let last = rows.last, last == [""] { rows.removeLast() }
        return rows
    }

    // MARK: Cleaning up values

    /// "412", "412.0" (Excel), "Hip 412" or "412A"-style supplements as 412.
    static func hipNumber(_ text: String) -> Int? {
        if let value = Double(text), value >= 1, value == value.rounded() { return Int(value) }
        let digits = text.drop { !$0.isNumber }.prefix { $0.isNumber }
        guard let n = Int(digits), n >= 1 else { return nil }
        return n
    }

    static func dollars(_ text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return Int(value.rounded())
    }

    static func halfPointGrade(_ text: String, max: Double) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value >= 1, value <= max, (value * 2).rounded() == value * 2 else { return nil }
        return value
    }

    static func webLink(_ text: String) -> URL? {
        let link = text.lowercased().hasPrefix("http") ? text : "https://\(text)"
        guard let url = URL(string: link), url.host?.contains(".") == true else { return nil }
        return url
    }

    /// Catalog abbreviations as the words the app uses: C → colt, F → filly.
    static func sexWord(_ text: String) -> String {
        switch text.lowercased() {
        case "c", "colt", "r", "rig", "ridgling": "colt"
        case "f", "filly": "filly"
        case "g", "gelding": "gelding"
        case "h", "horse", "stallion": "horse"
        case "m", "mare": "mare"
        default: text.lowercased()
        }
    }

    /// B → Bay, Ch → Chestnut, Dk B/Br → Dark Bay/Brown. Anything else is kept as written.
    static func colorWord(_ text: String) -> String {
        switch normalize(text) {
        case "b": "Bay"
        case "ch", "chs", "chestnut": "Chestnut"
        case "dkb", "dkbbr", "dkbor", "dkbbro", "dkbayorbr", "darkbayorbrown", "darkbaybrown": "Dark Bay/Brown"
        case "br", "bro", "brown": "Brown"
        case "blk", "bl", "black": "Black"
        case "gr", "gray", "grey": "Gray"
        case "ro", "roan": "Roan"
        case "grro", "grayroan", "greyroan", "grorro": "Gray/Roan"
        case "wh", "white": "White"
        case "pal", "palomino": "Palomino"
        default: text
        }
    }

    // MARK: Applying

    /// A brand-new hip from a row. Blank fields get the same defaults as `admin.js import-hips`.
    static func newHip(_ row: Row) -> Hip {
        var hip = Hip(number: row.number)
        hip.color = ""
        apply(row, to: &hip)
        return hip
    }

    /// Copies the spreadsheet's fields onto a hip, leaving everything staff entered in the app alone.
    static func apply(_ row: Row, to hip: inout Hip) {
        if let v = row.name { hip.name = v }
        if let v = row.sex { hip.sex = v }
        if let v = row.color { hip.color = v }
        if let v = row.foaled { hip.foaled = v }
        if let v = row.session { hip.session = v }
        if let v = row.barn { hip.barn = v }
        if let v = row.consignor { hip.consignor = v }
        if let v = row.sire { hip.pedigree.sire = v }
        if let v = row.sireSire { hip.pedigree.sireSire = v }
        if let v = row.sireDam { hip.pedigree.sireDam = v }
        if let v = row.dam { hip.pedigree.dam = v }
        if let v = row.damSire { hip.pedigree.damSire = v }
        if let v = row.damDam { hip.pedigree.damDam = v }
        if let v = row.reserve { hip.reserve = v }
        if let v = row.pedigreeURL { hip.pedigreeURL = v }
        if let v = row.walkVideoURL { hip.walkVideoURL = v }
        if let v = row.photoURL { hip.photoURL = v }
        if let v = row.walkVideoLength { hip.walkVideoLength = v }
        if let v = row.conformationGrade { hip.conformationGrade = v }
        if let v = row.pedigreeGrade { hip.pedigreeGrade = v }
        if let v = row.gradeNotes { hip.gradeNotes = v }
        if let v = row.isOut { hip.isOut = v }
    }

    /// The same changes as Firestore field updates, for a hip that's already saved: only the
    /// spreadsheet's own fields are written, so opinions and staff edits made meanwhile are kept.
    static func fieldUpdates(_ row: Row) -> [String: Any] {
        var update: [String: Any] = [:]
        let pairs: [(String, Any?)] = [
            ("name", row.name), ("sex", row.sex), ("color", row.color), ("foaled", row.foaled),
            ("session", row.session), ("barn", row.barn), ("consignor", row.consignor),
            ("pedigree.sire", row.sire), ("pedigree.sireSire", row.sireSire), ("pedigree.sireDam", row.sireDam),
            ("pedigree.dam", row.dam), ("pedigree.damSire", row.damSire), ("pedigree.damDam", row.damDam),
            ("reserve", row.reserve), ("pedigreeURL", row.pedigreeURL?.absoluteString),
            ("walkVideoURL", row.walkVideoURL?.absoluteString), ("photoURL", row.photoURL?.absoluteString),
            ("walkVideoLength", row.walkVideoLength), ("conformationGrade", row.conformationGrade),
            ("pedigreeGrade", row.pedigreeGrade), ("gradeNotes", row.gradeNotes), ("isOut", row.isOut),
        ]
        for (key, value) in pairs { if let value { update[key] = value } }
        return update
    }

    /// Our template, for staff to fill in (the same columns as firebase/hips-template.csv).
    static let template = """
    number,name,sex,color,foaled,session,barn,consignor,sire,sireSire,sireDam,dam,damSire,damDam,reserve,conformation_grade,pedigree_grade,grade_notes
    412,,colt,Bay,"Feb 14, 2025",Session 1,Barn 23,"Willow Ridge Sales, Agent",Northern Ledger,Granite Crown,Ledger Line,Lady Marisol,Coastal Prince,Marisol Bay,350000,8.0,4.5,"Big, balanced colt with a strong female family."
    413,,filly,Chestnut,"Mar 3, 2025",Session 1,Barn 23,"Willow Ridge Sales, Agent",Silver Tempo,Tempo Rubato,Quicksilver Lane,Arden Rose,Highland Reel,Rosewater,,,,

    """
}
