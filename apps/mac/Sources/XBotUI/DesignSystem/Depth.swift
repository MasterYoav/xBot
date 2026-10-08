import SwiftUI

/// Two depths: a card on the page, and something floating over it.
extension View {
    public func cardShadow() -> some View {
        shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
    }

    public func floatingShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 12, y: 8)
    }

    /// The raised card surface: fill, hairline, shadow.
    public func raisedSurface(radius: CGFloat = Radius.large) -> some View {
        background(Palette.raised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.hairline))
    }
}
