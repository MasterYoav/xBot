import AppKit
import Observation
import XBotCore

/// Whether animations may run right now (see `MotionPolicy`). Views read `isLive` in their body,
/// so they pause and resume as it changes.
@MainActor @Observable
public final class MotionGate {
    public static let shared = MotionGate()
    public private(set) var isLive = true
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification, NSApplication.didUnhideNotification,
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { MotionGate.shared.update() }
            })
        }
        update()
    }

    func update() {
        let onScreen = NSApp.windows.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
        // XBOT_MOTION_ALWAYS=1: animate regardless, to measure drawing cost from a background copy.
        let always = ProcessInfo.processInfo.environment["XBOT_MOTION_ALWAYS"] == "1"
        let live = always || MotionPolicy.isLive(appActive: NSApp.isActive, windowOnScreen: onScreen)
        if live != isLive { isLive = live }
    }
}
