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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state = Self.state, state.hasManagedRuntime else { return .terminateNow }
        Task { @MainActor in
            await state.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
