import Foundation
import Testing
@testable import XBotBrain

private var expectedPlan: NSDictionary { [
    "summary": "Cancel stale requests.",
    "steps": [["title": "Track the request in flight", "active": "Tracking the request in flight"]],
] }

private func json(_ text: String) -> NSDictionary? {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? NSDictionary
}

@Suite struct PlanStreamTests {
    /// Claude Code answers through a `StructuredOutput` tool and repeats the answer on the result
    /// line. The tool is plumbing, and so is the plan file plan mode writes: neither is a tool row.
    @Test func claudeAnswersOnTheResultLineAndHidesItsPlumbing() throws {
        let events = try fixtureLines("claude-plan-turn").flatMap(HarnessKind.claude.events(from:))
        let calls = events.compactMap { if case .toolCall(_, let name, _, _) = $0 { name } else { nil } }
        #expect(calls == ["Read"])
        guard case .structured(let text) = events[events.count - 2] else { Issue.record("no answer"); return }
        #expect(json(text) == expectedPlan)
        #expect(events.last == .done)
    }

    @Test func claudeWritesAndEditsCarryTheirSize() {
        let write = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w","name":"Write","input":{"file_path":"a.ts","content":"one\ntwo\nthree\n"}}]},"parent_tool_use_id":null}"#
        let edit = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"e","name":"Edit","input":{"file_path":"a.ts","old_string":"x","new_string":"y\nz"}}]},"parent_tool_use_id":null}"#
        #expect(HarnessKind.claude.events(from: write) == [.toolCall(id: "w", name: "Write", summary: "a.ts", size: "+3")])
        #expect(HarnessKind.claude.events(from: edit) == [.toolCall(id: "e", name: "Edit", summary: "a.ts", size: "+2")])
    }

    /// With a schema, Codex's answer is its last message. Earlier messages are still reply text.
    @Test func codexsLastMessageBecomesTheAnswer() throws {
        var tail = SchemaTail()
        let events = try fixtureLines("codex-plan-turn")
            .flatMap(HarnessKind.codex.events(from:))
            .flatMap { tail.process($0) }
        #expect(events.count == 6)
        #expect(events[0] == .session("c1"))
        #expect(events[1] == .text("I'll inspect the search code."))
        guard case .structured(let text) = events[4] else { Issue.record("no answer"); return }
        #expect(json(text) == expectedPlan)
        #expect(events[5] == .done)
    }

    @Test func aFailedTurnGivesBackTheHeldMessageAsText() {
        var tail = SchemaTail()
        #expect(tail.process(.text("partial")).isEmpty)
        #expect(tail.process(.failed("limit")) == [.text("partial"), .failed("limit")])
    }

    @Test func planningIsReadOnlyWhateverTheModeSays() {
        let request = TurnRequest(prompt: "x", directory: URL(filePath: "/tmp"), mode: .fullAccess,
                                  schema: "{}", planning: true)
        let claude = HarnessKind.claude.arguments(for: request)
        #expect(claude.contains("plan"))
        #expect(!claude.contains("bypassPermissions"))
        #expect(Array(claude.suffix(2)) == ["--json-schema", "{}"])
        let codex = HarnessKind.codex.arguments(for: request, schemaFile: URL(filePath: "/tmp/s.json"))
        #expect(codex.contains("sandbox_mode=\"read-only\""))
        #expect(Array(codex.suffix(3)) == ["--output-schema", "/tmp/s.json", "-"])
    }
}
