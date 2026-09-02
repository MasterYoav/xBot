import SwiftUI
import XBotEngine

/// Shape, colour, and an optional status ring. Drawn locally from the agent's seed — no network,
/// so the rail paints on the first frame and looks the same on every machine.
public struct AgentAvatar: View {
    public enum Size {
        case small, medium, large

        var side: CGFloat {
            switch self {
            case .small: 22
            case .medium: 36
            case .large: 64
            }
        }

        var corner: CGFloat {
            switch self {
            case .small: Radius.small
            case .medium: Radius.avatar
            case .large: Radius.large
            }
        }
    }

    public enum Activity: Equatable {
        case idle
        /// A turn is in flight.
        case working
        /// Blocked on the human. The strongest treatment in the rail.
        case needsYou
    }

    private let seed: String
    private let initials: String
    private let size: Size
    private let activity: Activity

    public init(agent: Agent, size: Size = .medium, activity: Activity = .idle) {
        self.seed = agent.avatarSeed
        self.initials = Self.initials(from: agent.name)
        self.size = size
        self.activity = activity
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size.corner, style: .continuous)
            .fill(Palette.agentColor(seed: seed))
            .overlay {
                Text(initials)
                    .font(.system(size: size.side * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size.side, height: size.side)
            .overlay {
                if activity == .working {
                    RoundedRectangle(cornerRadius: size.corner + 2, style: .continuous)
                        .strokeBorder(Palette.stateReconnecting, lineWidth: 2)
                        .padding(-3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if activity == .needsYou {
                    // Shape as well as colour. Colour is never the only signal — this has to read
                    // for someone who cannot separate our amber from our green.
                    Image(systemName: "exclamationmark")
                        .font(.system(size: size.side * 0.24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size.side * 0.42, height: size.side * 0.42)
                        .background(Circle().fill(Palette.attention))
                        .offset(x: size.side * 0.14, y: -size.side * 0.14)
                }
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch activity {
        case .idle: initials
        case .working: String(localized: "\(initials), working")
        case .needsYou: String(localized: "\(initials), needs you")
        }
    }

    private static func initials(from name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
