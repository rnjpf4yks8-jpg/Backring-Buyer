// Checks the spreadsheet reader (HAINTEL/CatalogImport.swift) without the app. Run on a Mac:
//   swiftc HAINTEL/Models.swift HAINTEL/CatalogImport.swift Tests/CatalogImportCheck.swift -o /tmp/check && /tmp/check
// GitHub Actions runs it on every push.
import Foundation

var failures = 0
func check(_ condition: Bool, _ what: String, line: Int = #line) {
    if condition { print("ok   \(what)") } else { failures += 1; print("FAIL \(what) (line \(line))") }
}
func problem(_ text: String) -> String? {
    do { _ = try CatalogImport.parse(text); return nil } catch { return error.localizedDescription }
}

@main
struct CatalogImportCheck {
    static func main() throws {
        // 1. Our own template
        let t = try CatalogImport.parse(CatalogImport.template)
        check(t.rows.count == 2, "template: 2 hips")
        let first = t.rows[0]
        check(first.number == 412 && first.sex == "colt" && first.color == "Bay", "template: hip 412 colt bay")
        check(first.foaled == "Feb 14, 2025", "template: quoted date with comma")
        check(first.consignor == "Willow Ridge Sales, Agent", "template: quoted consignor with comma")
        check(first.damSire == "Coastal Prince" && first.damDam == "Marisol Bay", "template: pedigree")
        check(first.reserve == 350000, "template: reserve")
        check(first.conformationGrade == 8.0 && first.pedigreeGrade == 4.5, "template: grades")
        check(first.gradeNotes == "Big, balanced colt with a strong female family.", "template: notes")
        check(t.rows[1].reserve == nil && t.rows[1].conformationGrade == nil, "template: blanks leave reserve/grades alone")
        check(t.rows[1].name == "", "template: blank name clears it (like admin.js)")
        check(t.warnings.isEmpty && t.ignoredColumns.isEmpty, "template: no warnings, no ignored columns")

        // 2. A sale-company style export: other headings, Windows line endings, Excel numbers, abbreviations
        let export = "\u{FEFF}Hip No.,Horse Name,Sex,Colour,YOB,Sire,Dam,Broodmare Sire,Consignor,Reserve,Extra\r\n"
            + "101.0,Quiet Thunder,C,Dk B/Br,2025,Into Mischief,Lady X,Tapit,Lane's End,\"$120,000\",x\r\n"
            + "102,,F,Ch,2025,Gun Runner,Miss Y,Medaglia d'Oro,\"Taylor Made, Agent\",,y\r\n"
            + ",,,,,,,,,,\r\n"
            + "Hip 103,,G,Gr/Ro,2025,Curlin,Zed,Ghostzapper,Hill 'n' Dale,,z\r\n"
        let e = try CatalogImport.parse(export)
        check(e.rows.map(\.number) == [101, 102, 103], "export: hip numbers incl. 101.0 and 'Hip 103'")
        check(e.rows[0].name == "Quiet Thunder" && e.rows[0].sex == "colt" && e.rows[0].color == "Dark Bay/Brown", "export: name, C → colt, Dk B/Br")
        check(e.rows[1].sex == "filly" && e.rows[1].color == "Chestnut", "export: F → filly, Ch → Chestnut")
        check(e.rows[2].sex == "gelding" && e.rows[2].color == "Gray/Roan", "export: G → gelding, Gr/Ro")
        check(e.rows[0].damSire == "Tapit" && e.rows[0].foaled == "2025", "export: Broodmare Sire → damSire, YOB → foaled")
        check(e.rows[0].reserve == 120000, "export: $120,000 reserve")
        check(e.rows[1].consignor == "Taylor Made, Agent", "export: quoted consignor")
        check(e.rows[2].dam == "Zed" && e.rows[2].sire == "Curlin", "export: last row with CRLF")
        check(e.ignoredColumns == ["Extra"], "export: unknown column reported as ignored")
        let gap = try CatalogImport.parse("number,sire,dam\n1,A,B\n\n,C,D\n")
        check(gap.warnings.first?.contains("Row 4") == true, "row numbers count blank rows, like Excel")
        check(e.rows[0].sireSire == nil, "export: missing column stays nil (not wiped)")

        // 3. Semicolon-separated (European Excel) and tabs
        let semi = try CatalogImport.parse("hip;sire;dam;conformation_grade\n7;A;B;7,5\n8;C;D;11\n")
        check(semi.rows.count == 2 && semi.rows[0].conformationGrade == 7.5, "semicolons, 7,5 grade")
        check(semi.rows[1].conformationGrade == nil && semi.warnings.count == 1, "grade 11 refused with a warning")
        let tabs = try CatalogImport.parse("Hip\tSire\tDam\n9\tE\tF\n")
        check(tabs.rows.first?.number == 9 && tabs.rows.first?.dam == "F", "tab separated")

        // 4. Quotes and line breaks inside cells, repeated hips, rows without numbers
        let tricky = try CatalogImport.parse("number,sire,dam,grade_notes\n5,A,B,\"Says \"\"wow\"\"\nsecond line\"\n,X,Y,\n5,A2,B2,\n")
        check(tricky.rows.count == 1 && tricky.rows[0].sire == "A2", "repeated hip: last row wins")
        check(tricky.warnings.contains { $0.contains("no hip number") } && tricky.warnings.contains { $0.contains("rows 2 and 4") }, "warnings for blank number and repeat")
        let q = try CatalogImport.parse("number,sire,dam,grade_notes\n6,A,B,\"Says \"\"wow\"\"\nsecond line\"\n")
        check(q.rows[0].gradeNotes == "Says \"wow\"\nsecond line", "quotes and line break inside a cell")

        // 5. Problems
        check(problem("number,dam\n1,B\n")?.contains("sire") == true, "missing sire column")
        check(problem("sire,dam\nA,B\n")?.contains("hip number") == true, "missing hip number column")
        check(problem("number,sire,dam\n") != nil, "no hips")
        check(problem("PK\u{3}\u{4}\u{0}\u{0}binary") != nil, "binary file refused")

        // 6. Applying to hips
        var hip = Hip(number: 412)
        hip.gradeNotes = "staff note"
        hip.walkVideoLength = "0:42"
        CatalogImport.apply(t.rows[1].withNumber(412), to: &hip)
        check(hip.pedigree.sire == "Silver Tempo" && hip.sex == "filly", "apply: catalog fields copied")
        check(hip.gradeNotes == "staff note" && hip.walkVideoLength == "0:42", "apply: blank cells keep staff edits")
        let fresh = CatalogImport.newHip(e.rows[1])
        check(fresh.number == 102 && fresh.opinionsIn.isEmpty && fresh.vetReport == VetReport(), "newHip: defaults")
        let update = CatalogImport.fieldUpdates(e.rows[0])
        check(update["pedigree.damSire"] as? String == "Tapit" && update["reserve"] as? Int == 120000, "fieldUpdates: nested pedigree key and reserve")
        check(update["pedigree.sireSire"] == nil && update["conformationGrade"] == nil, "fieldUpdates: absent columns not written")

        print(failures == 0 ? "\nAll catalog checks passed." : "\n\(failures) catalog check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}

extension CatalogImport.Row {
    func withNumber(_ n: Int) -> Self { var r = self; r.number = n; return r }
}
