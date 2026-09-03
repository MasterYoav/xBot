import SwiftUI

/// Soft, slowly drifting brand gradient — Sakura Mist through Bellflower Purple.
public struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        Group {
            if reduceTransparency {
                Palette.windowBackground
            } else {
                TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0 / 30.0)) { timeline in
                    let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.12
                    GeometryReader { geometry in
                        ZStack {
                            Palette.auroraBase
                            blob(
                                color: Palette.auroraCoral,
                                size: geometry.size,
                                phase: phase,
                                origin: CGPoint(x: 0.22, y: 0.18),
                                drift: 38
                            )
                            blob(
                                color: Palette.auroraIbis,
                                size: geometry.size,
                                phase: phase * 0.9 + 1.0,
                                origin: CGPoint(x: 0.78, y: 0.28),
                                drift: 34
                            )
                            blob(
                                color: Palette.auroraBellflower,
                                size: geometry.size,
                                phase: phase * 1.05 + 2.2,
                                origin: CGPoint(x: 0.62, y: 0.78),
                                drift: 44
                            )
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func blob(
        color: Color,
        size: CGSize,
        phase: Double,
        origin: CGPoint,
        drift: CGFloat
    ) -> some View {
        let diameter = max(size.width, size.height) * 0.58
        let opacity = colorScheme == .dark ? 0.38 : 0.34
        return Circle()
            .fill(color.opacity(opacity))
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.24)
            .position(
                x: size.width * origin.x + sin(phase + Double(origin.x * 10)) * drift,
                y: size.height * origin.y + cos(phase * 0.9 + Double(origin.y * 10)) * drift
            )
    }
}
