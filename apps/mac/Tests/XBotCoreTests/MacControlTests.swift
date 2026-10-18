import CoreGraphics
import Foundation
import Testing
@testable import XBotCore

@Suite struct MacControlTests {
    // MARK: The Accessibility tree, trimmed

    func window(_ children: [UINode]) -> UINode {
        UINode(role: "AXWindow", title: "Untitled", frame: CGRect(x: 0, y: 0, width: 800, height: 600), ref: 1, children: children)
    }

    @Test func silentContainersAreSkippedButTheirChildrenListed() {
        let tree = window([
            UINode(role: "AXGroup", frame: CGRect(x: 0, y: 0, width: 800, height: 500), ref: 2, children: [
                UINode(role: "AXButton", title: "Send", frame: CGRect(x: 700, y: 20, width: 60, height: 24), ref: 3),
                UINode(role: "AXTextArea", value: "Hello\nthere", frame: CGRect(x: 10, y: 60, width: 780, height: 400), ref: 4),
            ]),
        ])
        let (lines, omitted) = UITree.lines([tree])
        #expect(omitted == 0)
        #expect(lines.map(\.id) == ["e1", "e2", "e3"])
        #expect(lines.map(\.role) == ["AXWindow", "AXButton", "AXTextArea"])
        #expect(lines.map(\.ref) == [1, 3, 4])
        #expect(lines[1].depth == 1, "below the window, not below the silent group")
        #expect(lines[2].value == "Hello there", "one line")
    }

    @Test func invisibleBranchesAreLeftOut() {
        let tree = window([
            UINode(role: "AXGroup", frame: CGRect(x: 0, y: 0, width: 0, height: 0), children: [
                UINode(role: "AXButton", title: "Hidden", frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            ]),
            UINode(role: "AXButton", title: "Shown", frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
        ])
        #expect(UITree.lines([tree]).lines.compactMap(\.title) == ["Untitled", "Shown"])
    }

    @Test func unlabelledDecorationIsLeftOutButUnlabelledControlsStay() {
        let tree = window([
            UINode(role: "AXImage", frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            UINode(role: "AXTextField", frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            UINode(role: "AXStaticText", value: "Subject", frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
        ])
        #expect(UITree.lines([tree]).lines.map(\.role) == ["AXWindow", "AXTextField", "AXStaticText"])
    }

    @Test func aHugeTreeStopsAtTheLimitAndSaysHowManyMore() {
        let buttons = (0..<50).map { UINode(role: "AXButton", title: "B\($0)", frame: CGRect(x: 0, y: 0, width: 5, height: 5)) }
        let (lines, omitted) = UITree.lines([window(buttons)], limit: 10)
        #expect(lines.count == 10)
        #expect(omitted == 41)
        #expect(UITree.text(lines, omitted: omitted).hasSuffix("… 41 more elements not shown."))
    }

    @Test func longValuesAreCutAndTheTextReadsWell() {
        let tree = window([
            UINode(role: "AXButton", title: "OK", frame: CGRect(x: 10, y: 20, width: 30, height: 40), enabled: false),
            UINode(role: "AXTextArea", value: String(repeating: "x", count: 500), frame: CGRect(x: 0, y: 0, width: 5, height: 5)),
        ])
        let (lines, omitted) = UITree.lines([tree], valueLength: 20)
        #expect(lines[2].value == String(repeating: "x", count: 20) + "…")
        let text = UITree.text(lines, omitted: omitted)
        #expect(text.contains(#"  e2 AXButton "OK" (10,20 30×40) disabled"#))
    }

    // MARK: Screenshots

    func picture(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func aRetinaScreenIsScaledToFitAndNeverUp() {
        #expect(ScreenshotJPEG.size(width: 3024, height: 1964) == (1600, 1039))
        #expect(ScreenshotJPEG.size(width: 1000, height: 3000) == (533, 1600))
        #expect(ScreenshotJPEG.size(width: 800, height: 600) == (800, 600))
    }

    @Test func theScreenshotIsAJPEGWithinBudget() throws {
        let encoded = try #require(ScreenshotJPEG.encode(picture(width: 3200, height: 2000)))
        #expect(encoded.width == 1600)
        #expect(encoded.height == 1000)
        #expect(encoded.data.prefix(2) == Data([0xFF, 0xD8]))
        #expect(encoded.data.count < 400_000, "the spec's per-screenshot budget")
    }

    // MARK: Keys

    @Test func combinationsReadTheWayPeopleWriteThem() {
        #expect(KeyCombo.normalised("cmd+shift+4") == KeyCombo(modifiers: ["cmd", "shift"], key: "4"))
        #expect(KeyCombo.normalised("Command+S") == KeyCombo(modifiers: ["cmd"], key: "s"))
        #expect(KeyCombo.normalised("⌘↩") == KeyCombo(modifiers: ["cmd"], key: "return"))
        #expect(KeyCombo.normalised("ctrl+alt+delete") == KeyCombo(modifiers: ["option", "control"], key: "delete"))
        #expect(KeyCombo.normalised("Return") == KeyCombo(modifiers: [], key: "return"))
        #expect(KeyCombo.normalised("esc") == KeyCombo(modifiers: [], key: "escape"))
        #expect(KeyCombo.normalised("shift") == KeyCombo(modifiers: [], key: "shift"))
        #expect(KeyCombo.normalised("cmd++") == KeyCombo(modifiers: ["cmd"], key: "+"))
    }

    @Test func aCombinationBecomesKeyDownAndUpWithItsFlags() throws {
        let events = try #require(KeyCodes.events(for: KeyCombo(modifiers: ["cmd", "shift"], key: "4")))
        #expect(events.count == 2)
        #expect(events[0].getIntegerValueField(.keyboardEventKeycode) == 21)
        #expect(events[0].type == .keyDown)
        #expect(events[1].type == .keyUp)
        #expect(events[0].flags.contains(.maskCommand))
        #expect(events[0].flags.contains(.maskShift))
        #expect(!events[0].flags.contains(.maskAlternate))
        #expect(KeyCodes.events(for: KeyCombo(modifiers: [], key: "return"))?.first?.getIntegerValueField(.keyboardEventKeycode) == 36)
        #expect(KeyCodes.events(for: KeyCombo(modifiers: [], key: "hyperdrive")) == nil)
    }

    @Test func typingCarriesTheTextInChunksWithoutSplittingAnEmoji() {
        let text = String(repeating: "a", count: 19) + "😀" + "bc"
        let events = KeyCodes.typingEvents(for: text)
        var typed = ""
        for event in events where event.type == .keyDown {
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 32)
            event.keyboardGetUnicodeString(maxStringLength: 32, actualStringLength: &length, unicodeString: &buffer)
            typed += String(utf16CodeUnits: buffer, count: length)
        }
        #expect(typed == text)
        #expect(events.count == 4, "two chunks, down and up each")
    }

    @Test func appsAreFoundByNameOrBundleID() {
        let safari = RunningApp(name: "Safari", bundleID: "com.apple.Safari", pid: 1)
        #expect(safari.isNamed("safari"))
        #expect(safari.isNamed("Safari.app"))
        #expect(safari.isNamed("com.apple.safari"))
        #expect(!safari.isNamed("Mail"))
    }
}
