import CoreGraphics
import Foundation
import XBotTools

/// The mac_* tools: the Mac itself, through `MacControlling`.
extension ToolHost {
    func mac(_ tool: String, _ arguments: JSONValue, token: String) async -> ToolResult {
        switch tool {
        case "mac_screenshot": return await screenshot(arguments, token: token)
        case "mac_ui": return await ui(arguments, token: token)
        case "mac_click": return click(arguments, token: token)
        case "mac_type":
            guard let text = arguments["text"]?.stringValue, !text.isEmpty else { return missing("text") }
            mac.type(text)
            return .text("Typed \(text.count) characters.")
        case "mac_keys":
            guard let text = arguments.string("combo") else { return missing("combo") }
            let combo = KeyCombo.normalised(text)
            guard mac.press(combo) else { return .error("\(text) isn't a key xBot knows. Try names like return, escape, tab, space, up, f5, or a letter.") }
            return .text("Pressed \(text).")
        case "mac_scroll":
            let dx = arguments.number("dx") ?? 0, dy = arguments.number("dy") ?? 0
            guard dx != 0 || dy != 0 else { return missing("dx or dy") }
            let point = arguments.number("x").flatMap { x in arguments.number("y").map { CGPoint(x: x, y: $0) } }
            mac.scroll(dx: dx, dy: dy, at: point)
            return .text("Scrolled.")
        case "mac_open":
            guard let target = arguments.string("target") else { return missing("target") }
            if let problem = await mac.open(target) { return .error(problem) }
            return .text("Opened \(target).")
        case "mac_apps":
            let apps = mac.runningApps()
            return .text(apps.map { app in
                var line = app.name + (app.bundleID.map { " (\($0))" } ?? "")
                if app.isFrontmost { line += " — frontmost" }
                if app.isHidden { line += " — hidden" }
                return line
            }.joined(separator: "\n"))
        case "mac_quit":
            guard let name = arguments.string("app") else { return missing("app") }
            guard let app = mac.runningApps().first(where: { $0.isNamed(name) }) else { return .error("\(name) isn't running.") }
            return mac.quit(app) ? .text("Asked \(app.name) to quit.") : .error("\(app.name) didn't quit.")
        default:
            return .error("There's no Mac tool called \(tool).")
        }
    }

    /// The named app, or the frontmost when no name is given. A name that isn't running is an error.
    func target(_ arguments: JSONValue) -> Result<RunningApp?, Problem> {
        guard let name = arguments.string("app") else { return .success(mac.runningApps().first(where: \.isFrontmost)) }
        guard let app = mac.runningApps().first(where: { $0.isNamed(name) }) else {
            return .failure(Problem(message: "\(name) isn't running. mac_open starts it."))
        }
        return .success(app)
    }

    func screenshot(_ arguments: JSONValue, token: String) async -> ToolResult {
        guard let session = sessions[token] else { return .error(ToolClient.notRunning) }
        var app: RunningApp?
        if arguments.string("app") != nil {
            switch target(arguments) {
            case .success(let found): app = found
            case .failure(let problem): return .error(problem.message)
            }
        }
        let image: CGImage
        do { image = try await mac.screenshot(of: app) } catch {
            return .error("The screenshot didn't work: \(error.localizedDescription)")
        }
        guard let jpeg = ScreenshotJPEG.encode(image) else { return .error("The screenshot couldn't be saved as a picture.") }
        let id = UUID()
        let file = imagesFolder.appending(path: "\(id.uuidString).jpg")
        do {
            try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
            try jpeg.data.write(to: file, options: .atomic)
        } catch {
            return .error("The screenshot couldn't be saved: \(error.localizedDescription)")
        }
        let caption = app.map { String(localized: "\($0.name)'s window") } ?? String(localized: "The screen")
        post([.image(ImagePart(id: id, path: file.path(percentEncoded: false), width: jpeg.width, height: jpeg.height, caption: caption))],
             session: session)
        return ToolResult(content: [
            .image(jpeg.data, mimeType: "image/jpeg"),
            .text("\(app.map { "\($0.name)'s front window" } ?? "The main display"), scaled to \(jpeg.width)×\(jpeg.height) from \(image.width)×\(image.height) pixels. The person sees it in the chat too. For clicks, mac_ui gives elements and their frames in screen points."),
        ])
    }

    func ui(_ arguments: JSONValue, token: String) async -> ToolResult {
        let app: RunningApp
        switch target(arguments) {
        case .success(let found?): app = found
        case .success(nil): return .error("No app is frontmost.")
        case .failure(let problem): return .error(problem.message)
        }
        let roots: [UINode]
        do { roots = try await mac.uiTree(of: app) } catch {
            return .error("\(app.name)'s window couldn't be read: \(error.localizedDescription)")
        }
        let (lines, omitted) = UITree.lines(roots)
        sessions[token]?.elements = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard !lines.isEmpty else {
            return .text("\(app.name) shows no elements through Accessibility (no window open, or it doesn't support it). Take a mac_screenshot instead.")
        }
        return .text("\(app.name) (frames in screen points, top-left origin):\n" + UITree.text(lines, omitted: omitted))
    }

    func click(_ arguments: JSONValue, token: String) -> ToolResult {
        if let id = arguments.string("element") {
            guard let line = sessions[token]?.elements[id] else {
                return .error("There's no element \(id) from the last mac_ui. Read the screen again with mac_ui.")
            }
            if mac.press(ref: line.ref) { return .text("Pressed \(line.title.map { "\"\($0)\"" } ?? id).") }
            if let frame = mac.frame(ref: line.ref) ?? line.frame {
                mac.click(at: CGPoint(x: frame.midX, y: frame.midY))
                return .text("Clicked \(line.title.map { "\"\($0)\"" } ?? id).")
            }
            return .error("\(id) couldn't be pressed (it may have gone). Read the screen again with mac_ui.")
        }
        guard let x = arguments.number("x"), let y = arguments.number("y") else { return missing("element, or x and y") }
        mac.click(at: CGPoint(x: x, y: y))
        return .text("Clicked at \(Int(x)), \(Int(y)).")
    }
}
