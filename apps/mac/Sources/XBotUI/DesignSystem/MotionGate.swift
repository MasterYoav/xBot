import SwiftUI

import XBotWorld

extension View {
    /// Put on each window's root: pauses looping motion while the app is in the background.
    public func motionGate() -> some View { modifier(MotionGate()) }
}

private struct MotionGate: ViewModifier {
    @Environment(\.controlActiveState) private var state
    func body(content: Content) -> some View { content.environment(\.motionPaused, state == .inactive) }
}
