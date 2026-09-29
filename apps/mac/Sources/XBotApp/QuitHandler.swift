import AppKit
import XBotCore

/// Holds the quit long enough to decide what happens to the engine, and no longer.
///
/// `AppState.prepareToQuit` sends the stop and returns without waiting for it, and gives its one
/// question — are routines switched on — a short deadline. So the pause a person sees between
/// ⌘Q and the app vanishing is at most that deadline, and usually a round trip on loopback.
@MainActor
final class QuitHandler: NSObject, NSApplicationDelegate {
    /// Set once, when the app builds its state. Nil in a build with no managed runtime.
    static var state: AppState?

    /// A bare executable — `swift run`, or the debug binary started from a script — has no
    /// Info.plist, and macOS can hand it the prohibited policy: the window draws and its field even
    /// shows focus, but the app is never frontmost, so every keystroke goes to whatever is. The
    /// bundled app never takes this branch.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard Bundle.main.bundleIdentifier == nil else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state = Self.state, state.hasManagedRuntime else { return .terminateNow }
        Task { @MainActor in
            await state.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
