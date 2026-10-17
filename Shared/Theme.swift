import SwiftUI
import UIKit

// Design tokens. Every screen pulls color, spacing, radius and motion from here;
// no per-screen hex values. Pairs were picked for WCAG contrast in both modes.

private func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
    func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
}

enum Palette {
    /// Trust blue: tint, links, selection.
    static let primary = dynamic(0x1E40AF, 0x60A5FA)
    /// Money green: the main call to action. White text on it is 5.5:1.
    static let cta = dynamic(0x047857, 0x047857)
    /// App backdrop (never pure white).
    static let background = dynamic(0xEEF2F7, 0x0B1120)
    /// Card surface on top of the backdrop.
    static let surface = dynamic(0xFFFFFF, 0x151E32)
    /// Recessed fills: inputs, unselected chips, empty chart.
    static let fill = dynamic(0xE2E8F0, 0x1E293B)
    /// Hairline borders on cards.
    static let border = dynamic(0xD5DCE6, 0x26324A)
    /// Secondary text: 7:1 on background in both modes.
    static let textMuted = dynamic(0x475569, 0x94A3B8)
    static let danger = dynamic(0xB91C1C, 0xF87171)
    static let warning = dynamic(0xB45309, 0xFBBF24)
    static let success = dynamic(0x047857, 0x34D399)

    /// Hero card gradient. Fixed deep tones so white text stays above 7:1 in both modes.
    static let heroStart = Color(red: 0x1E / 255, green: 0x3A / 255, blue: 0x8A / 255)
    static let heroEnd = Color(red: 0x43 / 255, green: 0x38 / 255, blue: 0xCA / 255)

    /// Category accents. Each reaches 3:1 as an icon on its own 15% tint.
    static let categoryTints: [Color] = [
        dynamic(0x1D4ED8, 0x60A5FA), dynamic(0x047857, 0x34D399), dynamic(0xB45309, 0xFBBF24),
        dynamic(0xBE185D, 0xF472B6), dynamic(0x6D28D9, 0xA78BFA), dynamic(0x0E7490, 0x22D3EE),
        dynamic(0xB91C1C, 0xF87171), dynamic(0x4D7C0F, 0xA3E635),
    ]

    /// Stable tint per category name.
    static func tint(for name: String) -> Color {
        let hash = name.lowercased().unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
        return categoryTints[abs(hash) % categoryTints.count]
    }
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
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

enum Motion {
    /// Press feedback: quick, no overshoot.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.85)
    /// Selection changes (pills, chips).
    static let select = Animation.spring(response: 0.32, dampingFraction: 0.8)
    /// Content entering.
    static let enter = Animation.spring(response: 0.45, dampingFraction: 0.82)
}

extension Color {
    /// Kept for existing call sites: the app tint.
    static let brand = Palette.primary
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Palette.primary }
}
