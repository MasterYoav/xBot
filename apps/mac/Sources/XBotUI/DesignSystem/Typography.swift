import SwiftUI

/// The type scale.
///
/// Named `Typography` rather than the spec's `Type`: `Type` collides with how Swift reads metatypes
/// at a glance (`Type.body` beside `Foo.Type`) and every call site would carry that ambiguity for
/// no gain. The values are the spec's, unchanged. Flagged in docs rather than changed silently.
public enum Typography {
    public static let displayTitle = Font.system(size: 28, weight: .semibold)
    public static let sectionTitle = Font.system(size: 17, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    public static let caption = Font.system(size: 11)
    public static let mono = Font.system(size: 12, design: .monospaced)
}

extension View {
    /// Type plus its tracking, together, because they are not separable choices.
    ///
    /// Tracking is size-specific: large text reads too loose as it grows and wants negative
    /// tracking, small text wants a touch more. Applying the font without its tracking is the
    /// mistake this modifier exists to make impossible — there is no call site that gets one
    /// without the other.
    public func xbotFont(_ font: Font, tracking: CGFloat) -> some View {
        self.font(font).tracking(tracking)
    }

    public func displayTitle() -> some View { xbotFont(Typography.displayTitle, tracking: -0.4) }
    public func sectionTitle() -> some View { xbotFont(Typography.sectionTitle, tracking: -0.2) }
    public func bodyText() -> some View { xbotFont(Typography.body, tracking: 0) }
    public func bodyEmphasis() -> some View { xbotFont(Typography.bodyEmphasis, tracking: 0) }
    public func captionText() -> some View { xbotFont(Typography.caption, tracking: 0.1) }
}
