import SwiftUI
import XBotCore

/// The current toast, bottom centre: a dark capsule that slides up and fades.
public struct ToastHost: View {
    let center: ToastCenter

    public init(center: ToastCenter) { self.center = center }

    public var body: some View {
        ZStack {
            if let toast = center.current {
                HStack(spacing: Space.s) {
                    if let symbol = toast.systemImage { Image(systemName: symbol) }
                    Text(toast.text)
                    if let action = toast.action {
                        Button(action.title) { center.performAction() }
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .font(Typography.chip)
                .foregroundStyle(Palette.textInverse)
                .padding(.horizontal, Space.m)
                .frame(height: Metrics.iconButton + Space.xs)
                .background(Palette.textPrimary, in: Capsule())
                .floatingShadow()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .padding(.bottom, Space.xl)
        .motion(Motion.panel, value: center.current?.id)
    }
}
