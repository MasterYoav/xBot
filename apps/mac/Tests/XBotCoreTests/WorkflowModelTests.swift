import Foundation
import Testing
import XBotBrain
@testable import XBotCore

/// Workflows' model: steps, their storage, and how a Jev step asks and decides. See
/// docs/superpowers/specs/2026-10-12-jev-workflows-design.md.
@Suite struct WorkflowModelTests {
    let fix = WorkflowStep(title: "Fix it", kind: .agent(AgentStep(prompt: "Fix the build")))

    @Test func anAgentStepCanEditByDefault() {
        let step = AgentStep(prompt: "x")
        #expect(step.mode == .editFiles)
        #expect(step.brain == .jevPicks)
    }

    @Test func aGateDefaultsToHalfContinueOrStop() {
        let gate = JevGate()
        #expect(gate.threshold == 0.5)
        #expect(gate.yes == .next)
        #expect(gate.no == .stop)
    }

    @Test func stepsRoundTripAsJSON() throws {
        let steps: [WorkflowStep] = [
            fix,
            WorkflowStep(title: "Check", kind: .agent(AgentStep(
                prompt: "Run the tests", brain: .fixed(BrainChoice(harness: .codex, model: "gpt-5-mini", effort: .low)),
                mode: .readOnly))),
            WorkflowStep(title: "Failing?", kind: .jev(JevStep(question: "Is the build failing?",
                                                                decision: .gate(JevGate(threshold: 0.7, yes: .step(fix.id), no: .stop))))),
            WorkflowStep(title: "Where", kind: .jev(JevStep(question: "Where next?", decision: .route([
                RouteOption(label: "Docs", target: .next), RouteOption(label: "Code", target: .step(fix.id)),
            ])))),
            WorkflowStep(title: "How good", kind: .jev(JevStep(question: "How good is it?", decision: .score([
                ScoreLevel(label: "Bad", target: .step(fix.id)), ScoreLevel(label: "Good"),
            ])))),
        ]
        let data = try JSONEncoder().encode(steps)
        #expect(try JSONDecoder().decode([WorkflowStep].self, from: data) == steps)
    }

    // MARK: Asking

    @Test func aGateAsksOneYesNoQuestion() {
        let step = JevStep(question: "Is the build failing?", decision: .gate(JevGate()))
        #expect(step.jevQuestion() == .noul("Is the build failing?"))
    }

    @Test func aRouteAsksAChoiceOverItsOptions() {
        let step = JevStep(question: "Where next?", decision: .route([
            RouteOption(label: "Write docs", target: .next), RouteOption(label: "Fix code", target: .stop),
        ]))
        guard case .choice(let options) = step.jevQuestion().kind else { Issue.record("not a choice"); return }
        #expect(options.map(\.description) == ["Write docs", "Fix code"])
        #expect(Set(options.map(\.key)).count == 2)
    }

    @Test func aScoreAsksItsLevelsLowestFirst() {
        let step = JevStep(question: "How good?", decision: .score([ScoreLevel(label: "Bad"), ScoreLevel(label: "OK"), ScoreLevel(label: "Great")]))
        #expect(step.jevQuestion() == .score("How good?", levels: ["Bad", "OK", "Great"]))
    }

    // MARK: Deciding

    @Test func aGateAtOrAboveItsThresholdIsYes() {
        let step = JevStep(question: "Failing?", decision: .gate(JevGate(threshold: 0.7, yes: .step(fix.id), no: .stop)))
        #expect(step.decide(.noul(0.91))?.target == .step(fix.id))
        #expect(step.decide(.noul(0.7))?.target == .step(fix.id))
        #expect(step.decide(.noul(0.69))?.target == .stop)
        #expect(step.decide(.noul(0.91))?.said == "yes (0.91)")
        #expect(step.decide(.noul(0.2))?.said == "no (0.20)")
    }

    @Test func aRouteFollowsTheChosenOption() {
        let docs = RouteOption(label: "Write docs", target: .next)
        let code = RouteOption(label: "Fix code", target: .step(fix.id))
        let step = JevStep(question: "Where?", decision: .route([docs, code]))
        guard case .choice(let options) = step.jevQuestion().kind else { return }
        let decision = step.decide(.choice(options[1].key, probabilities: [:], confidence: 0.88))
        #expect(decision?.target == .step(fix.id))
        #expect(decision?.said == "Fix code (0.88)")
        #expect(step.decide(.choice("nonsense", probabilities: [:], confidence: 1)) == nil)
    }

    @Test func aScoreGoesWhereItsNearestLevelSays() {
        let step = JevStep(question: "How good?", decision: .score([
            ScoreLevel(label: "Bad", target: .step(fix.id)), ScoreLevel(label: "OK", target: .next), ScoreLevel(label: "Great", target: .stop),
        ]))
        #expect(step.decide(.score(0.4, legend: [:], probabilities: [:], confidence: 0.6))?.target == .step(fix.id))
        #expect(step.decide(.score(1.38, legend: [:], probabilities: [:], confidence: 0.6))?.target == .next)
        #expect(step.decide(.score(1.6, legend: [:], probabilities: [:], confidence: 0.6))?.target == .stop)
        #expect(step.decide(.score(9, legend: [:], probabilities: [:], confidence: 0.6))?.target == .stop)
        #expect(step.decide(.score(1.38, legend: [:], probabilities: [:], confidence: 0.58))?.said == "OK, 1.38 (0.58)")
    }

    @Test func anAnswerOfTheWrongTypeDecidesNothing() {
        let step = JevStep(question: "Failing?", decision: .gate(JevGate()))
        #expect(step.decide(.choice("a", probabilities: [:], confidence: 1)) == nil)
    }

    // MARK: Editing

    @Test func aWorkflowNeedsJevWhenAStepAsksIt() {
        var w = Workflow(name: "x", trigger: .manual, steps: [
            WorkflowStep(title: "a", kind: .agent(AgentStep(prompt: "p", brain: .fixed(BrainChoice(harness: .claude))))),
        ])
        #expect(!w.needsJev)
        w.steps.append(WorkflowStep(title: "b", kind: .agent(AgentStep(prompt: "p"))))
        #expect(w.needsJev)
        w.steps = [WorkflowStep(title: "g", kind: .jev(JevStep(question: "?", decision: .gate(JevGate()))))]
        #expect(w.needsJev)
    }

    @Test func hasWorkNeedsAnAgentStepThatSaysSomething() {
        #expect(!Workflow(name: "x", trigger: .manual, steps: []).hasWork)
        #expect(!Workflow(name: "x", trigger: .manual, steps: [WorkflowStep(title: "a", kind: .agent(AgentStep(prompt: "  ")))]).hasWork)
        #expect(Workflow(name: "x", trigger: .manual, steps: [fix]).hasWork)
    }

    @Test func movingAStepKeepsTheOthersInOrder() {
        let a = WorkflowStep(title: "a", kind: .agent(AgentStep(prompt: "a")))
        let b = WorkflowStep(title: "b", kind: .agent(AgentStep(prompt: "b")))
        let c = WorkflowStep(title: "c", kind: .agent(AgentStep(prompt: "c")))
        var w = Workflow(name: "x", trigger: .manual, steps: [a, b, c])
        w.move(c.id, to: 0)
        #expect(w.steps.map(\.title) == ["c", "a", "b"])
        w.move(c.id, to: 3)
        #expect(w.steps.map(\.title) == ["a", "b", "c"])
    }

    @Test func droppingAPaletteTileAddsThatKindOfStepWhereItLands() {
        var w = Workflow(name: "x", trigger: .manual, steps: [fix])
        do { let ok = w.drop(Workflow.dragItem(for: .gate), at: 0); #expect(ok) }
        do { let ok = w.drop(Workflow.dragItem(for: .route), at: 99); #expect(ok) }
        do { let ok = w.drop(Workflow.dragItem(for: .score), at: 1); #expect(ok) }
        do { let ok = w.drop(Workflow.dragItem(for: .agent), at: 1); #expect(ok) }
        let kinds = w.steps.map { step -> String in
            switch step.kind {
            case .agent: "agent"
            case .jev(let j): switch j.decision { case .gate: "gate"; case .route: "route"; case .score: "score" }
            }
        }
        #expect(kinds == ["gate", "agent", "score", "agent", "route"])
        // New Jev steps start with something to edit: two options, three levels.
        guard case .jev(let route) = w.steps[4].kind, case .route(let options) = route.decision,
              case .jev(let score) = w.steps[2].kind, case .score(let levels) = score.decision else { Issue.record("kinds"); return }
        #expect(options.count == 2)
        #expect(levels.count == 3)
    }

    @Test func droppingAStepCardMovesIt() {
        let a = WorkflowStep(title: "a", kind: .agent(AgentStep(prompt: "a")))
        let b = WorkflowStep(title: "b", kind: .agent(AgentStep(prompt: "b")))
        var w = Workflow(name: "x", trigger: .manual, steps: [a, b])
        do { let ok = w.drop(Workflow.dragItem(for: b), at: 0); #expect(ok) }
        #expect(w.steps.map(\.title) == ["b", "a"])
        do { let ok = w.drop("hello", at: 0); #expect(!ok) }
        do { let ok = w.drop("wstep:\(UUID().uuidString)", at: 0); #expect(!ok) }
    }

    @Test func removingAStepSendsGoTosAtItToTheNextStep() {
        let target = WorkflowStep(title: "t", kind: .agent(AgentStep(prompt: "t")))
        let gate = WorkflowStep(title: "g", kind: .jev(JevStep(question: "?", decision: .gate(JevGate(yes: .step(target.id), no: .stop)))))
        var w = Workflow(name: "x", trigger: .manual, steps: [gate, target])
        w.removeStep(target.id)
        guard case .jev(let jev) = w.steps[0].kind, case .gate(let g) = jev.decision else { Issue.record("gate lost"); return }
        #expect(g.yes == .next)
    }
}

@Suite struct WorkflowStateTests {
    @Test func theStateIsTheInputThenEachOutputUnderItsTitleNewestLast() {
        let state = WorkflowState.assemble(input: "Ship 2.0", outputs: [("Build", "Built."), ("Test", "3 failed.")])
        #expect(state == "Input:\nShip 2.0\n\n## Build\nBuilt.\n\n## Test\n3 failed.")
    }

    @Test func noInputMeansNoInputSection() {
        #expect(WorkflowState.assemble(input: "  ", outputs: [("Build", "Built.")]) == "## Build\nBuilt.")
    }

    @Test func aLongStateIsTrimmedFromTheOldestEnd() {
        let old = String(repeating: "o", count: 500)
        let state = WorkflowState.assemble(input: old, outputs: [("New", "the newest words")], limit: 100)
        #expect(state.count <= 100)
        #expect(state.hasSuffix("## New\nthe newest words"))
        #expect(state.hasPrefix("…"))
    }
}
