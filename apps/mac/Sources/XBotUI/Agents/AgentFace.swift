import AppKit
import SwiftUI
import XBotCore

/// The sidebar's face: the head in a round tile, alive.
struct AgentFace: View {
    let agent: Agent
    var size: CGFloat = 30
    var status: AgentStatus = .idle

    var body: some View {
        ZStack {
            Circle().fill(AvatarPalette.tile(agent.avatar))
            LivingAvatar(avatar: agent.avatar, pixel: size / 17, talking: status.isWorking, headOnly: true,
                         seed: agent.id.hashValue)
                .offset(y: -size * 0.12)
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .overlay {
            switch status {
            case .working: WorkingRing(size: size)
            case .done: Circle().strokeBorder(Palette.success, lineWidth: max(1.5, size / 16))
            case .idle: Circle().strokeBorder(Palette.hairline)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(agent.name)
    }
}

/// A turning arc: this one is busy.
private struct WorkingRing: View {
    let size: CGFloat
    @Environment(\.motionPaused) private var motionPaused
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: motionPaused)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4 * 360
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: max(1.5, size / 14), lineCap: .round))
                .rotationEffect(.degrees(angle))
                .padding(max(0.75, size / 28))
        }
        .accessibilityHidden(true)
    }
}

/// A crew member's sprite as a PNG, for the iPhone and iPad app.
public enum AvatarPicture {
    @MainActor
    public static func png(_ avatar: AgentAvatar, pixel: CGFloat = 6) -> Data? {
        let renderer = ImageRenderer(content: AvatarSprite(avatar: avatar, pixel: pixel))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
