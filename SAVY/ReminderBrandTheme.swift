import SwiftUI

/// Notorious Recall palette + type. Page surfaces are black; entry forms are white.
enum Brand {
    static let crimson = Color(red: 0xDC / 255, green: 0x14 / 255, blue: 0x3C / 255)
    static let page    = Color(hex: 0x0A1626)              // deep navy page background (was black)
    static let card    = Color(red: 0xF3 / 255, green: 0xEA / 255, blue: 0xD5 / 255) // entry-form background (cream)
    static let ink     = Color.black
    static let dim     = Color(white: 0.6)

    // Reminders-screen palette (from the Figma "Screen / Reminders" frame).
    static let tan         = Color(hex: 0xD5C194)   // RECALL band + tab bar
    static let nearBlack   = Color(hex: 0x0C1E33)   // deep navy — heroes, dark feed cards, FAB options (was near-black)
    static let darkRed     = Color(hex: 0xB00124)   // story / tile red
    static let recallBlue  = Color(hex: 0x021784)   // "RECALL" label
    static let cyan        = Color(hex: 0x0C8A92)   // deep aqua — white text pops
    static let tileBlue    = Color(hex: 0x0F288E)   // deep blue (cyan-card text)
    // Primary palette — "truest" colors, vivid against the navy.
    static let primaryBlue   = Color(hex: 0x1D4ED8)
    static let primaryYellow = Color(hex: 0xF4C400)
    static let primaryGreen  = Color(hex: 0x1E9E57)
    static let tileGray    = Color(hex: 0xCFD3D9)   // light gray tile
    static let tileDark    = Color(hex: 0x14304D)   // lighter navy tile (was near-black)
    static let tabActive   = Color(hex: 0x2E2716)   // active tab label
    static let tabInactive = Color(hex: 0x7D6A45)   // inactive tab label

    /// Matches Notorious Recall — Bodoni 72 Oldstyle ships on every iPhone.
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        SavyTypography.displaySerif(size, weight: weight)
    }
}

extension Color {
    /// 0xRRGGBB convenience initializer for design-token colors.
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
