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
            if ProcessInfo.processInfo.environment["XBOT_DRAFT_PROJECT"] != nil, let workspace = Self.workspace {
                workspace.startDraft(in: workspace.projects.first?.id)
                try? await Task.sleep(for: .seconds(1))
            }
            // XBOT_CLICK="145,16;878,16": real clicks at points measured from the window's top left.
            if let window = NSApp.windows.first(where: \.isVisible),
               let clicks = ProcessInfo.processInfo.environment["XBOT_CLICK"] {
                for pair in clicks.split(separator: ";") {
                    let xy = pair.split(separator: ",").compactMap { Double($0) }
                    guard xy.count == 2, let height = window.contentView?.superview?.bounds.height else { continue }
                    let point = CGPoint(x: xy[0], y: height - xy[1])
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: window.windowNumber, context: nil,
                                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                            window.sendEvent(event)
                        }
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
            if let window = NSApp.windows.first(where: \.isVisible), let frame = window.contentView?.superview,
               let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                frame.cacheDisplay(in: frame.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
                let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { type in
                    window.standardWindowButton(type).map { "\(type.rawValue): hidden=\($0.isHidden) frame=\($0.frame) super=\(String(describing: $0.superview?.frame))" } ?? "\(type.rawValue): none"
                }
                // Which view a click in the title bar row reaches, across the window's width.
                let hits = stride(from: CGFloat(10), to: frame.bounds.width, by: 30).map { x -> String in
                    let point = CGPoint(x: x, y: frame.bounds.height - 16)
                    var chain: [String] = []
                    var view = frame.hitTest(point)
                    while let v = view, chain.count < 4 { chain.append(String(describing: type(of: v))); view = v.superview }
                    return "hit x=\(Int(x)): " + chain.joined(separator: " < ")
                }
                // Every AppKit scroll view, in window coordinates: one reaching into the title bar row
                // sits above the SwiftUI top bar and takes its clicks.
                var scrollViews: [String] = []
                func collect(_ view: NSView) {
                    if view is NSScrollView {
                        scrollViews.append("scroll: \(view.convert(view.bounds, to: nil))")
                    }
                    view.subviews.forEach(collect)
                }
                collect(frame)
                try? (["window: \(window.frame)", "content: \(String(describing: window.contentView?.frame))",
                       "contentLayoutRect: \(window.contentLayoutRect)"] + buttons + scrollViews + hits)
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
