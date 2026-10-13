import CoreGraphics
import Testing
@testable import XBotUI

@Suite struct GuideDockTests {
    /// Core Graphics measures from the top of the main screen; AppKit from the bottom.
    @Test func windowListBoundsAreFlippedIntoScreenCoordinates() {
        let flipped = GuideDock.cocoaRect(fromWindowList: CGRect(x: 100, y: 50, width: 700, height: 600), mainScreenHeight: 1000)
        #expect(flipped == CGRect(x: 100, y: 350, width: 700, height: 600))
    }

    @Test func thePanelSitsToTheRightOfSystemSettingsNearItsTop() {
        let settings = CGRect(x: 100, y: 300, width: 700, height: 600)
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let origin = GuideDock.origin(beside: settings, panel: CGSize(width: 260, height: 300), screen: screen)
        #expect(origin.x == 800 + GuideDock.gap)
        #expect(origin.y == 900 - GuideDock.topInset - 300)
    }

    @Test func withNoRoomOnTheRightItGoesLeft() {
        let settings = CGRect(x: 700, y: 300, width: 700, height: 600)
        let screen = CGRect(x: 0, y: 0, width: 1500, height: 1000)
        let origin = GuideDock.origin(beside: settings, panel: CGSize(width: 260, height: 300), screen: screen)
        #expect(origin.x == 700 - GuideDock.gap - 260)
    }

    @Test func itStaysOnTheScreen() {
        let settings = CGRect(x: 0, y: 0, width: 1500, height: 200)
        let screen = CGRect(x: 0, y: 0, width: 1500, height: 1000)
        let origin = GuideDock.origin(beside: settings, panel: CGSize(width: 260, height: 300), screen: screen)
        #expect(origin.x >= screen.minX && origin.x + 260 <= screen.maxX)
        #expect(origin.y >= screen.minY && origin.y + 300 <= screen.maxY)
    }

    @Test func systemSettingsIsFoundInTheWindowList() {
        let list: [[String: Any]] = [
            ["kCGWindowOwnerName": "Finder", "kCGWindowLayer": 0,
             "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 900, "Height": 900]],
            // Its menu-bar item: not the window.
            ["kCGWindowOwnerName": "System Settings", "kCGWindowLayer": 25,
             "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 30, "Height": 24]],
            ["kCGWindowOwnerName": "System Settings", "kCGWindowLayer": 0,
             "kCGWindowBounds": ["X": 200, "Y": 120, "Width": 715, "Height": 640]],
        ]
        #expect(GuideDock.settingsWindow(in: list) == CGRect(x: 200, y: 120, width: 715, height: 640))
        #expect(GuideDock.settingsWindow(in: Array(list.prefix(2))) == nil)
    }
}
