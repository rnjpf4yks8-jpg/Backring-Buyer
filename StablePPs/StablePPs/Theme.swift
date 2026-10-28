import SwiftUI

/// Turf green on a pale page, like the web version of Stable PPs.
enum Theme {
    static let turf = Color(hex: 0x1D5A3B)
    static let turfSoft = Color(hex: 0xE1EDE5)
    static let dirt = Color(hex: 0x95562A)
    static let dirtSoft = Color(hex: 0xF4E8DE)
    static let page = Color(hex: 0xF3F5F2)
    static let card = Color.white
    static let ink = Color(hex: 0x15201A)
    static let muted = Color(hex: 0x5B6A61)
    static let line = Color(hex: 0xD5DDD7)
    static let chip = Color(hex: 0xEEF2EF)
    static let good = Color(hex: 0x1F7A45)
    static let warn = Color(hex: 0x9A6A00)
    static let bad = Color(hex: 0xA3312A)

    /// Condensed figures for the past-performance lines.
    static func data(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }

    /// Tall condensed headings.
    static func display(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .heavy).width(.condensed)
    }

    static func surfaceColor(_ surface: String?) -> Color {
        switch surface {
        case "T": turf
        case "A": Color(hex: 0x4A5A8A)
        default: dirt
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// DRF-style text: the main part with its small raised part (beaten lengths, hundredths).
func raisedText(_ r: Raised, size: CGFloat = 13, weight: Font.Weight = .regular) -> Text {
    let main = Text(verbatim: r.main).font(Theme.data(size, weight))
    if r.raised.isEmpty { return main }
    let up = Text(verbatim: r.raised).font(Theme.data(size * 0.7, weight)).baselineOffset(size * 0.4)
    return Text("\(main)\(up)")
}

/// Several raised pieces in a row, separated by spaces.
func raisedRow(_ parts: [Raised], size: CGFloat = 13) -> Text {
    var out = Text(verbatim: "")
    var first = true
    for part in parts where !part.plain.isEmpty {
        let piece = raisedText(part, size: size)
        out = first ? piece : Text("\(out) \(piece)")
        first = false
    }
    return out
}

/// A white card with a hairline border.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

/// A small rounded label.
struct Chip: View {
    let text: String
    var color: Color = Theme.muted
    var fill: Color = Theme.chip

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(fill, in: Capsule())
    }
}

/// A grey note under a section, like the web version's notices.
struct Note: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A full-width button that looks like the web version's buttons.
struct ActionButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(primary ? Color.white : Theme.turf)
            .background(primary ? Theme.turf : Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(primary ? Theme.turf : Theme.line))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
