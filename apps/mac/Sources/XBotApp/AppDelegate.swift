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
            // XBOT_PROJECT=/path: aim Home at that folder (added for the run, removed at the end).
            var added: UUID?
            if let path = ProcessInfo.processInfo.environment["XBOT_PROJECT"], let workspace = Self.workspace {
                let project = workspace.addProject(at: URL(filePath: path))
                added = project.id
                workspace.startDraft(in: project.id)
            }
            // XBOT_HANG_LOG=/path: a line for every time the main thread is late by 100 ms or more.
            if let log = ProcessInfo.processInfo.environment["XBOT_HANG_LOG"] {
                Self.watchMainThread(log: log)
            }
            defer { if let added { Self.workspace?.removeProject(added) } }
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
            // XBOT_SOAK=seconds: after the clicks, leave the app running that long before the picture.
            if let soak = ProcessInfo.processInfo.environment["XBOT_SOAK"].flatMap(Double.init) {
                if ProcessInfo.processInfo.environment["XBOT_DRAFT_PROJECT"] != nil, let workspace = Self.workspace {
                    workspace.startDraft(in: workspace.projects.first?.id)
                }
                try? await Task.sleep(for: .seconds(soak))
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
                try? (["window: \(window.frame)", "content: \(String(describing: window.contentView?.frame))",
                       "contentLayoutRect: \(window.contentLayoutRect)"] + buttons + hits)
                    .joined(separator: "\n").write(toFile: path + ".txt", atomically: true, encoding: .utf8)
            }
            NSApp.terminate(nil)
        }
    }

    /// Pings the main queue every 50 ms from a background thread and logs each reply that came late.
    private static func watchMainThread(log: String) {
        FileManager.default.createFile(atPath: log, contents: nil)
        let handle = FileHandle(forWritingAtPath: log)
        Thread.detachNewThread {
            while true {
                let sent = Date.now
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                answered.wait()
                let late = Date.now.timeIntervalSince(sent)
                if late >= 0.1 { handle?.write(Data("\(Int(sent.timeIntervalSince1970)) late \(Int(late * 1000)) ms\n".utf8)) }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
    #endif

    /// Saves every reply in progress and stops the CLIs writing them.
    func applicationWillTerminate(_ notification: Notification) {
        Self.workspace?.stopAll()
    }
}
