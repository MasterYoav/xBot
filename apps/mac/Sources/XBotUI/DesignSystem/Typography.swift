import SwiftUI

/// The type scale: SF Pro, with SF Mono for metadata. Weight does the hierarchy; sizes stay close.
public enum Typography {
    public static let hero = Font.system(size: 26, weight: .semibold)
    public static let title = Font.system(size: 15, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let reading = Font.system(size: 13.5)
    public static let emphasis = Font.system(size: 13, weight: .medium)
    public static let chip = Font.system(size: 12, weight: .medium)
    public static let caption = Font.system(size: 11)
    public static let label = Font.system(size: 10, weight: .medium, design: .monospaced)
    public static let mono = Font.system(size: 12, design: .monospaced)
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
