import AppKit
import SwiftUI

/// Semantic colour. Every token resolves in light and dark, and no view ever names a value.
///
/// ponytail: defined in code rather than as an asset catalog. The spec writes these as
/// `Color("WindowBackground")`, which needs one `.colorset` directory and JSON file per token —
/// twenty-odd of them, hand-authored, for exactly the behaviour `NSColor(name:dynamicProvider:)`
/// already gives. The rule the spec is protecting is "no view names a raw value", and that holds
/// either way: the numbers live here and nowhere else. Move to an asset catalog when a designer
/// needs to edit them without a compiler, which is the only thing this cannot do.
public enum Palette {
    // Surfaces
    public static let windowBackground = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let railBackground = dynamic(light: 0xF2F2F7, dark: 0x161618)
    public static let panelBackground = dynamic(light: 0xFAFAFC, dark: 0x1F1F22)
    public static let elevatedSurface = dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)

    // Message bubbles, from the Grok Bot reference: light neutral in, near-black out.
    public static let bubbleIncoming = dynamic(light: 0xF1F1F4, dark: 0x2C2C2E)
    public static let bubbleIncomingText = dynamic(light: 0x111113, dark: 0xF5F5F7)
    public static let bubbleOutgoing = dynamic(light: 0x1A1A1C, dark: 0xE8E8EA)
    public static let bubbleOutgoingText = dynamic(light: 0xFFFFFF, dark: 0x111113)

    // Text
    public static let textPrimary = Color.primary
    public static let textSecondary = Color.secondary
    public static let textTertiary = dynamic(light: 0x9A9AA0, dark: 0x77777C)

    // Separators
    public static let separator = dynamic(light: 0xE3E3E8, dark: 0x2E2E32)

    // State
    public static let stateRunning = dynamic(light: 0x2A9E5C, dark: 0x35C36F)
    public static let stateReconnecting = dynamic(light: 0xC2870B, dark: 0xE0A526)
    public static let stateStopped = dynamic(light: 0x9A9AA0, dark: 0x77777C)
    public static let stateFailed = dynamic(light: 0xC2382E, dark: 0xE05A4F)
    public static let attention = dynamic(light: 0xD9542B, dark: 0xF0764A)

    /// Agent identity. The avatar palette from the reference picker.
    public static let agentColors: [Color] = [
        dynamic(light: 0x1A1A1C, dark: 0xE8E8EA),  // black
        dynamic(light: 0x6E4A2E, dark: 0x9C7047),  // brown
        dynamic(light: 0xC2382E, dark: 0xE05A4F),  // red
        dynamic(light: 0xD9542B, dark: 0xF0764A),  // orange
        dynamic(light: 0xC2870B, dark: 0xE0A526),  // amber
        dynamic(light: 0x2A9E5C, dark: 0x35C36F),  // green
        dynamic(light: 0x1E8E8E, dark: 0x2FB5B5),  // teal
        dynamic(light: 0x2C6FD1, dark: 0x4C90EE),  // blue
        dynamic(light: 0x6B4BC4, dark: 0x9070E0),  // purple
        dynamic(light: 0xC2418E, dark: 0xE066AC),  // pink
        dynamic(light: 0x76767C, dark: 0x9A9AA0),  // grey
    ]

    /// The stable colour for an agent, from its seed.
    ///
    /// Deterministic, so an agent looks the same on every launch and on every machine without the
    /// colour having to be stored or fetched. Sum of the UTF-8 bytes: the distribution does not
    /// need to be cryptographic, it needs to be the same answer twice.
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
