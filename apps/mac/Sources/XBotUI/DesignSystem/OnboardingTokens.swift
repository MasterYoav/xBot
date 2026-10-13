import AppKit
import SwiftUI

/// The onboarding's animated scenes (`Onboarding/Scenes/`): their clock, their stage, and the few
/// inks they need that the rest of the app doesn't. Everything else in a scene comes from
/// `Palette`, `Typography`, `Space`, `Radius`, `Metrics` and `Motion`.
public enum SceneMotion {
    /// The scenes' frame rate: smooth enough for walking and streaming text, light on CPU.
    public static let frameInterval: Double = 1.0 / 30
    /// The postcards drift rather than dash, and draw five worlds at once: half the rate.
    public static let ambientInterval: Double = 1.0 / 15
    /// The tempo every scene's choreography is written in, so the scenes feel like one film.
    public static let beat: Double = 0.5
    /// How long a loop takes to fade in at its start, and out at its seam.
    public static let loopFadeIn: Double = 0.4
    public static let loopFadeOut: Double = 0.6
    /// How far (in points of the design canvas) something travels as it fades in.
    public static let rise: CGFloat = 14
}

public enum SceneMetrics {
    /// Scenes are composed on this canvas and scaled to the room the onboarding gives them
    /// (560 × 340 to 960 × 560); the longer side grows, so a wider room shows more world.
    public static let canvas = CGSize(width: 720, height: 420)
    /// The corners of a world scene's frame: rounder than a card, it is a picture, not a panel.
    public static let frameRadius: CGFloat = 22
    /// The stylised xBot window in the chat, plan and inspector scenes.
    public static let mockWindow = CGSize(width: 600, height: 336)
    public static let mockSidebar: CGFloat = 150
    public static let trafficLight: CGFloat = 9
    /// Points per sprite pixel for the crew in a full scene, and in the postcards.
    public static let crewPixel: CGFloat = 4
    public static let postcardPixel: CGFloat = 2
    /// A postcard of a world, and its white border.
    public static let postcard = CGSize(width: 200, height: 128)
    public static let postcardBorder: CGFloat = 5
    /// The three cards that flip in on the extras scene.
    public static let extraCard = CGSize(width: 196, height: 236)
    /// A folder on the files scene, and the badge on its corner.
    public static let folder: CGFloat = 132
    public static let folderBadge: CGFloat = 38
}

/// Type that only exists inside the scenes: the miniature windows' small glyphs and code, and the
/// world's name tags and balloons (rounded, in the manner of the pixel worlds).
public enum SceneType {
    /// Small glyphs in a miniature window: a disclosure chevron, a tab's icon.
    public static let glyph = Font.system(size: 9, weight: .semibold)
    /// A step's icon in a miniature automation.
    public static let stepGlyph = Font.system(size: 10, weight: .semibold)
    /// The send button's arrow.
    public static let sendGlyph = Font.system(size: 11, weight: .bold)
    /// Code in a miniature diff, and a miniature terminal's text.
    public static let diff = Font.system(size: 9.5, design: .monospaced)
    public static let terminal = Font.system(size: 11, design: .monospaced)
    /// The pointer that drags a plan step.
    public static let pointer = Font.system(size: 17)
    /// The check on a phone that has just paired.
    public static let pairedCheck = Font.system(size: 34)
    /// The world's name tags, speech balloons, and the notes the crew sings.
    public static let nameTag = Font.system(size: 10, weight: .semibold, design: .rounded)
    public static let balloon = Font.system(size: 11, weight: .bold, design: .rounded)
    public static let song = Font.system(size: 15, weight: .heavy, design: .rounded)
}

/// Inks for the scenes' objects that the interface itself never draws: a Finder folder, the
/// hardware of a Mac and an iPhone, the warm light around the crew.
public enum ScenePalette {
    /// Finder's folder blue, and the darker blue of its tab and glyph.
    public static let folder = dynamic(0x6CB4F2, 0x5FA6E6)
    public static let folderTab = dynamic(0x4F97DA, 0x4A8CCB)
    public static let folderGlyph = dynamic(0x2F6FAE, 0x23527F)
    /// Device hardware: an aluminium Mac, a dark iPhone, and the glass of their screens.
    public static let aluminium = dynamic(0xD9DADE, 0x6B6D73)
    public static let aluminiumEdge = dynamic(0xB8BABF, 0x4C4E53)
    public static let phoneBody = dynamic(0x2A2B2F, 0x0E0E10)
    public static let screenGlass = dynamic(0x111214, 0x050506)
    /// A QR code is dark on white whatever the appearance, as on paper and on every screen that shows one.
    public static let qrPaper = dynamic(0xFFFFFF, 0xFFFFFF)
    public static let qrInk = dynamic(0x16161A, 0x16161A)
    /// Text and marks on a device's dark screen, light or dark appearance alike.
    public static let screenInk = dynamic(0xF4F4F6, 0xF4F4F6)
    /// The warm light that gathers behind the crew on the last step.
    public static let glow = dynamic(0xFFE3B0, 0xFFD58A, alpha: (0.55, 0.45))
    /// The ambient light behind the floating mock windows: the accent, very faint.
    public static let ambient = dynamic(0xB65E8C, 0xD08AB0, alpha: (0.10, 0.14))
    /// A diff's added line, before it settles into `successTint`, and a removed one.
    public static let diffRemoved = dynamic(0xD0453E, 0xF07A72, alpha: (0.10, 0.14))

    private static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? alpha.1 : alpha.0)
        })
    }
}
