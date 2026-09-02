import SwiftUI

/// Springs, because they are interruptible and velocity-aware. Nothing here is a fixed-duration
/// curve on anything the user can touch.
///
/// `duration` is Apple's *response* — how quickly the value reaches its target — not a settle time.
/// A spring has no fixed duration; settle emerges.
public enum Motion {
    /// Default for everything. No overshoot.
    public static let standard = Animation.spring(duration: 0.4, bounce: 0)
    /// Small state changes: toggles, highlights, badges.
    public static let quick = Animation.spring(duration: 0.25, bounce: 0)
    /// Panels, sheets, drawers.
    public static let panel = Animation.spring(duration: 0.3, bounce: 0.2)
    /// Only after a flick, throw, or drag release. Bounce is earned by a gesture, never chosen.
    public static let momentum = Animation.spring(duration: 0.4, bounce: 0.2)
    /// Reposition of an existing element.
    public static let reposition = Animation.spring(duration: 0.4, bounce: 0)

    /// The non-vestibular equivalent, for Reduce Motion.
    ///
    /// A cross-fade, not nothing. Reduced motion is a gentler signal, not the absence of one —
    /// removing the feedback entirely leaves a user who cannot tell whether their input registered.
    public static let reduced = Animation.easeOut(duration: 0.15)
}

extension View {
    /// Animate with a token, honouring Reduce Motion here rather than at the call site.
    ///
    /// The spec's rule is that accessibility lives in the token so no call site can forget, and a
    /// `static let` cannot read the environment — so the swap happens in this modifier, which is
    /// the only thing views are given. There is no way to animate with a token and miss this.
    public func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : animation, value: value)
    }
}

/// Feedback on press, never on release.
///
/// The scale is applied from `configuration.isPressed`, which SwiftUI sets on pointer-down. Putting
/// it in the action closure instead — the common mistake — delays every visible response until the
/// gesture ends, which is exactly the latency the first section of the design system is about.
public struct XBotButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.1, bounce: 0), value: configuration.isPressed)
    }
}

/// Apple's momentum projection, from the *Designing Fluid Interfaces* sample.
///
/// Exponential decay, deliberately NOT the textbook `v²/(2·deceleration)`. Snapping to the boundary
/// nearest the release point ignores where the gesture was going; this projects that first, and the
/// snap target is chosen from the projection.
public func project(initialVelocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
    (initialVelocity / 1000) * decelerationRate / (1 - decelerationRate)
}

/// Progressive resistance past a boundary. A hard stop reads as frozen rather than as a limit.
public func rubberband(
    _ overshoot: CGFloat,
    dimension: CGFloat,
    constant: CGFloat = 0.55
) -> CGFloat {
    (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
}
