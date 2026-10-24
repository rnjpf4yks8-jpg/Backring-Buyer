import SwiftUI

// Palette carried over from the Eliskopes site: navy and amber on a light slate page.
enum Theme {
    static let navy = Color(hex: 0x0B1730)
    static let navyCard = Color(hex: 0x12213F)
    static let navyRaised = Color(hex: 0x1A2C52)
    static let navyBorder = Color(hex: 0x24365C)
    static let amber = Color(hex: 0xF2B544)
    static let ink = Color(hex: 0x0E1726)
    static let slate = Color(hex: 0x4A5568)
    static let mist = Color(hex: 0xC9D3E6)
    static let muted = Color(hex: 0x8E9BB7)
    static let page = Color(hex: 0xF5F6F8)
    static let line = Color(hex: 0xE3E7EE)
    static let blue = Color(hex: 0x1F4FD1)
    static let blueTint = Color(hex: 0xF3F6FE)
    static let green = Color(hex: 0x146C3A)
    static let orange = Color(hex: 0xB45309)
    static let red = Color(hex: 0xB42318)

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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

/// Small uppercase monospaced label, like the section eyebrows on the website.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.blue

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11, .medium))
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

/// White card with a hairline border.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.slate)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? Theme.mono(15, .medium) : Theme.sans(15, .medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct GradeBadge: View {
    let grade: Grade

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(grade.color).frame(width: 8, height: 8)
            Text(grade.label)
                .font(Theme.sans(12, .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .foregroundStyle(grade.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(grade.color.opacity(0.1), in: Capsule())
    }
}

extension Grade {
    var color: Color {
        switch self {
        case .clean: Theme.green
        case .minor: Theme.orange
        case .concern: Theme.red
        }
    }
}

func usd(_ amount: Int) -> String {
    amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
}
