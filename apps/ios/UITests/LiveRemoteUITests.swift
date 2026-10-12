import XCTest

/// Live: drives the phone app against a running (debug) xBot on this Mac.
///   TEST_RUNNER_XBOT_PAIR_URL=<link from Settings › Devices> xcodebuild test -scheme XBotMobile …
final class LiveRemoteUITests: XCTestCase {
    func testNewChatRunsOnTheMac() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()

        // Connected directly.
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20), status.label)
        attach(app, "1 chats")

        // A new chat with Codex, read only.
        app.buttons["New chat"].tap()
        let field = app.descendants(matching: .any)["new-chat-text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Reply with exactly the word: pong")
        let agent = app.buttons["Agent"].exists ? app.buttons["Agent"] : app.staticTexts["Agent"]
        if agent.exists {
            agent.tap()
            let codex = app.buttons["Codex"].firstMatch
            if codex.waitForExistence(timeout: 3) { codex.tap() }
        }
        attach(app, "2 new chat")
        app.buttons["Send"].tap()

        // The reply arrives on the phone.
        let pong = app.staticTexts.containing(NSPredicate(format: "label ==[c] 'pong' OR label ==[c] 'pong.'")).firstMatch
        XCTAssertTrue(pong.waitForExistence(timeout: 120), "No reply from the Mac")
        attach(app, "3 reply")

        // A follow-up in the same chat.
        let composer = app.descendants(matching: .any)["composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Now reply with exactly the word: ping")
        app.buttons["Send"].tap()
        let ping = app.staticTexts.containing(NSPredicate(format: "label ==[c] 'ping' OR label ==[c] 'ping.'")).firstMatch
        XCTAssertTrue(ping.waitForExistence(timeout: 120), "No follow-up reply")
        attach(app, "4 follow-up")
    }

    /// Opens the newest chat and takes a picture (iPhone and iPad layouts).
    func testOpenChatLooksRight() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Reply with'")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["composer"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        attach(app, "open chat")
    }

    /// Chat management: rename, delete, undo, ask again.
    func testManageAChat() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))

        // Rename from the row's menu.
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Reply with'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1)
        app.buttons["Rename"].firstMatch.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        let name = "Renamed \(Int.random(in: 100...999))"
        field.typeText(name)
        app.alerts.buttons["Rename"].tap()
        let renamed = app.staticTexts[name]
        XCTAssertTrue(renamed.waitForExistence(timeout: 10), "The rename didn't come back from the Mac")
        attach(app, "1 renamed")

        // Delete with a swipe, then undo.
        renamed.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        if delete.waitForExistence(timeout: 3) { delete.tap() }
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[name].exists)
        attach(app, "2 deleted")
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10), "Undo didn't bring it back")
        attach(app, "3 undone")

        // Ask the last question again from the chat's menu.
        app.staticTexts[name].tap()
        // Every one-word answer (pong, ping) in the chat.
        let pongs = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] 'p[io]ng\\.?'"))
        XCTAssertTrue(pongs.firstMatch.waitForExistence(timeout: 15))
        let before = pongs.count
        app.buttons["Chat actions"].tap()
        app.buttons["Ask again"].tap()
        XCTAssertTrue(NSPredicate(format: "count > %d", before).wait(for: pongs, timeout: 120), "No second answer")
        attach(app, "4 asked again")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

extension NSPredicate {
    /// Waits until the element's (or query's) state matches.
    func wait(for object: Any, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: self, object: object)], timeout: timeout) == .completed
    }
}
