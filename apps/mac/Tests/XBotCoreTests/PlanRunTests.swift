import Foundation
import Synchronization
import Testing
import XBotBrain
@testable import XBotCore

/// Plays one script per turn, in order. With no scripts left it plays `fallback`, or — with none —
/// holds the turn open forever.
final class SequenceBrain: Brain {
    private let scripts: Mutex<[[BrainEvent]]>
    private let fallback: [BrainEvent]?
    let requests = Mutex<[TurnRequest]>([])

    init(_ scripts: [[BrainEvent]], fallback: [BrainEvent]? = nil) {
        self.scripts = Mutex(scripts)
        self.fallback = fallback
    }

    func run(_ request: TurnRequest) -> AsyncStream<BrainEvent> {
        requests.withLock { $0.append(request) }
        let script = scripts.withLock { $0.isEmpty ? fallback : $0.removeFirst() }
        let (stream, continuation) = AsyncStream.makeStream(of: BrainEvent.self)
        if let script {
            for event in script { continuation.yield(event) }
            continuation.finish()
        }
        return stream
    }
}

func planJSON(_ titles: [String]) -> String {
    let steps = titles.map { #"{"title":"\#($0)","active":"\#($0)ing"}"# }.joined(separator: ",")
    return #"{"summary":"Debounce the search value.","steps":[\#(steps)]}"#
}

func stepJSON(_ outcome: String = "done", note: String = "", add: [String] = []) -> String {
    let added = add.map { #"{"title":"\#($0)","active":"\#($0)ing"}"# }.joined(separator: ",")
    return #"{"outcome":"\#(outcome)","note":"\#(note)","add":[\#(added)]}"#
}

@MainActor @Suite struct PlanRunTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "plan-\(UUID().uuidString)")

    func planChat(_ brain: SequenceBrain, review: Bool = true, store: Store = .inMemory())
        async throws -> (Workspace, UUID) {
        let w = Workspace(store: store, inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        let chat = try #require(w.newChat(in: nil))
        w.setPlanMode(true, for: chat.id)
        w.setReviewPlan(review, for: chat.id)
        return (w, chat.id)
    }

    func settle(_ w: Workspace, _ id: UUID) async {
        for _ in 0..<5000 where w.isRunning(id) { await Task.yield() }
    }

    func reviewed(_ w: Workspace, _ id: UUID) async throws -> (UUID, Plan) {
        await settle(w, id)
        let found = try #require(w.latestPlan(in: id))
        return (found.messageID, found.plan)
    }

    @Test func planningProducesAReviewablePlan() async throws {
        let brain = SequenceBrain([[
            .session("s1"),
            .toolCall(id: "t", name: "Read", summary: "search.ts"),
            .toolResult(id: "t", output: "1\tx", isError: false),
            .structured(planJSON(["Find it", "Fix it"])), .done,
        ]])
        let (w, id) = try await planChat(brain)
        #expect(w.send("Search lags. Fix it.", in: id))
        let (_, plan) = try await reviewed(w, id)
        #expect(plan.status == .review)
        #expect(plan.steps.map(\.title) == ["Find it", "Fix it"])
        #expect(plan.steps.map(\.active) == ["Find iting", "Fix iting"])
        #expect(plan.summary == "Debounce the search value.")
        #expect(plan.investigation.count == 1)
        let request = try #require(brain.requests.withLock { $0.first })
        #expect(request.planning && request.schema == PlanSchemas.plan)
        #expect(request.prompt.contains("Search lags. Fix it."))
        #expect(w.chat(id)?.sessionID == "s1")
        #expect(w.messages(in: id).map(\.role) == [.user, .assistant])
    }

    @Test func runningGoesStepByStepResumingTheSession() async throws {
        let brain = SequenceBrain([
            [.session("s1"), .structured(planJSON(["Find it", "Fix it"])), .done],
            [.toolCall(id: "a", name: "Read", summary: "x"), .toolResult(id: "a", output: "1", isError: false),
             .structured(stepJSON(note: "Found it in api.ts.")), .done],
            [.structured(stepJSON(note: "Debounced.")), .done],
            [.textDelta("Done. Search waits for a pause."), .done],
        ])
        let (w, id) = try await planChat(brain)
        _ = w.send("Fix search", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        #expect(w.runPlan(messageID, in: id, steps: plan.steps))
        await settle(w, id)
        let done = try #require(w.latestPlan(in: id)?.plan)
        #expect(done.status == .finished)
        #expect(done.steps.map(\.status) == [.done, .done])
        #expect(done.steps[0].tools.count == 1)
        #expect(done.note == "Debounced.")
        #expect(done.closing == "Done. Search waits for a pause.")
        let requests = brain.requests.withLock { $0 }
        #expect(requests[1].resumeID == "s1" && requests[1].schema == PlanSchemas.step && !requests[1].planning)
        #expect(requests[1].prompt.contains("Do step 1 of the plan: Find it"))
        #expect(requests[2].prompt.contains("Do step 2 of the plan: Fix it"))
        #expect(requests[3].schema == nil)
    }

    @Test func aFailedStepIsRecordedAndTheAgentsAdditionsRunNext() async throws {
        let brain = SequenceBrain([
            [.structured(planJSON(["Run the tests", "Update the docs"])), .done],
            [.structured(stepJSON("failed", note: "1 failed: expected re", add: ["Fix the test", "Run the tests again"])), .done],
            [.structured(stepJSON()), .done], [.structured(stepJSON()), .done], [.structured(stepJSON()), .done],
            [.done],
        ])
        let (w, id) = try await planChat(brain)
        _ = w.send("Fix", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        _ = w.runPlan(messageID, in: id, steps: plan.steps)
        await settle(w, id)
        let after = try #require(w.latestPlan(in: id)?.plan)
        #expect(after.steps.map(\.title) == ["Run the tests", "Fix the test", "Run the tests again", "Update the docs"])
        #expect(after.steps.map(\.status) == [.failed, .done, .done, .done])
        #expect(after.steps[0].note == "1 failed: expected re")
        #expect(after.steps[1].added && after.added == 2)
        #expect(after.status == .finished && after.failedCount == 1)
    }

    @Test func aBrainFailureHaltsThePlanAndResumeRetriesThatStep() async throws {
        let brain = SequenceBrain([
            [.structured(planJSON(["One", "Two"])), .done],
            [.failed("You've hit your usage limit.")],
            [.structured(stepJSON()), .done], [.structured(stepJSON()), .done], [.done],
        ])
        let (w, id) = try await planChat(brain)
        _ = w.send("Go", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        _ = w.runPlan(messageID, in: id, steps: plan.steps)
        await settle(w, id)
        let halted = try #require(w.latestPlan(in: id)?.plan)
        #expect(halted.status == .stopped)
        #expect(halted.steps.map(\.status) == [.failed, .pending])
        #expect(halted.steps[0].note == "You've hit your usage limit.")
        #expect(w.resumePlan(messageID, in: id))
        await settle(w, id)
        let resumed = try #require(w.latestPlan(in: id)?.plan)
        #expect(resumed.status == .finished && resumed.steps.map(\.status) == [.done, .done])
    }

    @Test func stopMidStepLeavesAResumablePlan() async throws {
        let brain = SequenceBrain([[.structured(planJSON(["One", "Two"])), .done]])  // step 1 then holds
        let (w, id) = try await planChat(brain)
        _ = w.send("Go", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        _ = w.runPlan(messageID, in: id, steps: plan.steps)
        for _ in 0..<50 { await Task.yield() }
        w.stop(id)
        let stopped = try #require(w.latestPlan(in: id)?.plan)
        #expect(stopped.status == .stopped && !stopped.isCancelled)
        #expect(stopped.steps.map(\.status) == [.stopped, .pending])
        #expect(w.messages(in: id).count == 2)  // no stray "Stopped." message
    }

    @Test func editingATitleReplacesItsActiveLabelAndEmptyStepsAreDropped() async throws {
        let brain = SequenceBrain([[.structured(planJSON(["Find it", "Fix it"])), .done]], fallback: [.done])
        let (w, id) = try await planChat(brain)
        _ = w.send("Go", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        var steps = plan.steps
        steps[0].title = "Find it & prepare a report"
        steps.append(PlanStep(title: "  ", active: ""))
        _ = w.runPlan(messageID, in: id, steps: steps)
        await settle(w, id)
        let ran = try #require(w.latestPlan(in: id)?.plan)
        #expect(ran.steps.map(\.title) == ["Find it & prepare a report", "Fix it"])
        #expect(ran.steps.map(\.active) == ["Find it & prepare a report", "Fix iting"])
    }

    @Test func withoutReviewThePlanRunsStraightAway() async throws {
        let brain = SequenceBrain([[.structured(planJSON(["One"])), .done]], fallback: [.structured(stepJSON()), .done])
        let (w, id) = try await planChat(brain, review: false)
        _ = w.send("Go", in: id)
        await settle(w, id)
        #expect(w.latestPlan(in: id)?.plan.status == .finished)
    }

    @Test func noPlanShowsTheProblemAndCanRetry() async throws {
        let brain = SequenceBrain([
            [.text("I'd rather just chat."), .done],
            [.structured(planJSON(["One"])), .done],
        ])
        let (w, id) = try await planChat(brain)
        _ = w.send("Go", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        #expect(plan.status == .stopped && plan.steps.isEmpty)
        #expect(plan.problem == String(localized: "The agent didn't return a plan."))
        #expect(plan.reply == "I'd rather just chat.")
        #expect(w.retryPlanning(messageID, in: id))
        let (_, retried) = try await reviewed(w, id)
        #expect(retried.status == .review && retried.problem == nil)
        #expect(brain.requests.withLock { $0[1].prompt.contains("Go") })
    }

    @Test func additionsAreCappedAtTwenty() async throws {
        let many = (1...25).map { "Extra \($0)" }
        let brain = SequenceBrain([
            [.structured(planJSON(["One"])), .done],
            [.structured(stepJSON(add: many)), .done],
        ], fallback: [.structured(stepJSON()), .done])
        let (w, id) = try await planChat(brain)
        _ = w.send("Go", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        _ = w.runPlan(messageID, in: id, steps: plan.steps)
        await settle(w, id)
        let ran = try #require(w.latestPlan(in: id)?.plan)
        #expect(ran.added == Workspace.maxAddedSteps)
        #expect(ran.steps.count == 1 + Workspace.maxAddedSteps)
    }

    @Test func aStepWithoutAStructuredAnswerCountsAsDone() async throws {
        let brain = SequenceBrain([[.structured(planJSON(["One"])), .done], [.textDelta("did it"), .done], [.done]])
        let (w, id) = try await planChat(brain)
        _ = w.send("Go", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        _ = w.runPlan(messageID, in: id, steps: plan.steps)
        await settle(w, id)
        #expect(w.latestPlan(in: id)?.plan.steps.first?.status == .done)
    }

    @Test func cancellingInReviewLeavesTheMessage() async throws {
        let (w, id) = try await planChat(SequenceBrain([[.structured(planJSON(["One"])), .done]]))
        _ = w.send("Go", in: id)
        let (messageID, _) = try await reviewed(w, id)
        w.cancelPlan(messageID, in: id)
        #expect(w.latestPlan(in: id)?.plan.isCancelled == true)
        #expect(w.messages(in: id).first?.parts == [.text("Go")])
    }

    @Test func everyChangeIsSaved() async throws {
        let store = Store.inMemory()
        let brain = SequenceBrain([[.structured(planJSON(["One"])), .done]], fallback: [.structured(stepJSON()), .done])
        let (w, id) = try await planChat(brain, store: store)
        _ = w.send("Go", in: id)
        let (messageID, plan) = try await reviewed(w, id)
        _ = w.runPlan(messageID, in: id, steps: plan.steps)
        await settle(w, id)
        #expect(try store.messages(in: id).last?.plan == w.latestPlan(in: id)?.plan)
    }
}
