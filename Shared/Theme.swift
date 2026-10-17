import SwiftUI

// Design tokens. The app is dark-only and monochrome: one near-white accent on
// near-black surfaces, separated by hairlines rather than color or shadow.
// Muted text stays above 7:1 on the background; destructive red is the only hue.

private func hex(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

enum Palette {
    /// The single accent: selection, primary buttons, chart marks.
    static let primary = hex(0xFAFAFA)
    /// Text and glyphs drawn on `primary` fills.
    static let onPrimary = hex(0x0A0A0A)
    /// Main call to action (same as primary; kept as its own role).
    static let cta = primary
    static let background = hex(0x0A0A0A)
    /// Cards and grouped rows.
    static let surface = hex(0x141414)
    /// Recessed fills: inputs, unselected chips, icon tiles.
    static let fill = hex(0x1F1F1F)
    /// Hairline separators and card outlines.
    static let border = hex(0x2A2A2A)
    /// Secondary text: 8:1 on background.
    static let textMuted = hex(0xA1A1A1)
    /// Destructive actions only.
    static let danger = hex(0xF26D6D)
    static let warning = textMuted
    static let success = primary

    /// Greyscale steps for ranked series (charts, breakdown bars), brightest first.
    static let ramp: [Color] = [hex(0xFAFAFA), hex(0xB4B4B4), hex(0x7A7A7A), hex(0x4A4A4A), hex(0x333333)]

    /// Category accents are deliberately uniform in a monochrome theme.
    static func tint(for name: String) -> Color { primary }
}

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

enum Motion {
    /// Press feedback: quick, no overshoot.
    static let press = Animation.easeOut(duration: 0.12)
    /// Selection changes (pills, chips).
    static let select = Animation.spring(response: 0.3, dampingFraction: 0.9)
    /// Content entering.
    static let enter = Animation.easeOut(duration: 0.25)
}

extension Color {
    /// Kept for existing call sites: the app tint.
    static let brand = Palette.primary
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Palette.primary }
}
