import AppKit
import SwiftUI

/// Semantic colour. Every token resolves in light and dark, and no view ever names a value.
///
/// Brand palette (official):
///   Sakura Mist `#FFF3EC` · Coral Glaze `#FFC9A3` · Ibis Haze `#F08A8C` · Bellflower Purple `#B65E8C`
public enum Palette {
    // Surfaces — warm sakura base in light, deep plum in dark.
    public static let windowBackground = dynamic(light: 0xFFF3EC, dark: 0x181014)
    public static let railBackground = dynamic(light: 0xFFEFE6, dark: 0x120C10)
    public static let panelBackground = dynamic(light: 0xFFF8F3, dark: 0x1E1418)
    public static let elevatedSurface = dynamic(light: 0xFFFFFF, dark: 0x261A20)

    // Message bubbles
    public static let bubbleIncoming = dynamic(light: 0xFFE8DC, dark: 0x2A1C22)
    public static let bubbleIncomingText = dynamic(light: 0x2A1820, dark: 0xFFF3EC)
    public static let bubbleOutgoing = dynamic(light: 0xB65E8C, dark: 0xC9789E)
    public static let bubbleOutgoingText = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)

    // Text
    public static let textPrimary = dynamic(light: 0x2A1820, dark: 0xFFF3EC)
    public static let textSecondary = Color.secondary
    public static let textTertiary = dynamic(light: 0x9A7080, dark: 0xA08090)

    // Separators
    public static let separator = dynamic(light: 0xF0D4C8, dark: 0x3A2830)

    // State — functional hues that still sit comfortably on the warm palette.
    public static let stateRunning = dynamic(light: 0x3D9A62, dark: 0x4CB876)
    public static let stateReconnecting = dynamic(light: 0xD4844A, dark: 0xE8A060)
    public static let stateStopped = dynamic(light: 0x9A7080, dark: 0x807080)
    public static let stateFailed = dynamic(light: 0xD04A52, dark: 0xF08A8C)
    public static let attention = dynamic(light: 0xF08A8C, dark: 0xF0A0A2)

    // Aurora background — the four official brand colours.
    public static let auroraBase = dynamic(light: 0xFFF3EC, dark: 0x140C10)
    public static let auroraCoral = dynamic(light: 0xFFC9A3, dark: 0xA87858)
    public static let auroraIbis = dynamic(light: 0xF08A8C, dark: 0xB8686A)
    public static let auroraBellflower = dynamic(light: 0xB65E8C, dark: 0x904A70)

    /// Agent identity — brand-forward with enough variety for the rail.
    public static let agentColors: [Color] = [
        dynamic(light: 0xB65E8C, dark: 0xC9789E),  // bellflower
        dynamic(light: 0xF08A8C, dark: 0xF0A0A2),  // ibis
        dynamic(light: 0xFFC9A3, dark: 0xE8B898),  // coral
        dynamic(light: 0x2A1820, dark: 0xFFF3EC),  // ink
        dynamic(light: 0x8E4A6E, dark: 0xA86080),  // plum
        dynamic(light: 0xD4844A, dark: 0xE8A060),  // amber
        dynamic(light: 0x3D9A62, dark: 0x4CB876),  // green
        dynamic(light: 0x6B4BC4, dark: 0x9070E0),  // violet
        dynamic(light: 0x2C6FD1, dark: 0x4C90EE),  // blue
        dynamic(light: 0x76767C, dark: 0x9A9AA0),  // grey
    ]

    public static func agentColor(seed: String) -> Color {
        let total = seed.utf8.reduce(0) { $0 &+ Int($1) }
        return agentColors[total % agentColors.count]
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark =
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            }
        )
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
