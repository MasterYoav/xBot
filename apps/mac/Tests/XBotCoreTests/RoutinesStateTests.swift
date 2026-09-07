import Foundation
import Testing
import XBotEngine
@testable import XBotCore

/// The Routines panel's state: show and stop, never compose.
@MainActor
@Suite
struct RoutinesStateTests {
    private func routine(
        _ id: String,
        agent: String = "orchestrator",
        enabled: Bool = true
    ) -> Routine {
        Routine(
            id: id,
            agentId: agent,
            schedule: "Weekdays at 09:00",
            timezone: "Europe/London",
            instruction: "Check the inbox.",
            enabled: enabled
        )
    }

    private struct Refused: Error {}

    @Test func showsOnlyTheSelectedAgentsRoutines() async {
        let state = RoutinesState()
        await state.load(for: "orchestrator") {
            [self.routine("a"), self.routine("b", agent: "researcher")]
        }
        #expect(state.routines.map(\.id) == ["a"])
    }

    /**
     Failure is never an empty list.

     "This agent has no routines" and "I could not ask" are opposite answers, and only one of them
     means the person should go and make one. The panel draws an invitation to create one on empty,
     so confusing the two sends somebody to ask for a routine they already have.
     */
    @Test func aFailureSaysSoInsteadOfShowingNone() async {
        let state = RoutinesState()
        await state.load(for: nil) { throw Refused() }
        #expect(state.routines.isEmpty)
        #expect(state.problem != nil)
    }

    @Test func loadingAgainClearsAnEarlierProblem() async {
        let state = RoutinesState()
        await state.load(for: nil) { throw Refused() }
        await state.load(for: nil) { [self.routine("a")] }
        #expect(state.problem == nil)
        #expect(state.routines.count == 1)
    }

    @Test func theSwitchMovesBeforeTheEngineAnswers() async {
        let state = RoutinesState()
        await state.load(for: nil) { [self.routine("a", enabled: true)] }
        await state.setEnabled("a", to: false) { _, _ in }
        #expect(state.routines[0].enabled == false)
    }

    /// A switch that lies about a routine still firing at 09:00 is worse than a slow one.
    @Test func aRefusedChangePutsTheSwitchBack() async {
        let state = RoutinesState()
        await state.load(for: nil) { [self.routine("a", enabled: true)] }
        await state.setEnabled("a", to: false) { _, _ in throw Refused() }
        #expect(state.routines[0].enabled == true)
        #expect(state.problem != nil)
    }

    @Test func aRefusedDeleteBringsTheRoutineBack() async {
        let state = RoutinesState()
        await state.load(for: nil) { [self.routine("a"), self.routine("b")] }
        await state.delete("a") { _ in throw Refused() }
        #expect(state.routines.map(\.id) == ["a", "b"])
        #expect(state.problem != nil)
    }

    @Test func aDeleteThatWorksLeavesTheRest() async {
        let state = RoutinesState()
        await state.load(for: nil) { [self.routine("a"), self.routine("b")] }
        await state.delete("a") { _ in }
        #expect(state.routines.map(\.id) == ["b"])
    }
}
