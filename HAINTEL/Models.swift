import Foundation

enum Grade: String, Codable, Hashable, CaseIterable {
    case clean, minor, concern

    var label: String {
        switch self {
        case .clean: "Clean"
        case .minor: "Minor findings"
        case .concern: "Concern"
        }
    }
}

struct Pedigree: Codable, Hashable {
    var sire = ""
    var sireSire = ""
    var sireDam = ""
    var dam = ""
    var damSire = ""
    var damDam = ""
}

struct VetReport: Codable, Hashable {
    var radiographs: Grade = .clean
    var radiographNotes = ""
    var scope: Grade = .clean
    var scopeNotes = ""
    var filed = ""

    var isEntered: Bool { !filed.isEmpty || !radiographNotes.isEmpty || !scopeNotes.isEmpty }
}

/// What a paid vet opinion is based on. The vet states this in their report.
enum ExamBasis: String, Codable, Hashable, CaseIterable {
    case repository, physicalExam

    var label: String {
        switch self {
        case .repository: "Repository radiographs and videoscope"
        case .physicalExam: "Physical examination of the horse"
        }
    }
}

/// HP: horse physical, measured in the field by HAINTEL staff.
struct HorsePhysical: Codable, Hashable {
    var heightInches: Double
    var lengthInches: Double
    var measuredBy: String
    var date: String

    /// Height in hands, written the way horsemen do: 15.2 hh = 15 hands 2 inches.
    var heightHands: String {
        let whole = Int(heightInches.rounded())
        return "\(whole / 4).\(whole % 4) hh"
    }
}

struct AuctionRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var sale: String
    var date: String
    var hip: Int
    var result: String

    // id is only for SwiftUI lists; it isn't stored.
    enum CodingKeys: String, CodingKey { case sale, date, hip, result }
}

/// One catalog entry. Entered by HAINTEL staff.
struct Hip: Codable, Identifiable, Hashable {
    var id: Int { number }
    var number: Int
    var name = ""
    var sex = "colt"
    var color = "Bay"
    var foaled = ""
    var session = ""
    var barn = ""
    var consignor = ""
    var pedigree = Pedigree()
    /// The sale company's catalog page (pedigree PDF) for this hip.
    var pedigreeURL: URL?
    var vetReport = VetReport()
    var reserve: Int?
    var auctionHistory: [AuctionRecord] = []
    var walkVideoURL: URL?
    var walkVideoLength = ""
    var photoURL: URL?
    var physical: HorsePhysical?
    /// Which paid opinions have been posted. Lets buyers see what's for sale without reading the opinion.
    var opinionsIn: [OpinionSlot] = []
    /// Opinions posted but not yet approved by HAINTEL. Buyers don't see these.
    var opinionsPending: [OpinionSlot]? = nil
    /// C: HAINTEL's conformation grade, 1–10 in half points. Nil until graded.
    var conformationGrade: Double? = nil
    /// P: HAINTEL's pedigree grade, 1–5 in half points. Nil until graded.
    var pedigreeGrade: Double? = nil
    /// One line on why the hip got its grades.
    var gradeNotes: String? = nil

    var pendingSlots: [OpinionSlot] { opinionsPending ?? [] }

    /// An opinion was posted or edited: hide it from buyers until it's approved.
    mutating func markPending(_ slot: OpinionSlot) {
        opinionsIn.removeAll { $0 == slot }
        if !pendingSlots.contains(slot) { opinionsPending = pendingSlots + [slot] }
    }

    mutating func markReviewed(_ slot: OpinionSlot, approved: Bool) {
        opinionsPending = pendingSlots.filter { $0 != slot }
        opinionsIn.removeAll { $0 == slot }
        if approved { opinionsIn.append(slot) }
    }

    var isGraded: Bool { conformationGrade != nil || pedigreeGrade != nil }

    /// C + P, out of 15. Nil until the hip has both grades.
    var combinedGrade: Double? {
        guard let conformationGrade, let pedigreeGrade else { return nil }
        return conformationGrade + pedigreeGrade
    }

    /// A grade the way staff write it, with one decimal: 8.0, 4.5.
    static func gradeText(_ grade: Double) -> String { String(format: "%.1f", grade) }

    var title: String { "\(color) \(sex)" }
    var cross: String { pedigree.sire.isEmpty ? "Pedigree not entered" : "\(pedigree.sire) — \(pedigree.dam)" }
}

/// The four paid opinions on each hip.
enum OpinionSlot: String, Codable, Hashable, CaseIterable {
    case vet1, vet2, bs1, bs2

    var isVet: Bool { self == .vet1 || self == .vet2 }

    /// The hip screen button this opinion is under: Vet Opinions or Bloodstock Opinions.
    var field: HipField { isVet ? .vetOpinions : .bloodstockOpinions }

    var title: String {
        switch self {
        case .vet1: "Vet 1"
        case .vet2: "Vet 2"
        case .bs1: "BS1"
        case .bs2: "BS2"
        }
    }
}

/// A vet's or bloodstock agent's opinion on one hip. Only its author, staff,
/// and buyers who paid for it can read it.
struct Opinion: Codable, Hashable {
    var notes = ""
    var date = ""
    // Vet opinions
    var basis: ExamBasis?
    var grade: Grade?
    // Bloodstock agent opinions
    var rank: Int?
    var outOf: Int?
    var score: Double?
    /// HAINTEL approves each opinion before buyers can see it. Missing means approved (posted before reviews began).
    var status: OpinionStatus?

    var reviewStatus: OpinionStatus { status ?? .approved }
}

enum OpinionStatus: String, Codable, Hashable {
    case pending, approved, rejected

    var label: String {
        switch self {
        case .pending: "Waiting for HAINTEL approval"
        case .approved: "Approved"
        case .rejected: "Returned by HAINTEL"
        }
    }
}

/// Someone on the sale's opinion panel: the two vets and two bloodstock agents Sandeep picks.
struct PanelMember: Codable, Hashable {
    var uid: String
    var name: String
    var org: String
}

struct Sale: Codable, Hashable {
    var id: String
    var name: String
    var company: String
    var date: String
    /// Keyed by OpinionSlot raw value.
    var panel: [String: PanelMember] = [:]
    var vetPrice = 25
    var agentPrice = 50

    func member(_ slot: OpinionSlot) -> PanelMember? { panel[slot.rawValue] }
    func price(_ slot: OpinionSlot) -> Int { slot.isVet ? vetPrice : agentPrice }

    /// The sale date as a Date, for ordering the sales list. Dates are entered like "Oct 27, 2026".
    var day: Date? { Sale.dateFormat.date(from: date) }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

enum Role: String, Codable, Hashable {
    case buyer, staff, agent, vet

    var label: String {
        switch self {
        case .buyer: "Buyer"
        case .staff: "HAINTEL staff"
        case .agent: "Bloodstock agent"
        case .vet: "Vet"
        }
    }
}

struct AppUser: Codable, Hashable {
    var uid: String
    var name: String
    var role: Role
    /// Saved when the account is created, so staff can tell people apart on the Panel screen.
    var email: String? = nil
}

/// Screens pushed on the app's navigation stack: a sale's hip screen, then one of its 10 buttons.
enum Route: Hashable {
    case sale(String)
    case field(HipField)
}

/// The 10 buttons on the hip screen, in the order Sandeep listed them. Vet 1 and Vet 2 share the
/// Vet Opinions button, and BS1 and BS2 share Bloodstock Opinions; each screen has a menu to pick one.
enum HipField: Int, CaseIterable, Identifiable, Hashable {
    case hipNumber, vetReport, pedigree, auctionHistory, vetOpinions
    case bloodstockOpinions, reserve, saleWalkVideo, salePicture, hp

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .hipNumber: "Hip Number"
        case .vetReport: "Vet Report"
        case .pedigree: "Pedigree"
        case .auctionHistory: "Auction History"
        case .vetOpinions: "Vet Opinions"
        case .bloodstockOpinions: "Bloodstock Opinions"
        case .reserve: "Reserve"
        case .saleWalkVideo: "Sale Walk Video"
        case .salePicture: "Sale Picture"
        case .hp: "HP"
        }
    }

    var symbol: String {
        switch self {
        case .hipNumber: "number"
        case .vetReport: "doc.text.magnifyingglass"
        case .pedigree: "arrow.triangle.branch"
        case .auctionHistory: "clock.arrow.circlepath"
        case .vetOpinions: "stethoscope"
        case .bloodstockOpinions: "person.text.rectangle"
        case .reserve: "lock.fill"
        case .saleWalkVideo: "play.rectangle.fill"
        case .salePicture: "photo.fill"
        case .hp: "ruler"
        }
    }

    /// The paid opinions under this button: both vets, both bloodstock agents, or none.
    var slots: [OpinionSlot] {
        switch self {
        case .vetOpinions: [.vet1, .vet2]
        case .bloodstockOpinions: [.bs1, .bs2]
        default: []
        }
    }

    var isOpinionGroup: Bool { !slots.isEmpty }

    var previous: HipField? { HipField(rawValue: rawValue - 1) }
    var next: HipField? { HipField(rawValue: rawValue + 1) }
}
