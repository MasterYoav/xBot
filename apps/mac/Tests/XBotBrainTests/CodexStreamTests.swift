import Foundation
import Testing
@testable import XBotBrain

@Suite struct CodexStreamTests {
    @Test func aToolTurn() throws {
        let events = try fixtureLines("codex-tool-turn").flatMap(HarnessKind.codex.events(from:))
        #expect(events == [
            .session("01a11205-6008-78f2-91ed-0b83eef8ca4c"),
            .notice("Codex is ignoring 2 unrecognized configuration settings."),
            .text("I’ll read `a.txt` with a shell command."),
            .toolCall(id: "item_4", name: "Shell", summary: "cat a.txt"),
            .toolResult(id: "item_4", output: "hello\n", isError: false),
            .text("done"),
            .done,
        ])
    }

    @Test func aFailedCommandIsAnErrorResult() {
        let line = #"{"type":"item.completed","item":{"id":"i","type":"command_execution","command":"ls nope","aggregated_output":"ls: nope: No such file","exit_code":1,"status":"failed"}}"#
        #expect(HarnessKind.codex.events(from: line) == [.toolResult(id: "i", output: "ls: nope: No such file", isError: true)])
    }

    @Test func fileChangesShowTheirPaths() {
        let line = #"{"type":"item.completed","item":{"id":"f","type":"file_change","changes":[{"path":"a.txt","kind":"update"},{"path":"b.txt","kind":"add"}],"status":"completed"}}"#
        #expect(HarnessKind.codex.events(from: line) == [
            .toolCall(id: "f", name: "Edit", summary: "a.txt, b.txt"),
            .toolResult(id: "f", output: "", isError: false),
        ])
    }

    /// A top-level `error` can be a reconnect that recovers; only `turn.failed` ends the turn.
    @Test func onlyTurnFailedEndsTheTurn() {
        #expect(HarnessKind.codex.events(from: #"{"type":"error","message":"Reconnecting… 1/5"}"#) == [.notice("Reconnecting… 1/5")])
        #expect(HarnessKind.codex.events(from: #"{"type":"turn.failed","error":{"message":"usage limit reached"}}"#) == [.failed("usage limit reached")])
    }

    @Test func resumeArgumentsPutTheIDBeforeTheStdinMarker() {
        let request = TurnRequest(prompt: "x", directory: URL(filePath: "/tmp"), mode: .readOnly, resumeID: "t-1")
        #expect(HarnessKind.codex.arguments(for: request) == [
            "exec", "resume", "--json", "--skip-git-repo-check", "-c", "sandbox_mode=\"read-only\"", "t-1", "-",
        ])
    }
}
