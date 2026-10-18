import CoreGraphics
import Foundation
import Testing
import XBotTools
@testable import XBotCore

/// The Mac, scripted: no real click, key or screenshot.
@MainActor
final class FakeMac: MacControlling {
    var allowed: Set<MacPermission> = [.accessibility, .screenRecording]
    var guides: [MacPermission] = []
    var apps = [
        RunningApp(name: "TextEdit", bundleID: "com.apple.TextEdit", pid: 10, isFrontmost: true),
        RunningApp(name: "Safari", bundleID: "com.apple.Safari", pid: 11),
    ]
    var windowTitles: [Int32: String] = [10: "Untitled"]
    var tree: [UINode] = []
    var pressed: [Int] = []
    var clicks: [CGPoint] = []
    var typed: [String] = []
    var keys: [KeyCombo] = []
    var scrolls: [(Double, Double)] = []
    var opened: [String] = []
    var quit: [String] = []
    var shotOf: [String?] = []

    func isAllowed(_ permission: MacPermission) -> Bool { allowed.contains(permission) }
    func showGuide(for permission: MacPermission) { guides.append(permission) }
    func runningApps() -> [RunningApp] { apps }
    func frontWindowTitle(of app: RunningApp) -> String? { windowTitles[app.pid] }

    func screenshot(of app: RunningApp?) async throws -> CGImage {
        shotOf.append(app?.name)
        let context = CGContext(data: nil, width: 3200, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3200, height: 2000))
        return context.makeImage()!
    }

    func uiTree(of app: RunningApp) async throws -> [UINode] { tree }
    func press(ref: Int) -> Bool { pressed.append(ref); return true }
    func frame(ref: Int) -> CGRect? { nil }
    func click(at point: CGPoint) { clicks.append(point) }
    func type(_ text: String) { typed.append(text) }
    func press(_ combo: KeyCombo) -> Bool { keys.append(combo); return KeyCodes.code(for: combo.key) != nil }
    func scroll(dx: Double, dy: Double, at point: CGPoint?) { scrolls.append((dx, dy)) }
    func open(_ target: String) async -> String? { opened.append(target); return nil }
    func quit(_ app: RunningApp) -> Bool { quit.append(app.name); return true }

    func front(_ name: String, bundleID: String, title: String) {
        apps = [RunningApp(name: name, bundleID: bundleID, pid: 20, isFrontmost: true)] + apps.map { var a = $0; a.isFrontmost = false; return a }
        windowTitles[20] = title
    }
}

@MainActor
@Suite struct ToolHostTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "toolhost-\(UUID().uuidString)")

    @MainActor struct Rig {
        let workspace: Workspace
        let host: ToolHost
        let mac: FakeMac
        let brain: ScriptedBrain
        let chat: Chat
        let token: String

        func call(_ tool: String, _ arguments: JSONValue = [:]) async -> ToolResult {
            await host.handle(ToolCall(token: token, tool: tool, arguments: arguments))
        }

        /// Answers the first approval that turns up, as the person would.
        func answerNextApproval(allow: Bool, by device: String = "Mac") async {
            for _ in 0..<2000 where workspace.approvals.pending.isEmpty { await Task.yield() }
            if let pending = workspace.approvals.pending.first {
                workspace.approvals.answer(pending.approval.id, allow: allow, by: device)
            }
        }
    }

    func rig(agent: String? = "HeadMaster", approvalTimeout: Duration = .seconds(30)) async throws -> Rig {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let brain = ScriptedBrain([.textDelta("ok"), .done])
        let defaults = UserDefaults(suiteName: "toolhost-\(UUID().uuidString)")!
        let w = Workspace(store: .inMemory(), inbox: folder.appending(path: "Inbox"), discover: { [.claude: brain] },
                          defaults: defaults)
        await w.refreshHarnesses()
        w.experience = ExperienceStore(folder: folder.appending(path: "Experience"))
        let mac = FakeMac()
        let host = ToolHost(workspace: w, mac: mac, socketPath: "/tmp/unused.sock",
                            executable: URL(filePath: "/Applications/xBot.app/Contents/MacOS/XBot"),
                            imagesFolder: folder.appending(path: "Images"),
                            appearance: Appearance(defaults: defaults, folder: folder),
                            antigravity: AntigravityMCP(defaults: defaults))
        host.approvalTimeout = approvalTimeout
        w.toolHost = host
        let member = agent.flatMap { name in w.agents.first { $0.name == name } }
        let chat: Chat
        if let member {
            chat = try #require(w.talk(to: member.id))
        } else {
            chat = try #require(w.newChat(in: nil))
        }
        let token = host.open(chatID: chat.id, agentID: member?.id).token
        return Rig(workspace: w, host: host, mac: mac, brain: brain, chat: chat, token: token)
    }

    func settle(_ w: Workspace) async {
        for _ in 0..<500 where w.isRunningAnyTurn { await Task.yield() }
    }

    // MARK: Tokens

    @Test func anUnknownTokenIsRefused() async throws {
        let r = try await rig()
        let result = await r.host.handle(ToolCall(token: "forged", tool: "xbot_crew", arguments: [:]))
        #expect(result.isError)
        #expect(result.text.contains("isn't one xBot"))
    }

    @Test func aClosedTokenIsRefused() async throws {
        let r = try await rig()
        r.host.close(r.token)
        #expect(await r.call("xbot_crew").isError)
    }

    @Test func anUnknownToolIsAnError() async throws {
        let r = try await rig()
        #expect(await r.call("xbot_fly").isError)
    }

    // MARK: xBot

    @Test func theCrewIsListed() async throws {
        let r = try await rig()
        let text = await r.call("xbot_crew").text
        for name in ["HeadMaster", "Forge", "Hawk", "Quill"] { #expect(text.contains(name)) }
        #expect(text.contains("Claude Code"))
    }

    @Test func projectsAreAddedAndListed() async throws {
        let r = try await rig()
        let project = folder.appending(path: "Site")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let added = await r.call("xbot_add_project", ["path": .string(project.path)])
        #expect(!added.isError)
        #expect(r.workspace.projects.map(\.name) == ["Site"])
        #expect(await r.call("xbot_projects").text.contains("Site"))
        let missing = await r.call("xbot_add_project", ["path": "/no/such/folder"])
        #expect(missing.isError)
    }

    @Test func aChatIsStartedWithACrewMemberAndRead() async throws {
        let r = try await rig()
        let result = await r.call("xbot_start_chat", ["agent": "forge", "message": "Build the login page"])
        #expect(!result.isError, "\(result.text)")
        let started = try #require(r.workspace.chats.first { $0.agentID == r.workspace.agents.first { $0.name == "Forge" }?.id })
        #expect(result.text.contains(started.id.uuidString))
        await settle(r.workspace)
        #expect(r.brain.requests.withLock { $0.contains { $0.prompt == "Build the login page" } })
        let listed = await r.call("xbot_chats").text
        #expect(listed.contains(started.id.uuidString))
        let read = await r.call("xbot_read_chat", ["id": .string(started.id.uuidString)]).text
        #expect(read.contains("Build the login page"))
        #expect(read.contains("ok"))
        #expect(await r.call("xbot_start_chat", ["agent": "Nobody", "message": "x"]).isError)
    }

    @Test func hiringAddsAMember() async throws {
        let r = try await rig()
        let result = await r.call("xbot_hire", ["name": "Pixel", "role": "Designer", "instructions": "Draw."])
        #expect(!result.isError)
        let pixel = try #require(r.workspace.agents.first { $0.name == "Pixel" })
        #expect(pixel.role == "Designer")
        #expect(pixel.instructions == "Draw.")
        #expect(await r.call("xbot_hire", ["name": "Pixel", "role": "Again"]).isError, "names are unique")
    }

    @Test func handingOffStartsTheMemberAndSaysSoHere() async throws {
        let r = try await rig()
        let result = await r.call("xbot_hand_off", ["to": "Forge", "task": "Fix the build"])
        #expect(!result.isError, "\(result.text)")
        await settle(r.workspace)
        #expect(r.brain.requests.withLock { $0.contains { $0.prompt.hasSuffix("Fix the build") } })
        let notices = r.workspace.messages(in: r.chat.id).flatMap(\.parts).compactMap { if case .notice(let n) = $0 { n } else { nil } }
        #expect(notices.contains { $0.hasPrefix(Handoff.handedPrefix("Forge")) })
    }

    @Test func automationsAreSavedListedAndRun() async throws {
        let r = try await rig()
        let saved = await r.call("xbot_save_automation", ["name": "Morning", "steps": ["Read the news", "Summarise it"],
                                                          "schedule": "weekdays", "time": "08:30"])
        #expect(!saved.isError, "\(saved.text)")
        let automation = try #require(r.workspace.automations.first { $0.name == "Morning" })
        #expect(automation.steps.map(\.text) == ["Read the news", "Summarise it"])
        #expect(automation.trigger == .schedule(.weekdays(hour: 8, minute: 30)))
        #expect(await r.call("xbot_automations").text.contains("Morning"))
        let ran = await r.call("xbot_run_automation", ["id": "morning"])
        #expect(!ran.isError, "\(ran.text)")
        #expect(!r.workspace.runs(of: automation.id).isEmpty)
        let renamed = await r.call("xbot_save_automation", ["id": .string(automation.id.uuidString), "name": "Mornings",
                                                            "steps": ["Read the news"]])
        #expect(!renamed.isError)
        #expect(r.workspace.automations.map(\.name).contains("Mornings"))
        #expect(r.workspace.automations.count == 1)
    }

    @Test func notesAreWrittenAndListed() async throws {
        let r = try await rig()
        let project = folder.appending(path: "Notes project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        r.workspace.addProject(at: project)
        let written = await r.call("xbot_write_note", ["project": "Notes project", "name": "Release plan", "text": "Ship on Friday."])
        #expect(!written.isError, "\(written.text)")
        let file = project.appending(path: "notes/release-plan.md")
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Release plan\n\nShip on Friday.")
        _ = await r.call("xbot_write_note", ["project": "Notes project", "name": "Release plan", "text": "# Release plan\n\nShip Monday."])
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Release plan\n\nShip Monday.", "replaced, not doubled")
        let listed = await r.call("xbot_notes", ["project": "Notes project"]).text
        #expect(listed.contains("Release plan"))
        #expect(listed.contains("release-plan.md"))
    }

    @Test func settingsWorldAndAppearance() async throws {
        let r = try await rig()
        #expect(!(await r.call("xbot_set_world", ["name": "moonbase"])).isError)
        #expect(r.workspace.workplace == .moonbase)
        #expect(await r.call("xbot_set_world", ["name": "Mars"]).isError)
        #expect(!(await r.call("xbot_set_appearance", ["theme": "light", "app_icon": "plum"])).isError)
        #expect(r.host.appearance.theme == .light)
        #expect(r.host.appearance.appIcon == .plum)
        let settings = await r.call("xbot_settings").text
        #expect(settings.contains("moonbase"))
        #expect(settings.contains("light"))
    }

    @Test func rememberingKeepsTheLessonAndShowsIt() async throws {
        let r = try await rig()
        let result = await r.call("xbot_remember", ["cue": "When Xcode asks to trust a package", "lesson": "Choose Trust and Enable",
                                                    "confidence": "high", "evidence": "The build went on after it."])
        #expect(!result.isError, "\(result.text)")
        let head = try #require(r.workspace.headMaster)
        #expect(r.workspace.experience.lessons(of: head.id).map(\.lesson) == ["Choose Trust and Enable"])
        let lessons = r.workspace.messages(in: r.chat.id).flatMap(\.parts).compactMap { if case .lesson(let l) = $0 { l } else { nil } }
        #expect(lessons.count == 1)
        #expect(await r.call("xbot_lessons").text.contains("Choose Trust and Enable"))
        #expect(await r.call("xbot_remember", ["cue": "x", "lesson": "y", "confidence": "sure", "evidence": "z"]).isError)
    }

    @Test func rememberingNeedsACrewMember() async throws {
        let r = try await rig(agent: nil)
        #expect(await r.call("xbot_remember", ["cue": "x", "lesson": "y", "confidence": "low", "evidence": "z"]).isError)
    }

    @Test func askingWaitsForThePersonsNextMessage() async throws {
        let r = try await rig()
        async let answer = r.call("xbot_ask", ["question": "Which colour?", "options": ["Red", "Blue"]])
        for _ in 0..<2000 where !r.workspace.questions.isWaiting(in: r.chat.id) { await Task.yield() }
        #expect(r.workspace.questions.isWaiting(in: r.chat.id))
        let asked = r.workspace.messages(in: r.chat.id).last?.parts
        #expect(asked?.contains { if case .text(let t) = $0 { t.contains("Which colour?") && t.contains("Blue") } else { false } } == true)
        #expect(r.workspace.send("Blue, please", in: r.chat.id))
        let result = await answer
        #expect(result.text.contains("Blue, please"))
        #expect(!r.workspace.isRunning(r.chat.id), "the reply answered the question; it didn't start a turn")
        #expect(r.workspace.messages(in: r.chat.id).last?.parts == [.text("Blue, please")])
    }

    @Test func anUnansweredQuestionSaysSo() async throws {
        let r = try await rig()
        r.host.questionTimeout = .milliseconds(50)
        let result = await r.call("xbot_ask", ["question": "Still there?"])
        #expect(result.text.contains("didn't answer"))
        #expect(!r.workspace.questions.isWaiting(in: r.chat.id))
    }

    // MARK: Mac control

    @Test func aScreenshotIsSavedPostedAndReturnedAsAnImage() async throws {
        let r = try await rig()
        let result = await r.call("mac_screenshot")
        #expect(!result.isError, "\(result.text)")
        guard case .image(let jpeg, let mime)? = result.content.first else { Issue.record("no image"); return }
        #expect(mime == "image/jpeg")
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))
        let image = try #require(r.workspace.messages(in: r.chat.id).flatMap(\.parts).compactMap { if case .image(let i) = $0 { i } else { nil } }.first)
        #expect(image.width == 1600)
        #expect(image.height == 1000)
        #expect(FileManager.default.fileExists(atPath: image.path))
        #expect(image.path.hasPrefix(folder.appending(path: "Images").path))
        _ = await r.call("mac_screenshot", ["app": "safari"])
        #expect(r.mac.shotOf == [nil, "Safari"])
    }

    @Test func withoutScreenRecordingTheGuideOpensAndTheAgentIsTold() async throws {
        let r = try await rig()
        r.mac.allowed = [.accessibility]
        let result = await r.call("mac_screenshot")
        #expect(result.isError)
        #expect(result.text.hasPrefix(ToolHost.permissionSentencePrefix))
        #expect(r.mac.guides == [.screenRecording])
    }

    @Test func withoutAccessibilityNothingIsClickedAndTheGuideOpens() async throws {
        let r = try await rig()
        r.mac.allowed = [.screenRecording]
        for (tool, arguments) in [("mac_ui", JSONValue.object([:])), ("mac_click", ["x": 1, "y": 2]), ("mac_type", ["text": "hi"]),
                                  ("mac_keys", ["combo": "return"]), ("mac_scroll", ["dy": 10])] {
            let result = await r.call(tool, arguments)
            #expect(result.text.hasPrefix(ToolHost.permissionSentencePrefix), "\(tool)")
        }
        #expect(r.mac.clicks.isEmpty && r.mac.typed.isEmpty && r.mac.keys.isEmpty)
        #expect(r.mac.guides.allSatisfy { $0 == .accessibility })
    }

    @Test func theScreenIsReadAndAnElementPressedByItsID() async throws {
        let r = try await rig()
        r.mac.tree = [UINode(role: "AXWindow", title: "Untitled", frame: CGRect(x: 0, y: 0, width: 400, height: 300), ref: 1, children: [
            UINode(role: "AXButton", title: "Bold", frame: CGRect(x: 10, y: 10, width: 20, height: 20), ref: 7),
        ])]
        let read = await r.call("mac_ui").text
        #expect(read.contains(#"e2 AXButton "Bold""#))
        #expect(!(await r.call("mac_click", ["element": "e2"])).isError)
        #expect(r.mac.pressed == [7])
        #expect(await r.call("mac_click", ["element": "e99"]).isError)
    }

    @Test func typingKeysScrollingAndOpeningInTextEditJustHappen() async throws {
        let r = try await rig()
        #expect(!(await r.call("mac_type", ["text": "Hello"])).isError)
        #expect(!(await r.call("mac_keys", ["combo": "cmd+s"])).isError)
        #expect(!(await r.call("mac_click", ["x": 100, "y": 200])).isError)
        #expect(!(await r.call("mac_scroll", ["dy": 120])).isError)
        #expect(!(await r.call("mac_open", ["target": "https://example.com"])).isError)
        #expect(r.mac.typed == ["Hello"])
        #expect(r.mac.keys == [KeyCombo(modifiers: ["cmd"], key: "s")])
        #expect(r.mac.clicks == [CGPoint(x: 100, y: 200)])
        #expect(r.mac.opened == ["https://example.com"])
        #expect(r.workspace.approvals.pending.isEmpty)
        #expect(await r.call("mac_keys", ["combo": "cmd+warp"]).isError)
        let apps = await r.call("mac_apps").text
        #expect(apps.contains("TextEdit") && apps.contains("com.apple.Safari"))
    }

    // MARK: Approvals

    @Test func quittingAsksAndRunsWhenAllowed() async throws {
        let r = try await rig()
        async let result = r.call("mac_quit", ["app": "Safari"])
        await r.answerNextApproval(allow: true, by: "iPhone")
        #expect(!(await result).isError)
        #expect(r.mac.quit == ["Safari"])
        // The card is in the chat, rewritten with the answer.
        let card = try #require(r.workspace.messages(in: r.chat.id).flatMap(\.parts).compactMap { if case .approval(let a) = $0 { a } else { nil } }.first)
        #expect(card.summary == "HeadMaster wants to quit Safari")
        #expect(card.state == .allowed)
        #expect(card.answeredBy == "iPhone")
    }

    @Test func aRefusedActionDoesNotRunAndTheAgentIsTold() async throws {
        let r = try await rig()
        r.mac.front("Mail", bundleID: "com.apple.mail", title: "New Message")
        async let result = r.call("mac_keys", ["combo": "cmd+return"])
        await r.answerNextApproval(allow: false)
        let answer = await result
        #expect(answer.text == ToolHost.notAllowed)
        #expect(r.mac.keys.isEmpty)
        let card = r.workspace.messages(in: r.chat.id).flatMap(\.parts).compactMap { if case .approval(let a) = $0 { a } else { nil } }.first
        #expect(card?.state == .refused)
        #expect(card?.risk == "send")
    }

    @Test func anExpiredApprovalCountsAsNo() async throws {
        let r = try await rig(approvalTimeout: .milliseconds(50))
        let result = await r.call("mac_quit", ["app": "Safari"])
        #expect(result.text == ToolHost.notAllowed)
        #expect(r.mac.quit.isEmpty)
    }

    @Test func withNoPhoneTheMacIsAlerted() async throws {
        let r = try await rig()
        var alerted: [ApprovalPart] = []
        r.host.phoneAttached = { false }
        r.host.alertMac = { approval, _ in alerted.append(approval) }
        async let result = r.call("mac_quit", ["app": "Safari"])
        await r.answerNextApproval(allow: false)
        _ = await result
        #expect(alerted.count == 1)
        r.host.phoneAttached = { true }
        async let again = r.call("mac_quit", ["app": "Safari"])
        await r.answerNextApproval(allow: false)
        _ = await again
        #expect(alerted.count == 1, "the phone has it")
    }

    @Test func clickingSendFoundThroughTheScreenAsks() async throws {
        let r = try await rig()
        r.mac.front("Mail", bundleID: "com.apple.mail", title: "New Message")
        r.mac.tree = [UINode(role: "AXWindow", title: "New Message", frame: CGRect(x: 0, y: 0, width: 400, height: 300), ref: 1, children: [
            UINode(role: "AXButton", title: "Send", frame: CGRect(x: 10, y: 10, width: 20, height: 20), ref: 9),
        ])]
        _ = await r.call("mac_ui")
        async let result = r.call("mac_click", ["element": "e2"])
        await r.answerNextApproval(allow: true)
        #expect(!(await result).isError)
        #expect(r.mac.pressed == [9])
    }

    // MARK: The hook

    @Test func theHookAllowsSafeCommandsAndAsksForRiskyOnes() async throws {
        let r = try await rig()
        let safe = await r.host.handle(ToolCall(token: r.token, tool: "Bash", arguments: ["command": "git status"], hook: true))
        #expect(!safe.isError)
        async let push = r.host.handle(ToolCall(token: r.token, tool: "Bash", arguments: ["command": "git push"], hook: true))
        await r.answerNextApproval(allow: false)
        let refused = await push
        #expect(refused.isError)
        #expect(refused.text == ToolHost.notAllowed)
        async let again = r.host.handle(ToolCall(token: r.token, tool: "Bash", arguments: ["command": "git push"], hook: true))
        await r.answerNextApproval(allow: true)
        #expect(!(await again).isError)
    }
}
