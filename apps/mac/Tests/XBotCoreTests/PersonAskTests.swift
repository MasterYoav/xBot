import Foundation
import Testing
import XBotEngine
@testable import XBotCore

/// An agent's computer asking the person for a secret mid-turn, and the person answering.
@MainActor
struct PersonAskTests {
    @Test func aSecretAskedDuringATurnIsShownAndAnswered() async throws {
        let engine = StubEngineClient(tokenDelay: .milliseconds(300))
        await engine.ask(ComputerControlState(holder: .agent, secretWanted: "the verification code"))
        let state = AppState(engine: engine)
        await state.load()

        state.send("sign me in")
        try await until { state.personAsk != nil }
        #expect(state.personAsk?.ask == .secret(label: "the verification code"))

        state.supplySecret("123456")
        try await until { state.personAsk == nil }
        // The engine got a value; nothing on this side kept it.
        #expect(await engine.suppliedSecretLengths == [6])
        #expect(state.secretProblem == nil)
    }

    @Test func theAskEndsWithTheTurn() async throws {
        let engine = StubEngineClient(tokenDelay: .zero)
        await engine.ask(ComputerControlState(holder: .agent, helpReason: "Sign in to the bank"))
        let state = AppState(engine: engine)
        await state.load()

        state.send("hello")
        try await until { !state.isTurnInFlight }
        #expect(state.personAsk == nil)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for state")
    }
}
