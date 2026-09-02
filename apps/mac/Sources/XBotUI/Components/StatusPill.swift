import SwiftUI

/// The floating capsule over the conversation.
///
/// Not part of the layout — content scrolls under it. It *materialises*: blur and scale animate
/// together on enter, so it reads as a surface arriving rather than an opacity ramp.
public struct StatusPill: View {
    private let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            ProgressView().controlSize(.small)
            Text(text).captionText()
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .xbotMaterial(Materials.overlayPill, opaqueFallback: Palette.elevatedSurface)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .transition(
            .scale(scale: 0.92).combined(with: .opacity)
        )
        .accessibilityLabel(text)
    }
}
