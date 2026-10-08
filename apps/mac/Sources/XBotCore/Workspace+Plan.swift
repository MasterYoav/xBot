import Foundation

/// Plan mode: one read-only planning turn answering in `PlanSchemas.plan`, a review the person can
/// edit, then one resumed turn per step answering in `PlanSchemas.step`, then a closing sentence.
/// xBot drives the loop, so it always knows which step is running. The plan is saved after every
/// change. See docs/superpowers/specs/2026-10-08-plan-mode-design.md.
extension Workspace {
    /// Past this many added steps an agent is looping, not finishing.
    public static let maxAddedSteps = 20

    public func setPlanMode(_ on: Bool, for id: UUID) { update(id) { $0.planMode = on } }

    public func setReviewPlan(_ on: Bool, for id: UUID) { update(id) { $0.reviewPlan = on } }

    /// The newest plan in a chat, with the message that holds it.
    public func latestPlan(in chatID: UUID) -> (messageID: UUID, plan: Plan)? {
        for message in messages(in: chatID).reversed() {
            if let plan = message.plan { return (message.id, plan) }
        }
        return nil
    }

    // MARK: Actions

    /// Runs the reviewed plan. Empty steps are dropped; a step whose title was edited shows that
    /// title while it runs, since its proposed -ing label no longer describes it.
    @discardableResult
    public func runPlan(_ messageID: UUID, in chatID: UUID, steps edited: [PlanStep]) -> Bool {
        guard !isRunning(chatID), let chat = chat(chatID), let brain = brains[chat.harness],
              let plan = storedPlan(messageID, in: chatID), plan.status == .review else { return false }
        let steps = edited.compactMap { step -> PlanStep? in
            var step = step
            step.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !step.title.isEmpty else { return nil }
            if plan.steps.first(where: { $0.id == step.id })?.title != step.title { step.active = step.title }
            return step
        }
        guard !steps.isEmpty else { return false }
        mutatePlan(messageID, in: chatID) { $0.steps = steps }
        planTurns[chatID] = messageID
        launch(chatID) { w, token in await w.driveSteps(brain, chatID: chatID, messageID: messageID, token: token) }
        return true
    }

    public func cancelPlan(_ messageID: UUID, in chatID: UUID) {
        mutatePlan(messageID, in: chatID) { plan in
            guard plan.status == .review else { return }
            plan.status = .stopped
        }
    }

    /// Asks for a plan again, in the same card.
    @discardableResult
    public func retryPlanning(_ messageID: UUID, in chatID: UUID) -> Bool {
        guard !isRunning(chatID), let chat = chat(chatID), let brain = brains[chat.harness],
              let plan = storedPlan(messageID, in: chatID) else { return false }
        mutatePlan(messageID, in: chatID) { $0 = Plan(prompt: plan.prompt, status: .drafting) }
        requestPlan(plan.prompt, chat: chat, brain: brain, messageID: messageID)
        return true
    }

    /// Carries on from where a stopped or halted plan left off.
    @discardableResult
    public func resumePlan(_ messageID: UUID, in chatID: UUID) -> Bool {
        guard !isRunning(chatID), let chat = chat(chatID), let brain = brains[chat.harness],
              let plan = storedPlan(messageID, in: chatID), plan.status == .stopped, plan.startedAt != nil
        else { return false }
        mutatePlan(messageID, in: chatID) { plan in
            for index in plan.steps.indices
            where plan.steps[index].status == .stopped || plan.steps[index].id == plan.haltedStepID {
                plan.steps[index] = PlanStep(id: plan.steps[index].id, title: plan.steps[index].title,
                                             active: plan.steps[index].active, added: plan.steps[index].added)
            }
            plan.haltedStepID = nil
        }
        planTurns[chatID] = messageID
        launch(chatID) { w, token in await w.driveSteps(brain, chatID: chatID, messageID: messageID, token: token) }
        return true
    }

    // MARK: Driving

    func startPlanning(_ prompt: String, chat: Chat, brain: any Brain) {
        let message = ChatMessage(chatID: chat.id, role: .assistant,
                                  parts: [.plan(Plan(prompt: prompt, status: .drafting))])
        save(message)
        requestPlan(prompt, chat: chat, brain: brain, messageID: message.id)
    }

    private func requestPlan(_ prompt: String, chat: Chat, brain: any Brain, messageID: UUID) {
        let request = TurnRequest(
            prompt: Self.planningPrompt(prompt), directory: directory(for: chat), model: turnModel(for: chat),
            mode: .readOnly, resumeID: chat.sessionID, effort: chat.effort, schema: PlanSchemas.plan, planning: true
        )
        let chatID = chat.id
        planTurns[chatID] = messageID
        launch(chatID) { w, token in
            await w.drivePlanning(brain, request, chatID: chatID, messageID: messageID, token: token)
            guard w.turns[chatID]?.token == token, w.chat(chatID)?.reviewPlan == false,
                  w.storedPlan(messageID, in: chatID)?.status == .review else { return }
            await w.driveSteps(brain, chatID: chatID, messageID: messageID, token: token)
        }
    }

    private func drivePlanning(
        _ brain: any Brain, _ request: TurnRequest, chatID: UUID, messageID: UUID, token: UUID
    ) async {
        var answer: String?
        for await event in brain.run(request) {
            guard turns[chatID]?.token == token else { return }
            switch event {
            case .session(let session): update(chatID) { $0.sessionID = session }
            case .structured(let json): answer = json
            case .textDelta(let text), .text(let text): mutatePlan(messageID, in: chatID) { $0.reply += text }
            case .failed(let reason): mutatePlan(messageID, in: chatID) { $0.problem = reason }
            case .toolCall, .toolResult: mutatePlan(messageID, in: chatID) { $0.investigation.apply(event, at: .now) }
            case .notice, .done: break
            }
        }
        guard turns[chatID]?.token == token else { return }
        mutatePlan(messageID, in: chatID) { plan in
            plan.investigation.finishUnfinished()
            if let answer = answer.flatMap(PlanAnswer.decode), !answer.steps.isEmpty, plan.problem == nil {
                plan.summary = answer.summary
                plan.note = answer.summary
                plan.steps = answer.steps.map { PlanStep(title: $0.title, active: $0.active) }
                plan.status = .review
            } else {
                plan.problem = plan.problem ?? String(localized: "The agent didn't return a plan.")
                plan.status = .stopped
            }
        }
    }

    private func driveSteps(_ brain: any Brain, chatID: UUID, messageID: UUID, token: UUID) async {
        mutatePlan(messageID, in: chatID) { plan in
            plan.status = .running
            plan.startedAt = plan.startedAt ?? .now
            plan.endedAt = nil
        }
        while let plan = storedPlan(messageID, in: chatID),
              let index = plan.steps.firstIndex(where: { $0.status == .pending }) {
            guard turns[chatID]?.token == token, let chat = chat(chatID) else { return }
            mutatePlan(messageID, in: chatID) { plan in
                plan.steps[index].status = .running
                plan.steps[index].startedAt = .now
            }
            let request = TurnRequest(
                prompt: Self.stepPrompt(plan.steps, index), directory: directory(for: chat), model: turnModel(for: chat),
                mode: chat.mode, resumeID: chat.sessionID, effort: chat.effort, schema: PlanSchemas.step
            )
            var answer: String?
            var failure: String?
            for await event in brain.run(request) {
                guard turns[chatID]?.token == token else { return }
                switch event {
                case .session(let session): update(chatID) { $0.sessionID = session }
                case .structured(let json): answer = json
                case .failed(let reason): failure = reason
                case .toolCall, .toolResult:
                    mutatePlan(messageID, in: chatID) { $0.steps[index].tools.apply(event, at: .now) }
                default: break
                }
            }
            guard turns[chatID]?.token == token else { return }
            if let failure {
                // The turn itself failed — the CLI, not the work. Halt, so the person can see why
                // and Resume, rather than spending the rest of the plan against the same wall.
                mutatePlan(messageID, in: chatID) { plan in
                    plan.steps[index].status = .failed
                    plan.steps[index].note = failure
                    plan.steps[index].endedAt = .now
                    plan.steps[index].tools.finishUnfinished()
                    plan.haltedStepID = plan.steps[index].id
                    plan.status = .stopped
                    plan.endedAt = .now
                }
                return
            }
            let result = answer.flatMap(StepAnswer.decode)
            mutatePlan(messageID, in: chatID) { plan in
                plan.steps[index].status = result?.failed == true ? .failed : .done
                plan.steps[index].note = result.map(\.note).flatMap { $0.isEmpty ? nil : $0 }
                plan.steps[index].endedAt = .now
                plan.steps[index].tools.finishUnfinished()
                if let note = plan.steps[index].note { plan.note = note }
                let wanted = result?.add ?? []
                let room = max(0, Self.maxAddedSteps - plan.added)
                let additions = wanted.prefix(room).map { PlanStep(title: $0.title, active: $0.active, added: true) }
                plan.steps.insert(contentsOf: additions, at: index + 1)
                plan.added += additions.count
                if wanted.count > room {
                    plan.note = String(localized: "Stopped adding steps at \(Self.maxAddedSteps).")
                }
            }
        }
        guard turns[chatID]?.token == token, let chat = chat(chatID) else { return }
        var closing = ""
        let request = TurnRequest(prompt: Self.closingPrompt, directory: directory(for: chat), model: turnModel(for: chat),
                                  mode: .readOnly, resumeID: chat.sessionID, effort: chat.effort)
        for await event in brain.run(request) {
            guard turns[chatID]?.token == token else { return }
            switch event {
            case .session(let session): update(chatID) { $0.sessionID = session }
            case .textDelta(let text): closing += text
            case .text(let text): closing += (closing.isEmpty ? "" : "\n\n") + text
            default: break
            }
        }
        guard turns[chatID]?.token == token else { return }
        mutatePlan(messageID, in: chatID) { plan in
            let trimmed = closing.trimmingCharacters(in: .whitespacesAndNewlines)
            plan.closing = trimmed.isEmpty ? nil : trimmed
            plan.status = .finished
            plan.endedAt = .now
        }
        let count = storedPlan(messageID, in: chatID)?.steps.count ?? 0
        toasts.show(String(localized: "Plan finished · \(count) steps"), systemImage: "checkmark")
    }

    /// Stop, or quit, while a plan turn ran.
    func haltPlan(_ messageID: UUID, in chatID: UUID) {
        mutatePlan(messageID, in: chatID) { plan in
            for index in plan.steps.indices where plan.steps[index].status == .running {
                plan.steps[index].status = .stopped
                plan.steps[index].endedAt = .now
                plan.steps[index].tools.finishUnfinished()
            }
            if plan.status == .drafting {
                plan.investigation.finishUnfinished()
                plan.problem = String(localized: "Planning was stopped.")
            }
            if plan.status != .finished {
                plan.status = .stopped
                plan.endedAt = .now
            }
        }
    }

    // MARK: Storage

    func storedPlan(_ messageID: UUID, in chatID: UUID) -> Plan? {
        transcripts[chatID]?.first { $0.id == messageID }?.plan
    }

    /// Changes the plan in its message and saves the message in place.
    func mutatePlan(_ messageID: UUID, in chatID: UUID, _ change: (inout Plan) -> Void) {
        guard var list = transcripts[chatID],
              let row = list.firstIndex(where: { $0.id == messageID }),
              let slot = list[row].parts.firstIndex(where: { if case .plan = $0 { true } else { false } }),
              case .plan(var plan) = list[row].parts[slot] else { return }
        change(&plan)
        list[row].parts[slot] = .plan(plan)
        transcripts[chatID] = list
        let message = list[row]
        attempt { try store.replace(message) }
    }

    // MARK: Prompts

    static func planningPrompt(_ request: String) -> String {
        """
        \(request)

        ---
        Plan mode: investigate first and change nothing. Then answer with a plan for the request \
        above: a one-sentence summary and 3 to 8 short steps. The user will review and edit the \
        steps before anything runs.
        """
    }

    static func stepPrompt(_ steps: [PlanStep], _ index: Int) -> String {
        let list = steps.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
        return """
        Do step \(index + 1) of the plan: \(steps[index].title)

        The whole plan, for context:
        \(list)

        Do only this step. Then answer: outcome done or failed (failed if the step could not be \
        completed, for example a test failed), a one-sentence note for the user, and any steps that \
        must be added right after this one to finish the job (usually none).
        """
    }

    static let closingPrompt = "All the steps are finished. In one or two sentences, tell the user what changed."
}
