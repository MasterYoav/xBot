import Foundation
import Testing
@testable import XBotCore

@MainActor
@Suite struct ApprovalCenterTests {
    private func sample() -> ApprovalPart {
        ApprovalPart(agent: "Forge", summary: "Delete 3 files", detail: "rm a b c", risk: "delete")
    }

    @Test func anAnsweredApprovalReturnsTheAnswerAndUpdatesTheCard() async {
        let center = ApprovalCenter()
        var posted: [ApprovalPart] = []
        var updated: [ApprovalPart] = []
        center.post = { approval, _ in posted.append(approval) }
        center.update = { approval, _ in updated.append(approval) }
        let approval = sample()
        let chat = UUID()
        async let state = center.ask(approval, in: chat)
        for _ in 0..<200 where center.pending.isEmpty { await Task.yield() }
        #expect(center.pending.map(\.approval.id) == [approval.id])
        #expect(center.answer(approval.id, allow: true, by: "iPhone"))
        #expect(await state == .allowed)
        #expect(posted.first?.state == .pending)
        #expect(updated.first?.state == .allowed)
        #expect(updated.first?.answeredBy == "iPhone")
        #expect(center.pending.isEmpty)
        #expect(!center.answer(approval.id, allow: false, by: "Mac"), "already answered")
    }

    @Test func aRefusalIsARefusal() async {
        let center = ApprovalCenter()
        let approval = sample()
        async let state = center.ask(approval, in: UUID())
        for _ in 0..<200 where center.pending.isEmpty { await Task.yield() }
        center.answer(approval.id, allow: false, by: "Mac")
        #expect(await state == .refused)
    }

    @Test func noAnswerExpires() async {
        let center = ApprovalCenter()
        var updated: [ApprovalPart] = []
        center.update = { approval, _ in updated.append(approval) }
        let state = await center.ask(sample(), in: UUID(), timeout: .milliseconds(50))
        #expect(state == .expired)
        #expect(updated.first?.state == .expired)
        #expect(center.pending.isEmpty)
    }
}

@Suite struct ExperienceStoreTests {
    private func store() -> ExperienceStore {
        ExperienceStore(folder: FileManager.default.temporaryDirectory.appending(path: "xbot-exp-\(UUID().uuidString)"))
    }

    @Test func lessonsRoundTripPerAgent() throws {
        let store = store()
        let forge = UUID(), hawk = UUID()
        try store.remember(Lesson(cue: "When Xcode asks to trust a package", lesson: "Choose Trust and Enable",
                                  confidence: .high, evidence: "The build failed until it was trusted"), for: forge)
        #expect(store.lessons(of: forge).map(\.lesson) == ["Choose Trust and Enable"])
        #expect(store.lessons(of: hawk).isEmpty)
    }

    @Test func theSameCueReplacesTheOlderLesson() throws {
        let store = store()
        let forge = UUID()
        try store.remember(Lesson(cue: "When tests are slow", lesson: "Run one suite", confidence: .low, evidence: "a"), for: forge)
        try store.remember(Lesson(cue: "when  tests are slow.", lesson: "Use --filter", confidence: .medium, evidence: "b"), for: forge)
        #expect(store.lessons(of: forge).map(\.lesson) == ["Use --filter"])
    }

    @Test func savingNothingRemovesTheFile() throws {
        let store = store()
        let forge = UUID()
        try store.remember(Lesson(cue: "x", lesson: "y", confidence: .low, evidence: "z"), for: forge)
        try store.save([], of: forge)
        #expect(store.lessons(of: forge).isEmpty)
    }
}
