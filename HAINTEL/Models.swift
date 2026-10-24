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
    var vetReport = VetReport()
    var reserve: Int?
    var auctionHistory: [AuctionRecord] = []
    var walkVideoURL: URL?
    var walkVideoLength = ""
    var photoURL: URL?
    var physical: HorsePhysical?
    /// Which paid opinions have been posted. Lets buyers see what's for sale without reading the opinion.
    var opinionsIn: [OpinionSlot] = []

    var title: String { "\(color) \(sex)" }
    var cross: String { pedigree.sire.isEmpty ? "Pedigree not entered" : "\(pedigree.sire) — \(pedigree.dam)" }
}

/// The four paid opinions on each hip.
enum OpinionSlot: String, Codable, Hashable, CaseIterable {
    case vet1, vet2, bs1, bs2

    var isVet: Bool { self == .vet1 || self == .vet2 }
    var field: HipField {
        switch self {
        case .vet1: .vet1
        case .vet2: .vet2
        case .bs1: .bs1Rank
        case .bs2: .bs2Rank
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
}

/// The 12 buttons on the hip screen, in the order Sandeep listed them.
enum HipField: Int, CaseIterable, Identifiable, Hashable {
    case hipNumber, vetReport, pedigree, auctionHistory, vet1, vet2
    case bs1Rank, bs2Rank, reserve, saleWalkVideo, salePicture, hp

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .hipNumber: "Hip Number"
        case .vetReport: "Vet Report"
        case .pedigree: "Pedigree"
        case .auctionHistory: "Auction History"
        case .vet1: "Vet 1"
        case .vet2: "Vet 2"
        case .bs1Rank: "BS1 Rank"
        case .bs2Rank: "BS2 Rank"
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
        case .vet1, .vet2: "stethoscope"
        case .bs1Rank, .bs2Rank: "person.text.rectangle"
        case .reserve: "lock.fill"
        case .saleWalkVideo: "play.rectangle.fill"
        case .salePicture: "photo.fill"
        case .hp: "ruler"
        }
    }

    var slot: OpinionSlot? {
        switch self {
        case .vet1: .vet1
        case .vet2: .vet2
        case .bs1Rank: .bs1
        case .bs2Rank: .bs2
        default: nil
        }
    }

    var previous: HipField? { HipField(rawValue: rawValue - 1) }
    var next: HipField? { HipField(rawValue: rawValue + 1) }
}
