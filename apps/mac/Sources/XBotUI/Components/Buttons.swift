import SwiftUI

/// The one strong action on a surface: a black capsule (white in dark mode).
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.chip)
            .foregroundStyle(Palette.textInverse)
            .padding(.horizontal, Space.m)
            .frame(height: Metrics.chipHeight)
            .background(Palette.textPrimary.opacity(isEnabled ? 1 : 0.3), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.1, bounce: 0), value: configuration.isPressed)
    }
}

/// A secondary action: text that gets a fill on hover.
public struct QuietButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        QuietLabel(configuration: configuration)
    }

    private struct QuietLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typography.chip)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Space.s)
                .frame(height: Metrics.chipHeight)
                .background(hovering ? Palette.hover : .clear, in: Capsule())
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(duration: 0.1, bounce: 0), value: configuration.isPressed)
        }
    }
}

/// A 28pt symbol button with a hover fill.
public struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    public init(_ systemImage: String, help: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Typography.emphasis)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                .background(hovering ? Palette.hover : .clear,
                            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(XBotButtonStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
