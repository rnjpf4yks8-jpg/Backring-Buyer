import Foundation

/// The 33 horses on the Equibase Virtual Stable list, so a new stable can be filled in one tap.
/// Ages are as of 2026; sire, dam and the rest fill in from each horse's first chart.
enum StableSeed {
    struct Seed {
        var id: String
        var name: String
        var sex: String
        var foalYear: Int
        var notes: String? = nil
        var equibase: String? = nil
    }

    static let horses: [Seed] = [
        Seed(id: "authentic-queen", name: "Authentic Queen", sex: "F", foalYear: 2023, equibase: "https://www.equibase.com/profiles/Results.cfm?type=Horse&refno=11292162&registry=T&rbt=TB"),
        Seed(id: "brand-liam", name: "Brand Liam", sex: "F", foalYear: 2024, equibase: "https://www.equibase.com/profiles/Results.cfm?type=Horse&refno=11448104&registry=T"),
        Seed(id: "cajun-coaster", name: "Cajun Coaster", sex: "G", foalYear: 2022, equibase: "https://www.equibase.com/profiles/Results.cfm?type=Horse&refno=11157011&registry=T"),
        Seed(id: "crescent-sky", name: "Crescent Sky", sex: "F", foalYear: 2023, equibase: "https://www.equibase.com/profiles/Results.cfm?type=Horse&refno=11301233&registry=T"),
        Seed(id: "divine-storm", name: "Divine Storm", sex: "F", foalYear: 2024, equibase: "https://www.equibase.com/profiles/Results.cfm?type=Horse&refno=11480875&registry=T"),
        Seed(id: "fastenurseatbelts", name: "Fastenurseatbelts", sex: "C", foalYear: 2024),
        Seed(id: "flebotomist", name: "Flebotomist", sex: "C", foalYear: 2024),
        Seed(id: "golden-corsair", name: "Golden Corsair", sex: "C", foalYear: 2024),
        Seed(id: "golden-holly", name: "Golden Holly", sex: "F", foalYear: 2023),
        Seed(id: "grand-mayhem", name: "Grand Mayhem", sex: "F", foalYear: 2024),
        Seed(id: "grey-strat", name: "Grey Strat", sex: "F", foalYear: 2024),
        Seed(id: "guidon", name: "Guidon", sex: "C", foalYear: 2023),
        Seed(id: "holy-grail", name: "Holy Grail", sex: "C", foalYear: 2024),
        Seed(id: "lunar-dynasty", name: "Lunar Dynasty", sex: "F", foalYear: 2024),
        Seed(id: "newyork-queen", name: "Newyork Queen", sex: "F", foalYear: 2024),
        Seed(id: "noble-vintage", name: "Noble Vintage", sex: "F", foalYear: 2024),
        Seed(id: "ohm-namo", name: "Ohm Namo", sex: "G", foalYear: 2023),
        Seed(id: "patriot-hall", name: "Patriot Hall", sex: "G", foalYear: 2024),
        Seed(id: "pride-of-heaven", name: "Pride of Heaven", sex: "F", foalYear: 2024),
        Seed(id: "proteas-song", name: "Proteas Song", sex: "C", foalYear: 2024),
        Seed(id: "redriver-storm", name: "Redriver Storm", sex: "F", foalYear: 2023),
        Seed(id: "remittance", name: "Remittance", sex: "G", foalYear: 2023),
        Seed(id: "ritzaphena", name: "Ritzaphena", sex: "F", foalYear: 2023),
        Seed(id: "sherkhan", name: "Sherkhan", sex: "G", foalYear: 2023),
        Seed(id: "shiva-parvati", name: "Shiva Parvati", sex: "F", foalYear: 2023),
        Seed(id: "sr-seventyone", name: "Sr Seventyone", sex: "F", foalYear: 2024),
        Seed(id: "sweet-saint", name: "Sweet Saint", sex: "F", foalYear: 2022),
        Seed(id: "told", name: "Told (IRE)", sex: "C", foalYear: 2023, notes: "Bred in Ireland.", equibase: "https://www.equibase.com/profiles/Results.cfm?type=Horse&refno=11348495&registry=T&rbt=TB"),
        Seed(id: "true-fire", name: "True Fire", sex: "F", foalYear: 2024),
        Seed(id: "turf-queen", name: "Turf Queen", sex: "F", foalYear: 2024),
        Seed(id: "vekowin", name: "Vekowin", sex: "R", foalYear: 2022),
        Seed(id: "voldemort", name: "Voldemort", sex: "G", foalYear: 2022),
        Seed(id: "weekendsandwhiskey", name: "Weekendsandwhiskey", sex: "R", foalYear: 2022),
    ]

    static func horse(_ s: Seed, now: String) -> Horse {
        var h = Horse(id: s.id, name: s.name)
        h.sex = s.sex
        h.foalYear = s.foalYear
        h.notes = s.notes
        h.equibaseUrl = s.equibase
        h.record = Record()
        h.source = "Equibase Virtual Stable list"
        h.createdAt = now
        h.updatedAt = now
        return h
    }
}
