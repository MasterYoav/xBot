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

    #if DEBUG
    /// `XBOT_WINDOW_SNAPSHOT=/path.png swift run XBot`: a picture of the real window — title bar,
    /// traffic lights and all — a few seconds after launch, then quit. How the chrome is checked
    /// where screen recording is not allowed; never in a release build.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = ProcessInfo.processInfo.environment["XBOT_WINDOW_SNAPSHOT"] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if let window = NSApp.windows.first(where: \.isVisible), let frame = window.contentView?.superview,
               let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                frame.cacheDisplay(in: frame.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
                let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { type in
                    window.standardWindowButton(type).map { "\(type.rawValue): hidden=\($0.isHidden) frame=\($0.frame) super=\(String(describing: $0.superview?.frame))" } ?? "\(type.rawValue): none"
                }
                try? (["window: \(window.frame)", "content: \(String(describing: window.contentView?.frame))",
                       "contentLayoutRect: \(window.contentLayoutRect)"] + buttons)
                    .joined(separator: "\n").write(toFile: path + ".txt", atomically: true, encoding: .utf8)
            }
            NSApp.terminate(nil)
        }
    }
    #endif

    /// Saves every reply in progress and stops the CLIs writing them.
    func applicationWillTerminate(_ notification: Notification) {
        Self.workspace?.stopAll()
    }
}
