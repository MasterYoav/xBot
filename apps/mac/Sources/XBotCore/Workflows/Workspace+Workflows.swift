import Foundation
import XBotBrain

/// Jev workflows: making, running and scheduling them. A run is one chat tagged with its workflow
/// (kept out of the sidebar and the tabs, like an automation's): each agent step is a turn in it,
/// so the CLI's session carries context from step to step, and each Jev step adds a notice saying
/// what Jev answered and where the run went. See docs/superpowers/specs/2026-10-12-jev-workflows-design.md.
extension Workspace {
    /// Each step runs at most this many times per run, so a go-to loop always ends.
    public static let maxStepRuns = 5

    // MARK: The feature

    /// The Workflows page, its sidebar row and the phone's entry: only while Jev Workflows is on.
    public var showsWorkflows: Bool { jev.workflowsEnabled }

    /// On, but no key in Settings › AI: the page says so, with a button to Settings.
    public var jevKeyMissing: Bool { jev.workflowsEnabled && jevOverride == nil && !jev.hasKey }

    /// Jev, when it may be asked: never while Jev Workflows is off.
    var jevDecider: (any JevDecider)? {
        guard jev.workflowsEnabled else { return nil }
        return jevOverride ?? jev.client()
    }

    public func showWorkflows() { page = .workflows }

    // MARK: Editing

    public func workflow(_ id: UUID) -> Workflow? { workflows.first { $0.id == id } }

    /// A new one, not saved until `saveWorkflow`.
    public func newWorkflow() -> Workflow {
        Workflow(
            name: String(localized: "New workflow"), trigger: .manual, steps: [],
            harness: availableHarnesses.contains(.claude) ? .claude : (availableHarnesses.first ?? .claude),
            sortIndex: (workflows.map(\.sortIndex).max() ?? 0) + 1
        )
    }

    public func saveWorkflow(_ workflow: Workflow) {
        attempt { try store.save(workflow) }
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            // The last run belongs to the store (runs claim it there), not to the editor's copy.
            var saved = workflow
            saved.lastRunAt = workflows[index].lastRunAt
            workflows[index] = saved
        } else {
            workflows.append(workflow)
        }
    }

    public func deleteWorkflow(_ id: UUID) {
        attempt { try store.deleteWorkflow(id) }
        workflows.removeAll { $0.id == id }
        for chat in chats where chat.workflowID == id { update(chat.id) { $0.workflowID = nil } }
    }

    /// Newest first.
    public func runs(ofWorkflow id: UUID) -> [Chat] {
        chats.filter { $0.workflowID == id }.sorted { $0.createdAt > $1.createdAt }
    }

    public func isRunning(workflow id: UUID) -> Bool { runs(ofWorkflow: id).contains { isRunning($0.id) } }

    /// Why it can't run now, in a sentence; nil when it can.
    public func workflowBlockedReason(_ workflow: Workflow) -> String? {
        if !jev.workflowsEnabled { return String(localized: "Jev Workflows is off in Settings › AI.") }
        if isRunning(workflow: workflow.id) { return String(localized: "It's running already.") }
        if !workflow.hasWork { return String(localized: "It has no agent step to do yet.") }
        if workflow.needsJev, jevDecider == nil { return JevError.noKey.sentence }
        for step in workflow.steps {
            if case .agent(let agent) = step.kind, case .fixed(let choice) = agent.brain, brains[choice.harness] == nil {
                return String(localized: "\(choice.harness.displayName) isn't installed on this Mac.")
            }
        }
        if availableHarnesses.isEmpty { return String(localized: "No agent is installed on this Mac.") }
        return nil
    }

    // MARK: Running

    /// Starts a run now: a new chat tagged with the workflow, then its steps in order. Nil when it
    /// can't run (`workflowBlockedReason`) or another xBot claimed it first.
    @discardableResult
    public func runWorkflow(_ id: UUID, input: String = "", at now: Date = .now) -> Chat? {
        reloadWorkflows()
        guard let workflow = workflow(id), workflowBlockedReason(workflow) == nil,
              attempt({ try store.claimWorkflow(id, expected: workflow.lastRunAt, at: now) }) == true
        else { return nil }
        if let index = workflows.firstIndex(where: { $0.id == id }) { workflows[index].lastRunAt = now }

        let start = Self.startingBrain(workflow, installed: availableHarnesses)
        let title = workflow.name + " · " + now.formatted(date: .abbreviated, time: .shortened)
        let chat = Chat(projectID: workflow.projectID, title: title, harness: start.harness, model: start.model,
                        mode: .editFiles, effort: start.effort, workflowID: id)
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty { save(ChatMessage(chatID: chat.id, role: .user, parts: [.text(input)])) }
        live[chat.id] = []
        launch(chat.id) { w, token in await w.driveWorkflow(workflow, input: input, chatID: chat.id, token: token) }
        return self.chat(chat.id)
    }

    /// Runs whatever is due, while Jev Workflows is on. Returns the ones started.
    @discardableResult
    public func runDueWorkflows(at now: Date = .now) -> [UUID] {
        guard jev.workflowsEnabled else { return [] }
        reloadWorkflows()
        return workflows.filter { $0.isDue(at: now) }.compactMap { runWorkflow($0.id, at: now)?.workflowID }
    }

    /// Takes the last runs from the store: the background helper may have run something.
    func reloadWorkflows() {
        guard let saved = attempt({ try store.workflows() }) else { return }
        workflows = saved
    }

    private static func startingBrain(_ workflow: Workflow, installed: [HarnessKind]) -> BrainChoice {
        for step in workflow.steps {
            if case .agent(let agent) = step.kind, case .fixed(let choice) = agent.brain { return choice }
        }
        return installed.contains(workflow.harness) ? workflow.fallback : BrainChoice(harness: installed.first ?? workflow.harness)
    }

    // MARK: Driving

    private func driveWorkflow(_ workflow: Workflow, input: String, chatID: UUID, token: UUID) async {
        var index = 0
        var runsPerStep: [UUID: Int] = [:]
        var outputs: [(title: String, text: String)] = []
        while workflow.steps.indices.contains(index) {
            guard turns[chatID]?.token == token else { return }
            let step = workflow.steps[index]
            runsPerStep[step.id, default: 0] += 1
            if runsPerStep[step.id]! > Self.maxStepRuns {
                note(String(localized: "“\(step.title)” would run more than \(Self.maxStepRuns) times, so the run stopped."),
                     failed: true, in: chatID)
                return
            }
            switch step.kind {
            case .agent(let agent):
                guard let output = await runAgentStep(step, agent, workflow: workflow, input: input, outputs: outputs,
                                                      chatID: chatID, token: token) else { return }
                outputs.append((step.title, output))
                index += 1

            case .jev(let jevStep):
                guard let decider = jevDecider else {
                    note(Self.jevNotice(step, jevStep, said: JevError.noKey.sentence, then: String(localized: "The run stopped.")),
                         failed: true, in: chatID)
                    return
                }
                let state = WorkflowState.assemble(input: input, outputs: outputs)
                let answer: JevAnswer?
                do {
                    answer = try await decider.ask(state: state, questions: [JevStep.name: jevStep.jevQuestion()]).answers[JevStep.name]
                } catch {
                    guard turns[chatID]?.token == token else { return }
                    // Fail closed: a gate Jev couldn't answer is a no, and a route or a score has
                    // nowhere to go. Never a silent guess.
                    note(Self.jevNotice(step, jevStep, said: String(localized: "Jev couldn't answer. \(error.sentence)"),
                                        then: String(localized: "The run stopped.")), failed: true, in: chatID)
                    return
                }
                guard turns[chatID]?.token == token else { return }
                guard let outcome = answer.flatMap(jevStep.decide) else {
                    note(Self.jevNotice(step, jevStep, said: String(localized: "Jev's answer didn't fit the question."),
                                        then: String(localized: "The run stopped.")), failed: true, in: chatID)
                    return
                }
                let (next, destination) = resolve(outcome.target, from: index, in: workflow)
                let text = "\(Self.kindLabel(jevStep)): \(jevStep.question) — \(outcome.said) → \(destination)"
                note(text, failed: false, in: chatID)
                outputs.append((step.title, text))
                guard let next else { return }
                index = next
            }
        }
    }

    /// One agent step as a turn in the run's chat. The step's output, or nil when the run ends here
    /// (the turn failed, was stopped, or its agent isn't installed).
    private func runAgentStep(
        _ step: WorkflowStep, _ agent: AgentStep, workflow: Workflow, input: String,
        outputs: [(title: String, text: String)], chatID: UUID, token: UUID
    ) async -> String? {
        var lead: [Part] = []
        var choice: BrainChoice
        switch agent.brain {
        case .fixed(let fixed):
            choice = fixed
        case .jevPicks:
            let picked = await pickBrain(for: agent.prompt, fallback: workflow.fallback)
            guard turns[chatID]?.token == token else { return nil }
            choice = picked.choice
            lead.append(.notice(picked.notice))
        }
        if brains[choice.harness] == nil, case .jevPicks = agent.brain, let first = availableHarnesses.first {
            choice = BrainChoice(harness: first)
        }
        guard let brain = brains[choice.harness] else {
            note(String(localized: "\(choice.harness.displayName) isn't installed on this Mac, so the run stopped at “\(step.title)”."),
                 failed: true, in: chatID)
            return nil
        }
        let mode = agent.mode
        update(chatID) { chat in
            // A session belongs to its CLI: another CLI starts its own.
            if chat.harness != choice.harness { chat.sessionID = nil }
            chat.harness = choice.harness
            chat.model = choice.model
            chat.effort = choice.effort
            chat.mode = mode
        }
        guard let chat = chat(chatID) else { return nil }
        save(ChatMessage(chatID: chatID, role: .user, parts: [.text(agent.prompt)]))
        let prompt = chat.sessionID == nil
            ? Self.firstPrompt(step, agent, workflow: workflow, state: WorkflowState.assemble(input: input, outputs: outputs))
            : agent.prompt
        let request = TurnRequest(prompt: prompt, directory: directory(for: chat), model: turnModel(for: chat),
                                  mode: chat.mode, resumeID: chat.sessionID, effort: chat.effort)
        live[chatID] = lead
        for await event in events(brain, request, harness: choice.harness) {
            guard turns[chatID]?.token == token else { return nil }
            receive(event, in: chatID, turn: token)
        }
        guard turns[chatID]?.token == token else { return nil }
        let parts = finishLiveReply(chatID)
        if !parts.isEmpty { save(ChatMessage(chatID: chatID, role: .assistant, parts: parts)) }
        update(chatID) { $0.updatedAt = .now }
        if parts.contains(where: { if case .failure = $0 { true } else { false } }) {
            note(String(localized: "“\(step.title)” failed, so the run stopped."), failed: true, in: chatID)
            return nil
        }
        return parts.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n\n")
    }

    /// The reply in progress, taken out of `live` and closed: a tool with no result never finished.
    private func finishLiveReply(_ chatID: UUID) -> [Part] {
        let parts = (live[chatID] ?? []).map { part -> Part in
            guard case .tool(var tool) = part, tool.output == nil else { return part }
            tool.output = ""
            tool.isError = true
            return .tool(tool)
        }
        live[chatID] = []
        return parts
    }

    /// Asks Jev for the CLI, model and effort; falls back, saying why, when Jev can't answer.
    func pickBrain(for task: String, fallback: BrainChoice) async -> (choice: BrainChoice, notice: String) {
        let installed = availableHarnesses
        let fallback = installed.contains(fallback.harness) || installed.isEmpty ? fallback : BrainChoice(harness: installed[0])
        let available = modelOptions
        let options = JevPick.options(installed: installed, models: { (kind: HarnessKind) -> [ModelOption] in available[kind] ?? [] })
        guard let decider = jevDecider else {
            return (fallback, String(localized: "Jev couldn't choose (\(JevError.noKey.sentence)) \(fallback.harness.displayName) is answering."))
        }
        do {
            let response = try await decider.ask(state: task, questions: JevPick.questions(for: options))
            if let pick = JevPick.decide(response, options: options) { return (pick.choice, pick.sentence) }
            return (fallback, String(localized: "Jev's choice wasn't one of the agents here, so \(fallback.harness.displayName) is answering."))
        } catch {
            return (fallback, String(localized: "Jev couldn't choose. \(error.sentence) \(fallback.harness.displayName) is answering."))
        }
    }

    /// Where a target leads: the index to run next (nil: the run ends) and its name for the notice.
    private func resolve(_ target: StepTarget, from index: Int, in workflow: Workflow) -> (Int?, String) {
        switch target {
        case .stop:
            return (nil, String(localized: "stop"))
        case .next:
            let next = index + 1
            return workflow.steps.indices.contains(next) ? (next, workflow.steps[next].title) : (nil, String(localized: "done"))
        case .step(let id):
            guard let found = workflow.steps.firstIndex(where: { $0.id == id }) else {
                return (nil, String(localized: "a step that's gone, so the run stopped"))
            }
            return (found, workflow.steps[found].title)
        }
    }

    /// A message of its own in the run: what Jev decided, or why the run stopped.
    private func note(_ text: String, failed: Bool, in chatID: UUID) {
        save(ChatMessage(chatID: chatID, role: .assistant, parts: [failed ? .failure(text) : .notice(text)]))
        update(chatID) { $0.updatedAt = .now }
    }

    static func kindLabel(_ step: JevStep) -> String {
        switch step.decision {
        case .gate: String(localized: "Gate")
        case .route: String(localized: "Route")
        case .score: String(localized: "Score")
        }
    }

    private static func jevNotice(_ step: WorkflowStep, _ jev: JevStep, said: String, then: String) -> String {
        "\(kindLabel(jev)): \(jev.question) — \(said) \(then)"
    }

    /// A step whose CLI has no session yet (the first, or one Jev moved to another CLI) gets what
    /// it needs to know: the workflow, the run so far, and its step.
    static func firstPrompt(_ step: WorkflowStep, _ agent: AgentStep, workflow: Workflow, state: String) -> String {
        var text = """
            You're doing one step of the workflow "\(workflow.name)" for the person who owns this Mac. \
            Do this step without stopping to ask; they set it up to run by itself.


            """
        if !state.isEmpty { text += "The run so far:\n\n\(state)\n\n" }
        text += "The step, \"\(step.title)\":\n\n\(agent.prompt)"
        return text
    }
}
