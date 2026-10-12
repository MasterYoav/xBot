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
        tab(app, "Chats")
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
        tab(app, "Projects")
        let demo = app.buttons["Demo: files and changes"].firstMatch
        if !demo.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        demo.tap()
        let readme = app.staticTexts["README.md"].firstMatch
        XCTAssertTrue(readme.waitForExistence(timeout: 15), "No files")
        XCTAssertTrue(app.staticTexts["notes"].exists)
        attach(app, "1 files")
        readme.tap()
        // A Markdown file opens as a document.
        XCTAssertTrue(app.descendants(matching: .any)["markdown-document"].firstMatch.waitForExistence(timeout: 15), "The file didn't open")
        attach(app, "2 file")
        back(app)

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
        back(app)
        back(app)
        app.buttons["Add a project…"].firstMatch.tap()
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
        back(app)
        let mine = app.staticTexts["Phone note"].firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 15), "The new note isn't listed")

        // Open it again: the text came back from the Mac.
        mine.tap()
        XCTAssertTrue(NSPredicate(format: "value CONTAINS 'Written on the phone.'").wait(for: app.textViews["note-text"], timeout: 15))
        back(app)

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
        let agent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Agent' AND label != 'Agents'")).firstMatch
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
        back(app)
        if app.navigationBars.buttons.element(boundBy: 0).exists, !app.staticTexts["Phone automation"].exists {
            back(app)
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

        tab(app, "Agents")
        func crewCard(_ name: String) -> XCUIElement {
            app.buttons.matching(identifier: "crew-card").matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        }
        XCTAssertTrue(crewCard("HeadMaster").waitForExistence(timeout: 15), "No crew")
        // Leftovers from an earlier run.
        while crewCard("Testy").waitForExistence(timeout: 2) {
            crewCard("Testy").press(forDuration: 1.2)
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
        let agent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Agent' AND label != 'Agents'")).firstMatch
        XCTAssertTrue(agent.waitForExistence(timeout: 5))
        agent.tap()
        app.buttons["Codex"].firstMatch.tap()
        attach(app, "2 hire")
        app.buttons["save-crew"].tap()

        let card = crewCard("Testy")
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
        back(app)
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

    /// Terminal: a shell on the Mac from the sidebar, and one in a project's folder.
    /// Writes /tmp/xbot-term-42 and /tmp/xbot-term-pwd on the Mac (checked by the runner).
    func testTerminal() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))

        app.buttons["Terminal"].firstMatch.tap()
        if !app.descendants(matching: .any)["terminal"].firstMatch.waitForExistence(timeout: 15) { print("HIERARCHY\n" + app.debugDescription) }
        sleep(3)
        app.descendants(matching: .any)["terminal"].firstMatch.tap()
        app.typeText("echo ok > /tmp/xbot-term-$((6*7)); ls -G /\n")
        sleep(2)
        attach(app, "1 home shell")
        back(app)

        // In a project: from its ⋯ menu.
        tab(app, "Projects")
        let demo = app.buttons["Demo: files and changes"].firstMatch
        for _ in 0..<5 where !demo.isHittable { app.swipeUp() }
        demo.tap()
        app.buttons["Project actions"].tap()
        app.buttons["Terminal here"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["terminal"].firstMatch.waitForExistence(timeout: 15))
        sleep(3)
        app.descendants(matching: .any)["terminal"].firstMatch.tap()
        app.typeText("pwd > /tmp/xbot-term-pwd; git status\n")
        sleep(2)
        attach(app, "2 project shell")
    }

    /// Profile, then the phone's appearance set to dark.
    func testProfileAndAppearance() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        // Places is a sideways row; Profile is the last circle in it.
        let profile = app.buttons["Profile"].firstMatch
        for _ in 0..<3 where !profile.isHittable { app.swipeUp() }
        for _ in 0..<3 where !profile.isHittable { app.buttons["Notes"].firstMatch.swipeLeft() }
        profile.tap()
        // Stats, or (on a Mac with no agent history) the empty state; plan usage either way.
        let shown = app.staticTexts.matching(NSPredicate(format: "label == 'Lifetime tokens' OR label == 'No agent history yet'")).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 90), "No stats")
        sleep(1)
        attach(app, "1 profile")
        app.swipeUp()
        attach(app, "2 profile lower")
        back(app)
        for _ in 0..<3 where !app.buttons["Settings"].firstMatch.isHittable { app.swipeDown() }
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Dark"].firstMatch.tap()
        sleep(1)
        attach(app, "3 dark settings")
        app.buttons["Match the device"].firstMatch.tap()
    }

    /// The Agents world follows the Mac: choose Sky Realm here (the runner checks the Mac's setting).
    func testWorldSync() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        tab(app, "Agents")
        app.buttons["Sky Realm"].firstMatch.tap()
        let menu = app.buttons["world-menu"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'Sky Realm'").wait(for: menu, timeout: 10))
        sleep(3)
        attach(app, "1 sky realm")
    }

    /// Home's plan board with 1, 3 and 6 providers (made up), and with the Mac's real ones.
    func testUsageBoardShapes() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        for count in [0, 1, 3, 6] {
            let app = XCUIApplication()
            app.launchEnvironment["XBOT_PAIR_URL"] = link
            if count > 0 { app.launchEnvironment["XBOT_FAKE_USAGE"] = "\(count)" }
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["usage-board"].firstMatch.waitForExistence(timeout: 20))
            sleep(2)
            attach(app, "board \(count)")
            app.swipeUp()
            sleep(1)
            attach(app, "board \(count) legend")
            app.terminate()
        }
    }

    /// Suggested agents: hire one with a tap, see them on the crew, let them go.
    func testSuggestedAgents() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        tab(app, "Agents")
        let hire = app.buttons["Hire Scout"].firstMatch
        for _ in 0..<3 where !hire.isHittable { app.swipeUp() }
        sleep(1)
        attach(app, "1 suggestions")
        hire.tap()
        let card = app.buttons.matching(identifier: "crew-card").matching(NSPredicate(format: "label BEGINSWITH 'Scout'")).firstMatch
        for _ in 0..<3 where !card.exists { app.swipeDown() }
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Scout wasn't hired")
        XCTAssertFalse(app.buttons["Hire Scout"].exists, "Still suggested")
        sleep(2)
        attach(app, "2 hired")
        card.press(forDuration: 1.2)
        app.buttons["Let go"].firstMatch.tap()
        XCTAssertTrue(NSPredicate(format: "exists == false").wait(for: card, timeout: 10))
    }

    /// A Markdown file opens as a document; editing a paragraph saves Markdown on the Mac.
    func testMarkdownEditing() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        tab(app, "Projects")
        app.buttons["Demo: files and changes"].firstMatch.tap()
        app.staticTexts["GUIDE.md"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["markdown-document"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Getting started"].waitForExistence(timeout: 5), "Not shown as a document")
        sleep(1)
        attach(app, "1 document")
        // Tick a task.
        app.buttons["Not done"].firstMatch.tap()
        sleep(1)
        // Edit the heading "Setup".
        app.staticTexts["Setup"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText(" and pairing")
        attach(app, "2 editing")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Saved on the Mac"].waitForExistence(timeout: 10), "Not saved")
        attach(app, "3 saved")
        // As code, from the file's menu.
        app.buttons["File actions"].tap()
        app.buttons["Show as code"].firstMatch.tap()
        sleep(1)
        attach(app, "4 as code")
    }

    /// Settings › Appearance › Accent colour: Blue, then back.
    func testAccentColour() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        app.buttons["Settings"].firstMatch.tap()
        let blue = app.buttons["Blue"].firstMatch
        for _ in 0..<3 where !blue.isHittable { app.swipeUp() }
        attach(app, "1 settings")
        blue.tap()
        sleep(1)
        attach(app, "2 blue settings")
        app.buttons["Done"].firstMatch.tap()
        sleep(2)
        attach(app, "3 blue home")
        tab(app, "Chats")
        sleep(1)
        attach(app, "4 blue chats")
        tab(app, "Home")
        app.buttons["Settings"].firstMatch.tap()
        for _ in 0..<3 where !app.buttons["Orchid"].firstMatch.isHittable { app.swipeUp() }
        app.buttons["Orchid"].firstMatch.tap()
    }

    /// The redesign: every tab, the world, a place from Home, someone on the crew.
    func testGlassTour() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        sleep(3)
        attach(app, "1 home")
        app.swipeUp()
        sleep(1)
        attach(app, "2 home scrolled")
        app.swipeDown(); app.swipeDown()

        tab(app, "Chats")
        sleep(1)
        attach(app, "3 chats")
        tab(app, "Agents")
        XCTAssertTrue(app.descendants(matching: .any)["world-stage"].firstMatch.waitForExistence(timeout: 10))
        sleep(3)
        attach(app, "4 world")
        tab(app, "Projects")
        sleep(1)
        attach(app, "5 projects")
        tab(app, "Home")
        app.buttons["Notes"].firstMatch.tap()
        sleep(2)
        attach(app, "6 notes cover")
        app.buttons["Close"].firstMatch.tap()
        sleep(1)
        tab(app, "Agents")
        sleep(1)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'HeadMaster'")).firstMatch.tap()
        sleep(2)
        attach(app, "7 member")
    }

    /// The redesign, pushed screens and sheets: a chat, a project, new chat, settings.
    func testGlassTourInside() throws {
        let link = try XCTUnwrap(ProcessInfo.processInfo.environment["XBOT_PAIR_URL"], "Set TEST_RUNNER_XBOT_PAIR_URL")
        let app = XCUIApplication()
        app.launchEnvironment["XBOT_PAIR_URL"] = link
        app.launch()
        let status = app.descendants(matching: .any)["link-status"].firstMatch
        XCTAssertTrue(NSPredicate(format: "label CONTAINS 'same Wi-Fi'").wait(for: status, timeout: 20))
        tab(app, "Chats")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Renamed'")).firstMatch.tap()
        sleep(2)
        attach(app, "1 chat")
        back(app)
        tab(app, "Projects")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Demo'")).firstMatch.tap()
        sleep(2)
        attach(app, "2 project")
        back(app)
        tab(app, "Home")
        app.buttons["New chat"].firstMatch.tap()
        sleep(1)
        attach(app, "3 new chat")
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Settings"].firstMatch.tap()
        sleep(1)
        attach(app, "4 settings")
    }

    /// The visible screen's back (or close) button. Other tabs keep their bars in the tree, so
    /// "the first navigation bar button" can be on a tab that isn't showing.
    private func back(_ app: XCUIApplication) {
        let backButton = app.navigationBars.buttons["BackButton"].firstMatch
        if backButton.exists && backButton.isHittable { backButton.tap(); return }
        let close = app.buttons["Close"].firstMatch
        if close.exists && close.isHittable { close.tap(); return }
        app.navigationBars.buttons.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minX < 80 }?.tap()
    }

    /// Taps a tab, unfolding the bar first if scrolling folded it.
    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name].firstMatch
        for _ in 0..<4 where !button.exists { app.swipeDown() }
        button.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        // Also straight to a folder on the Mac, when asked: result bundles sometimes never get written.
        if let folder = ProcessInfo.processInfo.environment["XBOT_SHOTS"] {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(filePath: folder).appending(path: "\(name).png"))
        }
    }
}

extension NSPredicate {
    /// Waits until the element's (or query's) state matches.
    func wait(for object: Any, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: self, object: object)], timeout: timeout) == .completed
    }
}
