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

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

extension NSPredicate {
    /// Waits until the element's state matches.
    func wait(for element: XCUIElement, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: self, object: element)], timeout: timeout) == .completed
    }
}
