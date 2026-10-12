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

    /// Projects: files, a file, new and trash, Changes with a diff, and adding a project.
    /// Needs the sandbox Mac's "Demo" project (a git repo with README.md and an untracked notes/)
    /// and a "Code/Scratchpad" folder in its home.
    func testProjects() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))

        // Files.
        let demo = app.buttons["Demo: files and changes"].firstMatch
        if !demo.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        demo.tap()
        let readme = app.staticTexts["README.md"].firstMatch
        XCTAssertTrue(readme.waitForExistence(timeout: 15), "No files")
        XCTAssertTrue(app.staticTexts["notes"].exists)
        attach(app, "1 files")
        readme.tap()
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 15), "The file didn't open")
        attach(app, "2 file")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // New file, then to the Trash.
        app.buttons["New"].tap()
        app.buttons["New File"].tap()
        let untitled = app.staticTexts["untitled"].firstMatch
        XCTAssertTrue(untitled.waitForExistence(timeout: 10), "No new file")
        untitled.swipeLeft()
        app.buttons["Trash"].firstMatch.tap()
        app.buttons["Move to Trash"].firstMatch.tap()
        XCTAssertTrue(NSPredicate(format: "exists == false").wait(for: untitled, timeout: 10), "Still there")

        // Changes, and a diff.
        app.buttons["Changes"].tap()
        let branch = app.staticTexts.matching(NSPredicate(format: "label == 'main' OR label == 'master'")).firstMatch
        XCTAssertTrue(branch.waitForExistence(timeout: 20), "No branch")
        let note = app.staticTexts["next-release.md"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        attach(app, "3 changes")
        note.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '+ '")).firstMatch.waitForExistence(timeout: 15), "No diff")
        attach(app, "4 diff")

        // Add a project from the Mac's folders.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        if app.navigationBars.buttons["Chats"].exists { app.navigationBars.buttons["Chats"].tap() }
        else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        app.buttons["New chat"].press(forDuration: 1.2)
        app.buttons["Add a project…"].tap()
        let code = app.staticTexts["Code"].firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15), "No Mac folders")
        code.tap()
        app.staticTexts["Scratchpad"].firstMatch.tap()
        let add = app.buttons["Add “Scratchpad” as a project"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        attach(app, "5 pick a folder")
        add.tap()
        XCTAssertTrue(app.staticTexts["Empty folder"].waitForExistence(timeout: 15), "The new project didn't open")
        attach(app, "6 added")
    }

    /// Notes: read one, write a new one (named after its title on the Mac), delete, undo, delete.
    func testNotes() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))

        app.buttons["Notes"].firstMatch.tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Project:'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        app.buttons["Demo"].firstMatch.tap()
        let existing = app.staticTexts["Next Release"].firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 15), "No notes")
        attach(app, "1 notes")

        // A new note.
        app.buttons["New note"].firstMatch.tap()
        let editor = app.textViews["note-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.typeText("# Phone note\nWritten on the phone.")
        sleep(3)
        attach(app, "2 writing")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let mine = app.staticTexts["Phone note"].firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 15), "The new note isn't listed")

        // Open it again: the text came back from the Mac.
        mine.tap()
        XCTAssertTrue(NSPredicate(format: "value CONTAINS 'Written on the phone.'").wait(for: app.textViews["note-text"], timeout: 15))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Delete, undo, delete.
        XCTAssertTrue(mine.waitForExistence(timeout: 10))
        mine.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 10))
        attach(app, "3 deleted")
        app.buttons["Undo"].tap()
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "Undo didn't bring it back")
        mine.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(NSPredicate(format: "exists == false").wait(for: mine, timeout: 10))
    }

    /// Automations: make one with a Codex step, run it now, see the run answer, delete it.
    func testAutomations() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))

        app.buttons["Automations"].firstMatch.tap()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 15), "No automations page")
        // Leftovers from an earlier run.
        for name in ["Phone automation", "New automation"] {
            let old = app.staticTexts[name].firstMatch
            while old.waitForExistence(timeout: 2) {
                old.swipeLeft()
                app.buttons["Delete"].firstMatch.tap()
                _ = NSPredicate(format: "exists == false").wait(for: old, timeout: 5)
            }
        }
        attach(app, "1 list")
        app.navigationBars.buttons["New automation"].firstMatch.tap()

        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        let current = (name.value as? String) ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "Phone automation\n")

        app.buttons["Add a step"].tap()
        let anything = app.buttons["Anything"].firstMatch
        XCTAssertTrue(anything.waitForExistence(timeout: 5))
        attach(app, "2 palette")
        anything.tap()
        let stepField = app.textFields["What to do"].firstMatch.exists ? app.textFields["What to do"].firstMatch : app.textViews["What to do"].firstMatch
        XCTAssertTrue(stepField.waitForExistence(timeout: 5))
        stepField.tap()
        stepField.typeText("Reply with exactly the word: pong. Don't use any tools.")
        app.buttons["Done"].firstMatch.tap()

        app.swipeUp()
        let agent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Agent'")).firstMatch
        XCTAssertTrue(agent.waitForExistence(timeout: 5))
        agent.tap()
        app.buttons["Codex"].firstMatch.tap()
        attach(app, "2b editor")

        app.buttons["Run now"].tap()
        // The agent's reply, not the prompt (which also says "pong").
        let pong = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] '\\W*pong\\W*'")).firstMatch
        XCTAssertTrue(pong.waitForExistence(timeout: 180), "The run didn't answer")
        attach(app, "3 run")

        // Back to the list: it's there, with its run; then delete it.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        if app.navigationBars.buttons.element(boundBy: 0).exists, !app.staticTexts["Phone automation"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let row = app.staticTexts["Phone automation"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        attach(app, "4 back")
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(NSPredicate(format: "exists == false").wait(for: row, timeout: 10))
    }

    /// Agents: the crew with sprites, hire someone on Codex, message them, let them go, undo, let go.
    func testAgents() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))

        app.buttons["Agents"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["HeadMaster"].firstMatch.waitForExistence(timeout: 15), "No crew")
        // Leftovers from an earlier run.
        while app.staticTexts["Testy"].firstMatch.waitForExistence(timeout: 2) {
            app.staticTexts["Testy"].firstMatch.press(forDuration: 1.2)
            app.buttons["Let go"].firstMatch.tap()
            sleep(2)
        }
        attach(app, "1 crew")

        app.buttons["Hire"].firstMatch.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        app.buttons["Shuffle the look"].tap()
        name.tap()
        name.typeText("Testy")
        app.textFields["Role, like “Writer”"].tap()
        app.textFields["Role, like “Writer”"].typeText("Tester\n")
        app.swipeUp()
        let agent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Agent'")).firstMatch
        XCTAssertTrue(agent.waitForExistence(timeout: 5))
        agent.tap()
        app.buttons["Codex"].firstMatch.tap()
        attach(app, "2 hire")
        app.buttons["save-crew"].tap()

        let card = app.staticTexts["Testy"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Not hired")
        card.tap()
        app.buttons["Message Testy"].tap()
        let text = app.textFields["talk-text"].exists ? app.textFields["talk-text"] : app.textViews["talk-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("Reply with exactly the word: pong. Don't use any tools.")
        app.navigationBars.buttons["Send"].tap()
        let pong = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] '\\W*pong\\W*'")).firstMatch
        XCTAssertTrue(pong.waitForExistence(timeout: 180), "Testy didn't answer")
        attach(app, "3 chat")

        // Back to Testy, let go, undo, let go.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let letGo = app.buttons["Let Testy go"]
        if !letGo.waitForExistence(timeout: 5) { app.swipeUp() }
        attach(app, "4 detail")
        letGo.tap()
        app.buttons["Let go"].firstMatch.tap()
        if !app.buttons["Undo"].waitForExistence(timeout: 10) { print("HIERARCHY\n" + app.debugDescription) }
        attach(app, "5 after let go")
        XCTAssertTrue(app.buttons["Undo"].exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Undo didn't bring Testy back")
        card.press(forDuration: 1.2)
        app.buttons["Let go"].firstMatch.tap()
        XCTAssertTrue(NSPredicate(format: "exists == false").wait(for: card, timeout: 10))
    }

    /// Abilities: the Mac's real catalog shows, each kind, and the plugin marketplace opens.
    func testAbilities() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        app.buttons["Abilities"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Plugins"].waitForExistence(timeout: 10))
        // The Mac asks the CLIs: wait for rows (sections are named after the agents).
        app.buttons["Skills"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'Codex' OR label == 'Claude Code'")).firstMatch.waitForExistence(timeout: 60), "No skills")
        attach(app, "1 skills")
        app.buttons["Plugins"].tap()
        sleep(1)
        attach(app, "2 plugins")
        app.buttons["Add"].tap()
        app.buttons["Browse plugins"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Install'")).firstMatch.waitForExistence(timeout: 90)
                      || app.staticTexts["Installed"].firstMatch.exists, "No marketplace")
        attach(app, "3 marketplace")
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
