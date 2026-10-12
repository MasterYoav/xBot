import Foundation
import Synchronization
import Testing
import XBotBrain
@testable import XBotCore

/// Jev, scripted: each call takes the next answer (or error); none left is offline.
final class ScriptedJev: JevDecider {
    let script: Mutex<[Result<JevResponse, JevError>]>
    let asked = Mutex<[(state: String, questions: [String: JevQuestion])]>([])

    init(_ script: [Result<JevResponse, JevError>]) { self.script = Mutex(script) }

    var calls: Int { asked.withLock { $0.count } }

    func ask(state: String, questions: [String: JevQuestion]) async throws(JevError) -> JevResponse {
        asked.withLock { $0.append((state, questions)) }
        let next = script.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        switch next {
        case .success(let response): return response
        case .failure(let error): throw error
        case nil: throw .offline
        }
    }

    static func noul(_ p: Double) -> Result<JevResponse, JevError> {
        .success(JevResponse(model: "jev", answers: [JevStep.name: .noul(p)]))
    }

    static func choice(_ key: String, _ confidence: Double = 0.9) -> Result<JevResponse, JevError> {
        .success(JevResponse(model: "jev", answers: [JevStep.name: .choice(key, probabilities: [:], confidence: confidence)]))
    }

    static func score(_ score: Double) -> Result<JevResponse, JevError> {
        .success(JevResponse(model: "jev", answers: [JevStep.name: .score(score, legend: [:], probabilities: [:], confidence: 0.6)]))
    }
}

/// The workflow engine, with scripted brains and a scripted Jev.
@MainActor @Suite struct WorkflowRunTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "workflow-\(UUID().uuidString)")

    func workspace(_ brains: [HarnessKind: any Brain], jev: ScriptedJev?, enabled: Bool = true, key: String? = "k",
                   store: Store = .inMemory()) async -> Workspace {
        let defaults = freshDefaults()
        let settings = JevSettings(defaults: defaults, keys: MemoryJevKeys(key))
        settings.workflowsEnabled = enabled
        let w = Workspace(store: store, inbox: inbox, discover: { brains }, codexModels: { [] }, defaults: defaults,
                          jev: settings, jevDecider: jev)
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace) async {
        for _ in 0..<5000 where !w.turns.isEmpty { try? await Task.sleep(for: .milliseconds(2)) }
    }

    func agent(_ title: String, _ prompt: String, brain: StepBrain = .fixed(BrainChoice(harness: .claude)),
               mode: PermissionMode = .editFiles) -> WorkflowStep {
        WorkflowStep(title: title, kind: .agent(AgentStep(prompt: prompt, brain: brain, mode: mode)))
    }

    func jev(_ title: String, _ question: String, _ decision: JevStep.Decision) -> WorkflowStep {
        WorkflowStep(title: title, kind: .jev(JevStep(question: question, decision: decision)))
    }

    func notices(_ w: Workspace, _ chatID: UUID) -> [String] {
        w.messages(in: chatID).flatMap(\.parts).compactMap { if case .notice(let n) = $0 { n } else { nil } }
    }

    func failures(_ w: Workspace, _ chatID: UUID) -> [String] {
        w.messages(in: chatID).flatMap(\.parts).compactMap { if case .failure(let f) = $0 { f } else { nil } }
    }

    func texts(_ w: Workspace, _ chatID: UUID, role: Role) -> [String] {
        w.messages(in: chatID).filter { $0.role == role }.flatMap(\.parts).compactMap { if case .text(let t) = $0 { t } else { nil } }
    }

    func run(_ w: Workspace, _ workflow: Workflow, input: String = "") async throws -> Chat {
        w.saveWorkflow(workflow)
        let chat = try #require(w.runWorkflow(workflow.id, input: input))
        await settle(w)
        return chat
    }

    // MARK: Agent steps

    @Test func agentStepsAreTurnsInOneRunChat() async throws {
        let brain = SequenceBrain([[.session("s1"), .text("Built."), .done], [.text("Tested."), .done]])
        let w = await workspace([.claude: brain], jev: ScriptedJev([]))
        let flow = Workflow(name: "Ship", trigger: .manual, steps: [agent("Build", "Build it"), agent("Test", "Test it", mode: .readOnly)])
        let chat = try await run(w, flow)
        #expect(w.chat(chat.id)?.workflowID == flow.id)
        #expect(w.runs(ofWorkflow: flow.id).map(\.id) == [chat.id])
        #expect(texts(w, chat.id, role: .user) == ["Build it", "Test it"])
        #expect(texts(w, chat.id, role: .assistant) == ["Built.", "Tested."])
        let requests = brain.requests.withLock { $0 }
        #expect(requests.count == 2)
        // The second step resumes the first's session: the CLI carries the context.
        #expect(requests[1].resumeID == "s1")
        #expect(requests[1].prompt == "Test it")
        #expect(requests[1].mode == .readOnly)
        #expect(requests[0].mode == .editFiles)
        #expect(requests[0].prompt.contains("Build it"))
    }

    @Test func theInputIsShownAndGivenToTheFirstStep() async throws {
        let brain = SequenceBrain([], fallback: [.text("ok"), .done])
        let w = await workspace([.claude: brain], jev: ScriptedJev([]))
        let chat = try await run(w, Workflow(name: "x", trigger: .manual, steps: [agent("A", "Do A")]), input: "Version 2.0")
        #expect(texts(w, chat.id, role: .user).first == "Version 2.0")
        #expect(brain.requests.withLock { $0.first?.prompt.contains("Version 2.0") } == true)
    }

    @Test func aFailedTurnStopsTheRun() async throws {
        let brain = SequenceBrain([[.failed("Not signed in.")]], fallback: [.text("never"), .done])
        let w = await workspace([.claude: brain], jev: ScriptedJev([]))
        let chat = try await run(w, Workflow(name: "x", trigger: .manual, steps: [agent("A", "a"), agent("B", "b")]))
        #expect(brain.requests.withLock { $0.count } == 1)
        #expect(failures(w, chat.id).last?.contains("“A”") == true)
        #expect(w.runFailed(chat.id))
    }

    // MARK: Gates

    @Test func aGateSaysWhatJevAnsweredAndGoesOn() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let scripted = ScriptedJev([ScriptedJev.noul(0.91)])
        let w = await workspace([.claude: brain], jev: scripted)
        let fix = agent("Fix it", "Fix the build")
        let flow = Workflow(name: "x", trigger: .manual, steps: [
            agent("Build", "Build"), jev("Failing?", "Is the build failing?", .gate(JevGate(yes: .next))), fix,
        ])
        let chat = try await run(w, flow)
        #expect(notices(w, chat.id).contains("Gate: Is the build failing? — yes (0.91) → Fix it"))
        #expect(texts(w, chat.id, role: .user) == ["Build", "Fix the build"])
    }

    @Test func aGateThatSaysNoStops() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let w = await workspace([.claude: brain], jev: ScriptedJev([ScriptedJev.noul(0.2)]))
        let flow = Workflow(name: "x", trigger: .manual, steps: [
            agent("Build", "Build"), jev("Failing?", "Is the build failing?", .gate(JevGate())), agent("Fix it", "Fix"),
        ])
        let chat = try await run(w, flow)
        #expect(notices(w, chat.id).contains("Gate: Is the build failing? — no (0.20) → stop"))
        #expect(brain.requests.withLock { $0.count } == 1)
    }

    @Test func aGateUsesItsThresholdAndGoesToAStep() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let w = await workspace([.claude: brain], jev: ScriptedJev([ScriptedJev.noul(0.6)]))
        let notify = agent("Notify", "Tell me")
        let flow = Workflow(name: "x", trigger: .manual, steps: [
            jev("Risky?", "Is it risky?", .gate(JevGate(threshold: 0.7, yes: .next, no: .step(notify.id)))),
            agent("Deploy", "Deploy"), notify,
        ])
        let chat = try await run(w, flow)
        #expect(texts(w, chat.id, role: .user) == ["Tell me"])
    }

    @Test func theStateIsTheInputAndEveryEarlierOutput() async throws {
        let brain = SequenceBrain([[.text("Built fine."), .done], [.text("2 tests failed."), .done]])
        let scripted = ScriptedJev([ScriptedJev.noul(0.1)])
        let w = await workspace([.claude: brain], jev: scripted)
        let flow = Workflow(name: "x", trigger: .manual, steps: [
            agent("Build", "b"), agent("Test", "t"), jev("Failing?", "Failing?", .gate(JevGate())),
        ])
        _ = try await run(w, flow, input: "Release 2.0")
        let state = try #require(scripted.asked.withLock { $0.first?.state })
        #expect(state == "Input:\nRelease 2.0\n\n## Build\nBuilt fine.\n\n## Test\n2 tests failed.")
    }

    // MARK: Routes and scores

    @Test func aRouteGoesToTheChosenStep() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let docs = agent("Docs", "Write docs")
        let code = agent("Code", "Fix code")
        let route = JevStep(question: "What next?", decision: .route([
            RouteOption(label: "Docs", target: .step(docs.id)), RouteOption(label: "Code", target: .step(code.id)),
        ]))
        guard case .choice(let options) = route.jevQuestion().kind else { Issue.record("no options"); return }
        let w = await workspace([.claude: brain], jev: ScriptedJev([ScriptedJev.choice(options[1].key, 0.88)]))
        let flow = Workflow(name: "x", trigger: .manual, steps: [WorkflowStep(title: "Route", kind: .jev(route)), docs, code])
        let chat = try await run(w, flow)
        #expect(texts(w, chat.id, role: .user) == ["Fix code"])
        #expect(notices(w, chat.id).contains("Route: What next? — Code (0.88) → Code"))
    }

    @Test func aScoreGoesWhereItsLevelSays() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let polish = agent("Polish", "Polish it")
        let w = await workspace([.claude: brain], jev: ScriptedJev([ScriptedJev.score(0.3)]))
        let flow = Workflow(name: "x", trigger: .manual, steps: [
            agent("Draft", "Draft it"),
            jev("Quality", "How good is it?", .score([ScoreLevel(label: "Poor", target: .step(polish.id)), ScoreLevel(label: "Good", target: .stop)])),
            agent("Skipped", "Never"), polish,
        ])
        let chat = try await run(w, flow)
        #expect(texts(w, chat.id, role: .user) == ["Draft it", "Polish it"])
    }

    // MARK: The loop guard

    @Test func aStepRunsAtMostFiveTimesPerRun() async throws {
        let brain = SequenceBrain([], fallback: [.text("again"), .done])
        let draft = agent("Draft", "Draft it")
        let scripted = ScriptedJev(Array(repeating: ScriptedJev.noul(0.9), count: 20))
        let w = await workspace([.claude: brain], jev: scripted)
        let flow = Workflow(name: "x", trigger: .manual, steps: [
            draft, jev("Again?", "Should it go again?", .gate(JevGate(yes: .step(draft.id), no: .stop))),
        ])
        let chat = try await run(w, flow)
        #expect(brain.requests.withLock { $0.count } == 5)
        #expect(failures(w, chat.id).last?.contains("5") == true)
        #expect(w.runFailed(chat.id))
        #expect(!w.isRunning(chat.id))
    }

    // MARK: Jev unreachable

    @Test func aGateFailsClosedWhenJevCantBeReached() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let w = await workspace([.claude: brain], jev: ScriptedJev([.failure(.rateLimited)]))
        let flow = Workflow(name: "x", trigger: .manual, steps: [
            jev("Failing?", "Is the build failing?", .gate(JevGate(yes: .next, no: .next))), agent("Deploy", "Deploy"),
        ])
        let chat = try await run(w, flow)
        #expect(brain.requests.withLock { $0.isEmpty })
        let last = try #require(failures(w, chat.id).last)
        #expect(last.contains(JevError.rateLimited.sentence))
        #expect(last.contains("stopped"))
    }

    @Test func aRouteStopsWhenJevCantBeReached() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let w = await workspace([.claude: brain], jev: ScriptedJev([.failure(.offline)]))
        let flow = Workflow(name: "x", trigger: .manual, steps: [
            jev("Route", "Where?", .route([RouteOption(label: "A"), RouteOption(label: "B")])), agent("A", "a"),
        ])
        _ = try await run(w, flow)
        #expect(brain.requests.withLock { $0.isEmpty })
    }

    @Test func jevPicksFallsBackToTheWorkflowsBrainWhenJevCantBeReached() async throws {
        let claude = SequenceBrain([], fallback: [.text("claude"), .done])
        let codex = SequenceBrain([], fallback: [.text("codex"), .done])
        let w = await workspace([.claude: claude, .codex: codex], jev: ScriptedJev([.failure(.overloaded)]))
        let flow = Workflow(name: "x", trigger: .manual, steps: [agent("A", "Do it", brain: .jevPicks)],
                            harness: .codex, model: "gpt-5", effort: .medium)
        let chat = try await run(w, flow)
        #expect(claude.requests.withLock { $0.isEmpty })
        let request = try #require(codex.requests.withLock { $0.first })
        #expect(request.model == "gpt-5")
        #expect(request.effort == .medium)
        #expect(notices(w, chat.id).contains { $0.contains(JevError.overloaded.sentence) })
    }

    // MARK: Jev picks

    @Test func jevsPickReachesTheTurn() async throws {
        let claude = SequenceBrain([], fallback: [.text("claude"), .done])
        let codex = SequenceBrain([], fallback: [.text("codex"), .done])
        let options = JevPick.options(installed: [.claude, .codex], models: { $0 == .claude ? Workspace.claudeModels : [] })
        let codexKey = try #require(options.first { $0.choice.harness == .codex }?.key)
        let scripted = ScriptedJev([.success(JevResponse(model: "jev", answers: [
            "brain": .choice(codexKey, probabilities: [:], confidence: 0.82),
            "effort": .score(0.1, legend: [:], probabilities: [:], confidence: 0.7),
        ]))])
        let w = await workspace([.claude: claude, .codex: codex], jev: scripted)
        let chat = try await run(w, Workflow(name: "x", trigger: .manual, steps: [agent("A", "Rename a variable", brain: .jevPicks)]))
        #expect(claude.requests.withLock { $0.isEmpty })
        #expect(codex.requests.withLock { $0.first?.effort } == .low)
        #expect(notices(w, chat.id).contains("Jev chose Codex, low effort (0.82)"))
        let asked = try #require(scripted.asked.withLock { $0.first })
        #expect(asked.state.contains("Rename a variable"))
        #expect(asked.questions["brain"] != nil && asked.questions["effort"] != nil)
    }

    // MARK: Guards, claims, schedules

    @Test func nothingRunsWhileTheToggleIsOff() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let scripted = ScriptedJev([ScriptedJev.noul(0.9)])
        let w = await workspace([.claude: brain], jev: scripted, enabled: false)
        let flow = Workflow(name: "x", trigger: .schedule(.hourly(minute: 0)), steps: [agent("A", "a")], createdAt: .distantPast)
        w.saveWorkflow(flow)
        #expect(w.runWorkflow(flow.id) == nil)
        #expect(w.runDueWorkflows().isEmpty)
        #expect(scripted.calls == 0)
        #expect(!w.showsWorkflows)
    }

    @Test func withoutAKeyAWorkflowThatAsksJevSaysSo() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let w = await workspace([.claude: brain], jev: nil, key: nil)
        let asks = Workflow(name: "x", trigger: .manual, steps: [agent("A", "a", brain: .jevPicks)])
        w.saveWorkflow(asks)
        #expect(w.workflowBlockedReason(asks) == JevError.noKey.sentence)
        #expect(w.runWorkflow(asks.id) == nil)
        #expect(w.showsWorkflows)
        #expect(w.jevKeyMissing)
        // One with only fixed agents needs no Jev.
        let plain = Workflow(name: "y", trigger: .manual, steps: [agent("A", "a")])
        #expect(w.workflowBlockedReason(plain) == nil)
    }

    /// The app and the background helper both tick on one library: whichever claims first runs it.
    @Test func aRunIsClaimedSoTheAppAndTheHelperNeverBothRunIt() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let store = Store.inMemory()
        let app = await workspace([.claude: brain], jev: ScriptedJev([]), store: store)
        let helper = await workspace([.claude: brain], jev: ScriptedJev([]), store: store)
        let made = Date(timeIntervalSince1970: 1_790_000_000)
        let flow = Workflow(name: "x", trigger: .schedule(.hourly(minute: 0)), steps: [agent("A", "a")], createdAt: made)
        app.saveWorkflow(flow)
        let now = made.addingTimeInterval(3 * 3600)
        #expect(app.runDueWorkflows(at: now) == [flow.id])
        #expect(helper.runDueWorkflows(at: now).isEmpty)
        // Nor is a run already going doubled.
        #expect(app.runWorkflow(flow.id) == nil)
        await settle(app)
        #expect(app.runs(ofWorkflow: flow.id).count == 1)
    }

    @Test func dueWorkflowsRunFromTheClock() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let w = await workspace([.claude: brain], jev: ScriptedJev([]))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let made = Date(timeIntervalSince1970: 1_790_000_000)
        let due = Workflow(name: "due", trigger: .schedule(.hourly(minute: 0)), steps: [agent("A", "a")], createdAt: made)
        let later = Workflow(name: "later", trigger: .schedule(.daily(hour: 3, minute: 0)), steps: [agent("A", "a")],
                             createdAt: made.addingTimeInterval(3600 * 24 * 365 * 10))
        let manual = Workflow(name: "manual", trigger: .manual, steps: [agent("A", "a")], createdAt: made)
        for f in [due, later, manual] { w.saveWorkflow(f) }
        let started = w.runDueWorkflows(at: made.addingTimeInterval(3 * 3600))
        #expect(started == [due.id])
        await settle(w)
        #expect(w.runDueWorkflows(at: made.addingTimeInterval(3 * 3600 + 60)).isEmpty)
    }

    @Test func runsStayOutOfTheSidebar() async throws {
        let brain = SequenceBrain([], fallback: [.text("out"), .done])
        let w = await workspace([.claude: brain], jev: ScriptedJev([]))
        let chat = try await run(w, Workflow(name: "x", trigger: .manual, steps: [agent("A", "a")]))
        let sidebar = SidebarModel(projects: w.projects, chats: w.chats, running: [])
        #expect(!sidebar.recent.contains { $0.id == chat.id })
    }
}
