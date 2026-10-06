import AppKit
import XBotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var workspace: Workspace?

    /// A bare executable (`swift run`) has no Info.plist and can be handed the prohibited
    /// activation policy: the window draws but never takes keystrokes. The bundled app never
    /// takes this branch.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard Bundle.main.bundleIdentifier == nil else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Saves every reply in progress and stops the CLIs writing them.
    func applicationWillTerminate(_ notification: Notification) {
        Self.workspace?.stopAll()
    }
}
