import Testing
@testable import XBotCore

@MainActor @Suite struct ToastCenterTests {
    @Test func toastsQueueAndExpire() async throws {
        let center = ToastCenter(duration: .milliseconds(40), actionDuration: .milliseconds(40))
        center.show("one")
        center.show("two")
        #expect(center.current?.text == "one")
        try await Task.sleep(for: .milliseconds(70))
        #expect(center.current?.text == "two")
        try await Task.sleep(for: .milliseconds(70))
        #expect(center.current == nil)
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
