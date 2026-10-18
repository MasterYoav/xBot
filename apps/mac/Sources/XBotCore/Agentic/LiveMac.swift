import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// The real Mac: NSWorkspace for apps, ScreenCaptureKit for a single frame, Accessibility for the
/// screen's elements, CGEvent for the pointer and keys. Nothing here runs between calls.
@MainActor
public final class LiveMac: MacControlling {
    /// Opens the floating guide for a permission (the UI's; Core can't draw it).
    let guide: @MainActor (MacPermission) -> Void
    private let refs = AXRefs()

    public init(guide: @escaping @MainActor (MacPermission) -> Void) {
        self.guide = guide
    }

    public func isAllowed(_ permission: MacPermission) -> Bool { MacControlAccess.isAllowed(permission) }

    public func showGuide(for permission: MacPermission) { guide(permission) }

    // MARK: Apps

    public func runningApps() -> [RunningApp] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Apps with a Dock icon, and whatever is in front even without one: a system alert
        // (UserNotificationCenter asking about the firewall, say) takes the keys, and an agent
        // that didn't know would type into it.
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular || $0.processIdentifier == front }
            .map { app in
                RunningApp(name: app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)",
                           bundleID: app.bundleIdentifier, pid: app.processIdentifier,
                           isFrontmost: app.processIdentifier == front, isHidden: app.isHidden)
            }
    }

    public func frontWindowTitle(of app: RunningApp) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(element, 1)
        guard let window = AXRead.attribute(element, kAXFocusedWindowAttribute) ?? AXRead.attribute(element, kAXMainWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return AXRead.attribute(window as! AXUIElement, kAXTitleAttribute) as? String
    }

    public func open(_ target: String) async -> String? {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), let scheme = url.scheme, scheme.count > 1, !text.hasPrefix("/") {
            return NSWorkspace.shared.open(url) ? nil : "Nothing on this Mac opens \(text)."
        }
        let path = (text as NSString).expandingTildeInPath
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path), !path.hasSuffix(".app") {
            return NSWorkspace.shared.open(URL(filePath: path)) ? nil : "\(text) couldn't be opened."
        }
        guard let app = Self.application(text) else { return "There's no app called \(text) on this Mac." }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            return nil
        } catch {
            return "\(text) didn't open: \(error.localizedDescription)"
        }
    }

    /// By bundle id, a path to an .app, or a name in the usual folders.
    static func application(_ text: String) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: text) { return url }
        let path = (text as NSString).expandingTildeInPath
        if path.hasSuffix(".app"), FileManager.default.fileExists(atPath: path) { return URL(filePath: path) }
        let name = text.hasSuffix(".app") ? text : text + ".app"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for folder in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                       "\(home)/Applications", "/System/Library/CoreServices"] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            if let match = names.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                return URL(filePath: folder).appending(path: match)
            }
        }
        return nil
    }

    public func quit(_ app: RunningApp) -> Bool {
        NSRunningApplication(processIdentifier: app.pid)?.terminate() ?? false
    }

    // MARK: Screenshots

    public func screenshot(of app: RunningApp?) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        let points: CGSize
        if let app {
            // The front window: windows come front to back.
            guard let window = content.windows.first(where: {
                $0.owningApplication?.processID == app.pid && $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40
            }) else {
                throw CaptureProblem(message: "\(app.name) has no window on screen.")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            points = window.frame.size
        } else {
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                throw CaptureProblem(message: "No display was found.")
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            points = CGSize(width: display.width, height: display.height)
        }
        // Captured at the size it's sent at: one frame, no stream, nothing bigger than needed.
        let scale = CGFloat(filter.pointPixelScale)
        let size = ScreenshotJPEG.size(width: Int(points.width * scale), height: Int(points.height * scale))
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    struct CaptureProblem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Accessibility

    public func uiTree(of app: RunningApp) async throws -> [UINode] {
        let refs = self.refs
        let pid = app.pid
        // Off the main thread: a slow app takes up to a second per call to answer.
        return await Task.detached { AXRead.windows(of: pid, refs: refs) }.value
    }

    public func press(ref: Int) -> Bool {
        guard let element = refs.element(ref) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    public func frame(ref: Int) -> CGRect? { refs.element(ref).flatMap(AXRead.frame) }

    // MARK: Events

    public func click(at point: CGPoint) {
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(15_000)
        }
    }

    public func type(_ text: String) {
        for event in KeyCodes.typingEvents(for: text) {
            event.post(tap: .cghidEventTap)
            usleep(4_000)
        }
    }

    public func press(_ combo: KeyCombo) -> Bool {
        guard let events = KeyCodes.events(for: combo) else { return false }
        for event in events {
            event.post(tap: .cghidEventTap)
            usleep(8_000)
        }
        return true
    }

    public func scroll(dx: Double, dy: Double, at point: CGPoint?) {
        if let point {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        // Wheel values move the content: scrolling down is a negative wheel.
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(-dy.rounded()),
                wheel2: Int32(-dx.rounded()), wheel3: 0)?.post(tap: .cghidEventTap)
    }
}

/// Elements read by `mac_ui`, by number, so a later click can press one. Numbers only grow, so two
/// chats reading screens at once never press each other's; old ones are let go.
final class AXRefs: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Int: AXUIElement] = [:]
    private var next = 1

    func keep(_ element: AXUIElement) -> Int {
        lock.lock(); defer { lock.unlock() }
        let ref = next
        next += 1
        elements[ref] = element
        if elements.count > 6000 { elements = elements.filter { $0.key > ref - 3000 } }
        return ref
    }

    func element(_ ref: Int) -> AXUIElement? {
        lock.lock(); defer { lock.unlock() }
        return elements[ref]
    }
}

/// Reading Accessibility attributes, with limits: a big app has tens of thousands of elements.
enum AXRead {
    static let maxNodes = 1500
    static let maxDepth = 30

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    static func text(_ value: CFTypeRef?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    static func windows(of pid: pid_t, refs: AXRefs) -> [UINode] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var count = 0
        let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.prefix(4).compactMap { node($0, depth: 0, count: &count, refs: refs) }
    }

    static func node(_ element: AXUIElement, depth: Int, count: inout Int, refs: AXRefs) -> UINode? {
        guard count < maxNodes else { return nil }
        count += 1
        let names = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXEnabledAttribute,
                     kAXChildrenAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let list = values as? [AnyObject], list.count == 6 else { return nil }
        func ok(_ value: AnyObject) -> CFTypeRef? {
            // A missing attribute comes back as an AXValue holding an error.
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { return nil }
            return value
        }
        let role = (ok(list[0]) as? String) ?? "AXUnknown"
        let children = depth < maxDepth ? ((ok(list[5]) as? [AXUIElement]) ?? []) : []
        var node = UINode(role: role, title: ok(list[1]) as? String, label: ok(list[2]) as? String,
                          value: role == "AXSecureTextField" ? nil : text(ok(list[3])), frame: frame(element),
                          enabled: (ok(list[4]) as? Bool) ?? true, ref: refs.keep(element))
        node.children = children.compactMap { self.node($0, depth: depth + 1, count: &count, refs: refs) }
        return node
    }
}
