import Foundation

// Demo data used until Firebase is set up. Every name and number here is made up.
enum SampleData {
    static let sale = Sale(
        id: "demo-yearling-sale",
        name: "October Yearling Sale",
        company: "Fasig-Tipton",
        date: "Oct 27, 2026",
        panel: [
            "vet1": PanelMember(uid: "demo-vet1", name: "Dr. A. Reyes", org: "Bluegrass Equine"),
            "vet2": PanelMember(uid: "demo-vet2", name: "Dr. K. Malone", org: "Hagyard Partners"),
            "bs1": PanelMember(uid: "demo-bs1", name: "J. Whitaker", org: "Whitaker Bloodstock"),
            "bs2": PanelMember(uid: "demo-bs2", name: "M. Castellano", org: "Castellano Thoroughbreds"),
        ]
    )

    /// People you can switch between in demo mode.
    static let people: [AppUser] = [
        AppUser(uid: "demo-buyer", name: "Demo buyer", role: .buyer),
        AppUser(uid: "demo-staff", name: "T. Nguyen", role: .staff),
        AppUser(uid: "demo-vet1", name: "Dr. A. Reyes", role: .vet),
        AppUser(uid: "demo-vet2", name: "Dr. K. Malone", role: .vet),
        AppUser(uid: "demo-bs1", name: "J. Whitaker", role: .agent),
        AppUser(uid: "demo-bs2", name: "M. Castellano", role: .agent),
    ]

    private static let sampleVideo = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8")

    static let hips: [Hip] = [
        Hip(
            number: 412, name: "", sex: "colt", color: "Bay", foaled: "Feb 14, 2025",
            session: "Session 1", barn: "Barn 23", consignor: "Willow Ridge Sales, Agent",
            pedigree: Pedigree(sire: "Northern Ledger", sireSire: "Granite Crown", sireDam: "Ledger Line",
                               dam: "Lady Marisol", damSire: "Coastal Prince", damDam: "Marisol Bay"),
            vetReport: VetReport(radiographs: .clean, radiographNotes: "36 views on file. No significant findings.",
                                 scope: .clean, scopeNotes: "Grade 1 arytenoid function. Full abduction.",
                                 filed: "Sep 2, 2026"),
            reserve: 350_000,
            auctionHistory: [
                AuctionRecord(sale: "November Breeding Stock", date: "Nov 2025", hip: 1088, result: "Sold as foal, $185,000")
            ],
            walkVideoURL: sampleVideo, walkVideoLength: "0:42", photoURL: nil, physical: HorsePhysical(heightInches: 61.5, lengthInches: 63, measuredBy: "T. Nguyen", date: "Sep 6, 2026"),
            opinionsIn: OpinionSlot.allCases
        ),
        Hip(
            number: 413, name: "", sex: "filly", color: "Chestnut", foaled: "Mar 3, 2025",
            session: "Session 1", barn: "Barn 23", consignor: "Willow Ridge Sales, Agent",
            pedigree: Pedigree(sire: "Silver Tempo", sireSire: "Tempo Rubato", sireDam: "Quicksilver Lane",
                               dam: "Arden Rose", damSire: "Highland Reel", damDam: "Rosewater"),
            vetReport: VetReport(radiographs: .minor, radiographNotes: "Mild sesamoiditis right fore.",
                                 scope: .clean, scopeNotes: "Grade 1.", filed: "Sep 2, 2026"),
            reserve: 175_000,
            auctionHistory: [],
            walkVideoURL: sampleVideo, walkVideoLength: "0:38", photoURL: nil, physical: HorsePhysical(heightInches: 60, lengthInches: 61, measuredBy: "T. Nguyen", date: "Sep 6, 2026"),
            opinionsIn: OpinionSlot.allCases
        ),
        Hip(
            number: 415, name: "Harbor Lights", sex: "colt", color: "Dark bay", foaled: "Jan 29, 2025",
            session: "Session 1", barn: "Barn 24", consignor: "Stonegate Farm",
            pedigree: Pedigree(sire: "Granite Crown", sireSire: "Iron Sovereign", sireDam: "Crowning Glory",
                               dam: "Port of Call", damSire: "Seafarer", damDam: "Harbor Mist"),
            vetReport: VetReport(radiographs: .concern, radiographNotes: "Fragment noted right front ankle.",
                                 scope: .minor, scopeNotes: "Grade 2 left arytenoid.", filed: "Sep 3, 2026"),
            reserve: 400_000,
            auctionHistory: [
                AuctionRecord(sale: "November Breeding Stock", date: "Nov 2025", hip: 942, result: "RNA at $90,000")
            ],
            walkVideoURL: nil, walkVideoLength: "", photoURL: nil, physical: HorsePhysical(heightInches: 62.5, lengthInches: 65, measuredBy: "R. Okafor", date: "Sep 7, 2026"),
            opinionsIn: OpinionSlot.allCases
        ),
        Hip(
            number: 418, name: "", sex: "filly", color: "Gray", foaled: "Apr 11, 2025",
            session: "Session 1", barn: "Barn 24", consignor: "Stonegate Farm",
            pedigree: Pedigree(sire: "Northern Ledger", sireSire: "Granite Crown", sireDam: "Ledger Line",
                               dam: "Misty Overture", damSire: "Silver Tempo", damDam: "Overture"),
            vetReport: VetReport(radiographs: .clean, radiographNotes: "No significant findings.",
                                 scope: .clean, scopeNotes: "Grade 1.", filed: "Sep 3, 2026"),
            reserve: nil,
            auctionHistory: [],
            walkVideoURL: sampleVideo, walkVideoLength: "0:35", photoURL: nil, physical: nil,
            opinionsIn: OpinionSlot.allCases
        ),
        Hip(
            number: 421, name: "", sex: "colt", color: "Chestnut", foaled: "Feb 2, 2025",
            session: "Session 1", barn: "Barn 25", consignor: "Cedar Hollow",
            pedigree: Pedigree(sire: "Tempo Rubato", sireSire: "Allegro Run", sireDam: "Rubato",
                               dam: "Kindred Spirit", damSire: "Iron Sovereign", damDam: "Kinfolk"),
            vetReport: VetReport(radiographs: .clean, radiographNotes: "No significant findings.",
                                 scope: .minor, scopeNotes: "Grade 2, full abduction on swallow.", filed: "Sep 4, 2026"),
            reserve: 250_000,
            auctionHistory: [
                AuctionRecord(sale: "Winter Mixed Sale", date: "Jan 2026", hip: 77, result: "Outs (scratched)")
            ],
            walkVideoURL: sampleVideo, walkVideoLength: "0:44", photoURL: nil, physical: HorsePhysical(heightInches: 61, lengthInches: 64, measuredBy: "R. Okafor", date: "Sep 7, 2026"),
            opinionsIn: OpinionSlot.allCases
        ),
    ]

    static let opinions: [String: Opinion] = [
        "412_vet1": Opinion(notes: "Clean films, good throat. No reason to pass.", date: "Sep 8, 2026", basis: .repository, grade: .clean),
        "412_vet2": Opinion(notes: "Small OCD lesion left hind fetlock. Low risk for racing.", date: "Sep 8, 2026", basis: .physicalExam, grade: .minor),
        "412_bs1": Opinion(notes: "Big, balanced colt. Walks with purpose. Top of our list for the session.", date: "Oct 24, 2026", rank: 4, outOf: 186, score: 9.1),
        "412_bs2": Opinion(notes: "Strong page. Slightly back at the knee.", date: "Oct 24, 2026", rank: 11, outOf: 186, score: 8.4),
        "413_vet1": Opinion(notes: "Sesamoid changes are common and mild here.", date: "Sep 8, 2026", basis: .repository, grade: .minor),
        "413_vet2": Opinion(notes: "Agree with repository. Acceptable.", date: "Sep 8, 2026", basis: .physicalExam, grade: .minor),
        "413_bs1": Opinion(notes: "Light-framed but athletic.", date: "Oct 24, 2026", rank: 22, outOf: 186, score: 7.8),
        "413_bs2": Opinion(notes: "Lovely mover.", date: "Oct 24, 2026", rank: 17, outOf: 186, score: 8.0),
        "415_vet1": Opinion(notes: "Fragment would need surgery. Pass unless the price drops.", date: "Sep 9, 2026", basis: .repository, grade: .concern),
        "415_vet2": Opinion(notes: "Fragment is small and non-articular. Manageable.", date: "Sep 9, 2026", basis: .physicalExam, grade: .minor),
        "415_bs1": Opinion(notes: "Physically one of the best.", date: "Oct 24, 2026", rank: 9, outOf: 186, score: 8.6),
        "415_bs2": Opinion(notes: "Vet risk drags him down.", date: "Oct 24, 2026", rank: 31, outOf: 186, score: 7.2),
        "418_vet1": Opinion(notes: "Clean.", date: "Sep 9, 2026", basis: .repository, grade: .clean),
        "418_vet2": Opinion(notes: "Clean.", date: "Sep 9, 2026", basis: .physicalExam, grade: .clean),
        "418_bs1": Opinion(notes: "Late foal, still filling out.", date: "Oct 24, 2026", rank: 48, outOf: 186, score: 6.9),
        "418_bs2": Opinion(notes: "Will improve with time.", date: "Oct 24, 2026", rank: 40, outOf: 186, score: 7.0),
        "421_vet1": Opinion(notes: "Throat is fine with full abduction.", date: "Sep 10, 2026", basis: .repository, grade: .minor),
        "421_vet2": Opinion(notes: "Acceptable.", date: "Sep 10, 2026", basis: .physicalExam, grade: .clean),
        "421_bs1": Opinion(notes: "Powerful hind end.", date: "Oct 24, 2026", rank: 15, outOf: 186, score: 8.2),
        "421_bs2": Opinion(notes: "Our pick of the barn.", date: "Oct 24, 2026", rank: 6, outOf: 186, score: 8.9),
    ]
}
