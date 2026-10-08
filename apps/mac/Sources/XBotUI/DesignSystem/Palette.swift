import AppKit
import SwiftUI
import XBotCore

/// Semantic colour. Neutral surfaces; one accent (sakura), used only for selection, send, focus,
/// links and the Plan chip; state colours only where state is meant. Every token resolves in light
/// and dark, and no view ever names a value. See docs/superpowers/specs/2026-10-08-premium-ui-design.md.
public enum Palette {
    // Surfaces
    public static let window = dynamic(0xF7F7F5, 0x1E1E1E)
    public static let sidebar = dynamic(0xF0F0EE, 0x191919)
    public static let raised = dynamic(0xFFFFFF, 0x262626)
    public static let inset = dynamic(0xF2F2F0, 0x202020)
    public static let hairline = dynamic(0x000000, 0xFFFFFF, alpha: (0.08, 0.08))
    public static let hover = dynamic(0x000000, 0xFFFFFF, alpha: (0.04, 0.05))

    // Text
    public static let textPrimary = dynamic(0x1A1A1A, 0xECECEC)
    public static let textSecondary = dynamic(0x1A1A1A, 0xECECEC, alpha: (0.6, 0.6))
    public static let textTertiary = dynamic(0x1A1A1A, 0xECECEC, alpha: (0.4, 0.4))
    /// Text on `textPrimary` — the primary button, toasts.
    public static let textInverse = dynamic(0xFFFFFF, 0x1A1A1A)

    // Accent and state, each with the tint its pill sits on
    public static let accent = dynamic(0xB65E8C, 0xD08AB0)
    public static let accentTint = dynamic(0xB65E8C, 0xD08AB0, alpha: (0.12, 0.18))
    public static let running = dynamic(0x2C6FD1, 0x4C90EE)
    public static let runningTint = dynamic(0x2C6FD1, 0x4C90EE, alpha: (0.12, 0.18))
    public static let success = dynamic(0x2F9E5B, 0x4CB876)
    public static let successTint = dynamic(0x2F9E5B, 0x4CB876, alpha: (0.12, 0.18))
    public static let failure = dynamic(0xD0453E, 0xF07A72)
    public static let failureTint = dynamic(0xD0453E, 0xF07A72, alpha: (0.10, 0.16))
    public static let warning = dynamic(0xC98A1E, 0xE8A845)
    public static let warningTint = dynamic(0xC98A1E, 0xE8A845, alpha: (0.12, 0.18))

    // Code
    public static let codeKeyword = dynamic(0xA2456F, 0xE0A0C0)
    public static let codeString = dynamic(0x2F7D4F, 0x8CC8A0)
    public static let codeComment = dynamic(0x8A8A85, 0x7A7A75)
    public static let codeNumber = dynamic(0xB86A1E, 0xE0A060)

    /// Each agent's mark: Claude Code's clay, Codex in ink.
    public static func agent(_ kind: HarnessKind) -> Color {
        switch kind {
        case .claude: claude
        case .codex: textPrimary
        }
    }

    private static let claude = dynamic(0xD97757, 0xE08A6E)

    private static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? alpha.1 : alpha.0)
        })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
