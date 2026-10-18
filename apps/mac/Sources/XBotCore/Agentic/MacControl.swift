import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An app running on the Mac, as `mac_apps` lists it.
public struct RunningApp: Equatable, Sendable {
    public var name: String
    public var bundleID: String?
    public var pid: Int32
    public var isFrontmost: Bool
    public var isHidden: Bool

    public init(name: String, bundleID: String?, pid: Int32, isFrontmost: Bool = false, isHidden: Bool = false) {
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
        self.isFrontmost = isFrontmost
        self.isHidden = isHidden
    }

    /// "Safari", "safari", "com.apple.Safari" all name Safari.
    public func isNamed(_ text: String) -> Bool {
        var wanted = text.trimmingCharacters(in: .whitespaces).lowercased()
        if wanted.hasSuffix(".app") { wanted.removeLast(4) }
        return name.lowercased() == wanted || bundleID?.lowercased() == wanted
    }
}

/// The two permissions Mac control needs, both granted only in System Settings.
public enum MacPermission: String, Sendable, CaseIterable {
    /// Reading the screen's elements, clicking, typing, keys.
    case accessibility
    /// Screenshots.
    case screenRecording
}

/// One element of an app's Accessibility tree, as read (before trimming). `ref` lets the reader
/// press the element later.
public struct UINode: Equatable, Sendable {
    public var role: String
    public var title: String?
    public var label: String?
    public var value: String?
    public var frame: CGRect?
    public var enabled: Bool
    public var ref: Int
    public var children: [UINode]

    public init(role: String, title: String? = nil, label: String? = nil, value: String? = nil, frame: CGRect? = nil,
                enabled: Bool = true, ref: Int = 0, children: [UINode] = []) {
        self.role = role; self.title = title; self.label = label; self.value = value
        self.frame = frame; self.enabled = enabled; self.ref = ref; self.children = children
    }
}

/// Everything Mac control touches on the system, behind one protocol so the tools are tested
/// without a real click (`LiveMac` is the real one).
@MainActor
public protocol MacControlling: AnyObject {
    func isAllowed(_ permission: MacPermission) -> Bool
    /// Opens the floating guide beside System Settings for `permission`.
    func showGuide(for permission: MacPermission)

    func runningApps() -> [RunningApp]
    /// The app's front window's title, through Accessibility. Nil when unknown.
    func frontWindowTitle(of app: RunningApp) -> String?
    /// The main display, or the app's front window.
    func screenshot(of app: RunningApp?) async throws -> CGImage
    /// The app's windows (one node per window, children below).
    func uiTree(of app: RunningApp) async throws -> [UINode]
    /// Presses an element read by the last `uiTree` (AXPress). False when it's gone.
    func press(ref: Int) -> Bool
    /// The element's frame, to click its middle when it can't be pressed.
    func frame(ref: Int) -> CGRect?

    func click(at point: CGPoint)
    func type(_ text: String)
    /// False when the key isn't one it knows.
    func press(_ combo: KeyCombo) -> Bool
    func scroll(dx: Double, dy: Double, at point: CGPoint?)
    /// An app (name or bundle id), a URL, or a path. Nil when opened; else why not.
    func open(_ target: String) async -> String?
    func quit(_ app: RunningApp) -> Bool
}

/// The trimmed tree `mac_ui` gives the model: elements it can see and use, each with a short id.
public enum UITree {
    public struct Line: Equatable, Sendable {
        public var id: String
        public var depth: Int
        public var role: String
        public var title: String?
        public var value: String?
        public var frame: CGRect?
        public var enabled: Bool
        public var ref: Int
    }

    /// Containers that say nothing themselves: not listed, their children are.
    static let silentRoles: Set<String> = ["AXGroup", "AXScrollArea", "AXSplitGroup", "AXLayoutArea", "AXUnknown",
                                           "AXList", "AXOutline", "AXTable", "AXRow", "AXColumn", "AXBrowser"]
    /// Worth listing even without a label: things to click or type into.
    static let actionableRoles: Set<String> = ["AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
                                               "AXPopUpButton", "AXMenuButton", "AXLink", "AXSlider", "AXComboBox",
                                               "AXMenuItem", "AXTab", "AXSearchField", "AXDisclosureTriangle",
                                               "AXIncrementor", "AXSwitch", "AXToggle"]

    /// Listed elements, depth-first, at most `limit`; invisible branches (no size) left out.
    public static func lines(_ roots: [UINode], limit: Int = 300, maxDepth: Int = 30, valueLength: Int = 120) -> (lines: [Line], omitted: Int) {
        var lines: [Line] = []
        var omitted = 0
        func visit(_ node: UINode, depth: Int, listedDepth: Int) {
            guard depth <= maxDepth else { return }
            if let frame = node.frame, frame.width <= 0 || frame.height <= 0, node.role != "AXWindow" { return }
            let title = clean(node.title) ?? clean(node.label)
            let value = clean(node.value).map { $0.count > valueLength ? String($0.prefix(valueLength)) + "…" : $0 }
            let listed = node.role == "AXWindow"
                || !silentRoles.contains(node.role) && (title != nil || value != nil || actionableRoles.contains(node.role))
            var childDepth = listedDepth
            if listed {
                if lines.count < limit {
                    lines.append(Line(id: "e\(lines.count + 1)", depth: listedDepth, role: node.role, title: title, value: value,
                                      frame: node.frame, enabled: node.enabled, ref: node.ref))
                } else {
                    omitted += 1
                }
                childDepth += 1
            }
            for child in node.children { visit(child, depth: depth + 1, listedDepth: childDepth) }
        }
        for root in roots { visit(root, depth: 0, listedDepth: 0) }
        return (lines, omitted)
    }

    /// One line per element: `e3 AXButton "Send" (812,640 64×28)`.
    public static func text(_ lines: [Line], omitted: Int) -> String {
        var out = lines.map { line -> String in
            var text = String(repeating: "  ", count: min(line.depth, 12)) + line.id + " " + line.role
            if let title = line.title { text += " \"\(title)\"" }
            if let value = line.value { text += " value=\"\(value)\"" }
            if let frame = line.frame {
                text += " (\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height)))"
            }
            if !line.enabled { text += " disabled" }
            return text
        }
        if omitted > 0 { out.append("… \(omitted) more elements not shown.") }
        return out.joined(separator: "\n")
    }

    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }
}

/// Screenshots as the spec has them: a JPEG at most 1600 px on its long side, quality about 0.6.
public enum ScreenshotJPEG {
    public static let maxDimension = 1600
    public static let quality = 0.6

    /// The size it'll be drawn at: scaled down to fit, never up.
    public static func size(width: Int, height: Int, maxDimension: Int = maxDimension) -> (width: Int, height: Int) {
        let long = max(width, height)
        guard long > maxDimension, long > 0 else { return (width, height) }
        let scale = Double(maxDimension) / Double(long)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    public static func encode(_ image: CGImage, maxDimension: Int = maxDimension, quality: Double = quality) -> (data: Data, width: Int, height: Int)? {
        let (width, height) = size(width: image.width, height: image.height, maxDimension: maxDimension)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data, width, height)
    }
}

/// macOS virtual key codes (Carbon's kVK_ values, which are fixed by the hardware layout) and the
/// event flags for a combination.
public enum KeyCodes {
    public static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "tab": 48, "space": 49, "`": 50, "delete": 51, "enter": 76, "escape": 53, "f17": 64, "f18": 79, "f19": 80,
        "f20": 90, "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101, "f11": 103, "f13": 105, "f16": 106,
        "f14": 107, "f10": 109, "f12": 111, "f15": 113, "help": 114, "home": 115, "pageup": 116, "forwarddelete": 117,
        "f4": 118, "end": 119, "f2": 120, "pagedown": 121, "f1": 122, "left": 123, "right": 124, "down": 125, "up": 126,
        "+": 24,
    ]

    public static func code(for key: String) -> CGKeyCode? { codes[key] }

    public static func flags(_ modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option": flags.insert(.maskAlternate)
            case "control": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        return flags
    }

    /// The key-down and key-up events for a combination, not posted. Nil for an unknown key.
    public static func events(for combo: KeyCombo) -> [CGEvent]? {
        guard let code = code(for: combo.key) else { return nil }
        let flags = flags(combo.modifiers)
        return [true, false].compactMap { down in
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            return event
        }
    }

    /// Typing: one key-down and key-up per chunk of at most 20 UTF-16 units, the text carried as
    /// the event's Unicode string so any character types whatever the keyboard layout.
    public static func typingEvents(for text: String) -> [CGEvent] {
        var events: [CGEvent] = []
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            var end = min(start + 20, units.count)
            // Never split a surrogate pair.
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            let chunk = Array(units[start..<end])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                events.append(event)
            }
            start = end
        }
        return events
    }
}
