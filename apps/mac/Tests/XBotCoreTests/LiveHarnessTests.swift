import Foundation
import Testing
@testable import XBotCore

/// A real turn through each installed CLI, on the developer's own subscription. Off by default:
/// it costs tokens and needs a signed-in CLI. Run with `XBOT_LIVE_HARNESS=1 swift test --filter Live`
/// after a CLI update, to see whether its stream format still reads.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["XBOT_LIVE_HARNESS"] == "1"))
struct LiveHarnessTests {
    @Test(arguments: HarnessKind.allCases)
    func aRealTurnRunsAndResumes(kind: HarnessKind) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xbot-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "the secret word is plum\n".write(to: folder.appending(path: "note.txt"), atomically: true, encoding: .utf8)

        let installed = await HarnessLocator.installed()
        try #require(installed[kind] != nil, "\(kind.displayName) is not installed")
        let w = Workspace(store: .inMemory(), inbox: folder, discover: { installed.filter { $0.key == kind } })
        await w.refreshHarnesses()
        let chat = try #require(w.newChat(in: nil))
        w.setMode(.readOnly, for: chat.id)

        #expect(w.send("Read note.txt and reply with only the secret word.", in: chat.id))
        while w.isRunning(chat.id) { try await Task.sleep(for: .milliseconds(200)) }
        let first = try #require(w.messages(in: chat.id).last)
        #expect(first.parts.contains { if case .tool = $0 { true } else { false } })
        #expect(first.parts.contains { if case .text(let t) = $0 { t.lowercased().contains("plum") } else { false } })
        #expect(w.chat(chat.id)?.sessionID != nil)

        #expect(w.send("What word did you just reply with? Reply with only that word.", in: chat.id))
        while w.isRunning(chat.id) { try await Task.sleep(for: .milliseconds(200)) }
        let second = try #require(w.messages(in: chat.id).last)
        #expect(second.parts.contains { if case .text(let t) = $0 { t.lowercased().contains("plum") } else { false } })
    }

    @Test(arguments: HarnessKind.allCases)
    func aRealPlanRunsToTheEnd(kind: HarnessKind) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "xbot-live-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "the secret word is plum\n".write(to: folder.appending(path: "note.txt"), atomically: true, encoding: .utf8)

        let installed = await HarnessLocator.installed()
        try #require(installed[kind] != nil, "\(kind.displayName) is not installed")
        let w = Workspace(store: .inMemory(), inbox: folder, discover: { installed.filter { $0.key == kind } })
        await w.refreshHarnesses()
        let chat = try #require(w.newChat(in: nil))
        w.setPlanMode(true, for: chat.id)
        w.setMode(.editFiles, for: chat.id)

        #expect(w.send("Copy the secret word from note.txt into a new file word.txt. Use exactly 2 steps.", in: chat.id))
        while w.isRunning(chat.id) { try await Task.sleep(for: .milliseconds(200)) }
        let found = try #require(w.latestPlan(in: chat.id))
        let (messageID, plan) = (found.messageID, found.plan)
        #expect(plan.status == .review, "\(plan.problem ?? "")")
        #expect(!plan.steps.isEmpty)

        #expect(w.runPlan(messageID, in: chat.id, steps: plan.steps))
        while w.isRunning(chat.id) { try await Task.sleep(for: .milliseconds(200)) }
        let ran = try #require(w.latestPlan(in: chat.id)?.plan)
        #expect(ran.status == .finished)
        #expect(ran.doneCount + ran.failedCount + ran.added >= plan.steps.count)
        let word = try String(contentsOf: folder.appending(path: "word.txt"), encoding: .utf8)
        #expect(word.lowercased().contains("plum"))
    }
}
