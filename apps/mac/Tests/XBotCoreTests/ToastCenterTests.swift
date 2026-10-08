import Testing
@testable import XBotCore

@MainActor @Suite struct ToastCenterTests {
    @Test func toastsQueueAndExpire() async throws {
        let center = ToastCenter(duration: .milliseconds(40), actionDuration: .milliseconds(40))
        center.show("one")
        center.show("two")
        #expect(center.current?.text == "one")
        try await until { center.current?.text == "two" }
        #expect(center.current?.text == "two")
        try await until { center.current == nil }
        #expect(center.current == nil)
    }

    /// Waits for a condition, up to two seconds: a busy machine (the git tests spawn processes
    /// beside this one) can delay a 40 ms timer well past a fixed sleep.
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func anActionRunsOnceAndMovesOn() {
        let center = ToastCenter()
        var runs = 0
        center.show("Deleted", action: .init(title: "Undo", run: { runs += 1 }))
        center.show("next")
        center.performAction()
        center.performAction()
        #expect(runs == 1)
        #expect(center.current?.text == "next")
    }
}
