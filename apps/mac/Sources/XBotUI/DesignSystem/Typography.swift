import SwiftUI
import XBotCore

/// The type scale: SF Pro by default, or the family chosen in Settings › Appearance; SF Mono for
/// metadata and code whatever is chosen, because columns of code need a fixed width. Weight does
/// the hierarchy; sizes stay close.
///
/// Computed, not stored: each read looks at `Appearance.shared`, and because the read happens while
/// a view's body runs, Observation re-renders that view when the family changes. Stored tokens were
/// fixed at first use and a new font only appeared after a relaunch.
@MainActor
public enum Typography {
    public static var hero: Font { face(26, .semibold) }
    public static var title: Font { face(15, .semibold) }
    public static var body: Font { face(13) }
    public static var reading: Font { face(13.5) }
    public static var emphasis: Font { face(13, .medium) }
    public static var chip: Font { face(12, .medium) }
    public static var caption: Font { face(11) }
    public static let label = Font.system(size: 10, weight: .medium, design: .monospaced)
    public static let mono = Font.system(size: 12, design: .monospaced)

    private static func face(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let family = Appearance.shared.fontFamily else { return .system(size: size, weight: weight) }
        return .custom(family, fixedSize: size).weight(weight)
    }
}

extension View {
    /// Type plus its tracking, together, because they are not separable choices.
    public func xbotFont(_ font: Font, tracking: CGFloat) -> some View {
        self.font(font).tracking(tracking)
    }

    public func heroText() -> some View { xbotFont(Typography.hero, tracking: -0.4) }
    public func titleText() -> some View { xbotFont(Typography.title, tracking: -0.2) }
    public func bodyText() -> some View { xbotFont(Typography.body, tracking: 0) }
    public func emphasisText() -> some View { xbotFont(Typography.emphasis, tracking: 0) }
    public func captionText() -> some View { xbotFont(Typography.caption, tracking: 0.1) }
    /// Replies: a touch larger, with air between lines.
    public func readingText() -> some View { xbotFont(Typography.reading, tracking: 0).lineSpacing(4) }
    /// Metadata: "3 OF 7 DONE", "● CONNECTED".
    public func labelText() -> some View { xbotFont(Typography.label, tracking: 0.6).textCase(.uppercase) }
}
