import SwiftUI

public enum PillState: Sendable {
    case neutral, running, success, failure, warning, accent

    var color: Color {
        switch self {
        case .neutral: Palette.textSecondary
        case .running: Palette.running
        case .success: Palette.success
        case .failure: Palette.failure
        case .warning: Palette.warning
        case .accent: Palette.accent
        }
    }

    var tint: Color {
        switch self {
        case .neutral: Palette.hover
        case .running: Palette.runningTint
        case .success: Palette.successTint
        case .failure: Palette.failureTint
        case .warning: Palette.warningTint
        case .accent: Palette.accentTint
        }
    }
}

/// "● CONNECTED": a dot and mono capitals on a tint of the state's colour.
public struct StatusPill: View {
    let state: PillState
    let text: String

    public init(_ state: PillState, _ text: String) {
        self.state = state
        self.text = text
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            Circle().fill(state.color).frame(width: Metrics.dot - 1, height: Metrics.dot - 1)
            Text(text).labelText()
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, Space.s - 2)
        .padding(.vertical, Space.xxs)
        .background(state.tint, in: Capsule())
    }
}
