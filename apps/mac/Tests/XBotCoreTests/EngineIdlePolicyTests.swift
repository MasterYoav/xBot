import Foundation
import Testing
@testable import XBotCore

/// When the engine may be stopped for idleness. docs/07.
@Suite
struct EngineIdlePolicyTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private var longAfter: Date { start.addingTimeInterval(EngineIdlePolicy.defaultTimeout + 60) }

    private func verdict(
        now: Date? = nil,
        turnRunning: Bool = false,
        humanHoldsControl: Bool = false,
        enabledRoutines: Int? = 0
    ) -> EngineIdlePolicy.Verdict {
        EngineIdlePolicy.verdict(
            lastActivity: start,
            now: now ?? longAfter,
            turnRunning: turnRunning,
            humanHoldsControl: humanHoldsControl,
            enabledRoutines: enabledRoutines
        )
    }

    @Test func aQuietEngineWithNothingDependingOnItStops() {
        #expect(verdict() == .stop)
    }

    @Test func notBeforeTheTimeout() {
        #expect(verdict(now: start.addingTimeInterval(EngineIdlePolicy.defaultTimeout - 1)) == .keepRunning)
    }

    /// Stopping mid-turn would throw the reply away, however long the turn has been running.
    @Test func neverDuringATurn() {
        #expect(verdict(turnRunning: true) == .keepRunning)
    }

    /// Somebody typing a password into the agent's browser is not idle.
    @Test func neverWhileAPersonHoldsTheBrowser() {
        #expect(verdict(humanHoldsControl: true) == .keepRunning)
    }

    /**
     The rule this type exists for.

     Routines run inside the engine. Stopping it for idleness would silently cancel "check the inbox
     every weekday at nine" on the first quiet afternoon — the person set it up precisely so they
     would not have to be at the Mac.
     */
    @Test func neverWhileARoutineIsSwitchedOn() {
        #expect(verdict(enabledRoutines: 1) == .keepRunning)
    }

    /// Could not find out is not the same as none. Guessing wrong one way costs some memory; the
    /// other way breaks a routine with nothing on screen to say so.
    @Test func notWhenItCannotTellWhetherRoutinesExist() {
        #expect(verdict(enabledRoutines: nil) == .keepRunning)
    }
}
