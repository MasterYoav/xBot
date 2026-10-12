import Foundation
import Testing
import XBotBrain
import XBotRemote
@testable import XBotCore

/// Workflows from the phone: listed with Run now, only while the Mac has Jev Workflows on.
@MainActor @Suite(.serialized) struct RemoteWorkflowsTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    func setUp(enabled: Bool) async -> (Workspace, RemoteHost, FakeLink) {
        let defaults = freshDefaults()
        let settings = JevSettings(defaults: defaults, keys: MemoryJevKeys("k"))
        settings.workflowsEnabled = enabled
        let brain = SequenceBrain([], fallback: [.text("done"), .done])
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] }, codexModels: { [] },
                          defaults: defaults, jev: settings, jevDecider: ScriptedJev([]))
        await w.refreshHarnesses()
        let host = RemoteHost(workspace: w, macName: "Mac", macID: UUID(), localInterval: .milliseconds(20), cloudInterval: .milliseconds(200))
        let link = FakeLink()
        host.attach(link)
        return (w, host, link)
    }

    func availability(_ link: FakeLink) -> [Bool] {
        link.sent.compactMap { if case .workflowsAvailable(let on) = $0 { on } else { nil } }
    }

    var plain: Workflow {
        Workflow(name: "Nightly", trigger: .schedule(.daily(hour: 2, minute: 0)), steps: [
            WorkflowStep(title: "Build", kind: .agent(AgentStep(prompt: "Build it", brain: .fixed(BrainChoice(harness: .claude))))),
        ])
    }

    @Test func thePhoneIsToldWhetherWorkflowsAreOn() async throws {
        let (w, host, link) = await setUp(enabled: false)
        defer { withExtendedLifetime(host) {} }
        #expect(availability(link) == [false])
        w.jev.workflowsEnabled = true
        let end = Date.now.addingTimeInterval(20)
        while availability(link).last != true, Date.now < end { try await Task.sleep(for: .milliseconds(10)) }
        #expect(availability(link) == [false, true])
    }

    @Test func listAndRunNow() async throws {
        let (w, host, link) = await setUp(enabled: true)
        defer { withExtendedLifetime(host) {} }
        let tests = RemoteProjectsTests()
        let flow = plain
        w.saveWorkflow(flow)

        let list = UUID()
        link.say(.listWorkflows(requestID: list))
        guard case .workflows(_, let listed, let available) = await tests.answer(link, list) else { Issue.record("no list"); return }
        #expect(available)
        #expect(listed.map(\.name) == ["Nightly"])
        #expect(listed.first?.stepTitles == ["Build"])
        #expect(listed.first?.schedule == .daily(hour: 2, minute: 0))
        #expect(listed.first?.blocked == nil)

        let run = UUID()
        link.say(.runWorkflow(requestID: run, workflowID: flow.id, input: "v2"))
        guard case .reply(_, let ok, _, let chatID) = await tests.answer(link, run), ok, let chatID else {
            Issue.record("not run"); return
        }
        #expect(w.chat(chatID)?.workflowID == flow.id)
        #expect(w.messages(in: chatID).first?.parts == [.text("v2")])
        // A run is the workflow's history, not a chat in the phone's list.
        try await Task.sleep(for: .milliseconds(100))
        let listedChats = link.sent.flatMap { message -> [UUID] in
            switch message {
            case .workspace(_, let chats, _): chats.map(\.id)
            case .chat(let chat): [chat.id]
            default: []
            }
        }
        #expect(!listedChats.contains(chatID))
        for _ in 0..<2000 where w.isRunning(chatID) { try await Task.sleep(for: .milliseconds(2)) }
    }

    @Test func aRunThatCantStartIsRefusedWithTheReason() async throws {
        let (w, host, link) = await setUp(enabled: true)
        defer { withExtendedLifetime(host) {} }
        let tests = RemoteProjectsTests()
        var empty = plain
        empty.steps = []
        w.saveWorkflow(empty)
        let run = UUID()
        link.say(.runWorkflow(requestID: run, workflowID: empty.id, input: nil))
        guard case .reply(_, let ok, let reason, _) = await tests.answer(link, run) else { Issue.record("no answer"); return }
        #expect(!ok)
        #expect(reason == w.workflowBlockedReason(empty))

        let gone = UUID()
        link.say(.runWorkflow(requestID: gone, workflowID: UUID(), input: nil))
        guard case .reply(_, false, let why, _) = await tests.answer(link, gone) else { Issue.record("no answer"); return }
        #expect(why?.isEmpty == false)
    }

    @Test func whileOffTheListIsEmptyAndRunsAreRefused() async throws {
        let (w, host, link) = await setUp(enabled: false)
        defer { withExtendedLifetime(host) {} }
        let tests = RemoteProjectsTests()
        let flow = plain
        w.saveWorkflow(flow)
        let list = UUID()
        link.say(.listWorkflows(requestID: list))
        guard case .workflows(_, let listed, let available) = await tests.answer(link, list) else { Issue.record("no list"); return }
        #expect(!available && listed.isEmpty)
        let run = UUID()
        link.say(.runWorkflow(requestID: run, workflowID: flow.id, input: nil))
        guard case .reply(_, let ok, _, _) = await tests.answer(link, run) else { Issue.record("no answer"); return }
        #expect(!ok)
        #expect(w.runs(ofWorkflow: flow.id).isEmpty)
    }
}
