import Foundation
import Testing
@testable import XBotBrain

@Suite struct ClaudeStreamTests {
    @Test func aToolTurnBecomesSessionToolCallResultAndDone() throws {
        let events = try fixtureLines("claude-tool-turn").flatMap(HarnessKind.claude.events(from:))
        #expect(events == [
            .session("a5984ed8-b509-4f00-9d68-025be0f5f129"),
            .toolCall(id: "toolu_01", name: "Read", summary: "/private/tmp/work/a.txt"),
            .toolResult(id: "toolu_01", output: "1\thello\n2\t", isError: false),
            .done,
        ])
    }

    /// Text comes only from the deltas. The whole `assistant` message repeats it, and taking both
    /// would print every reply twice.
    @Test func partialTextComesFromDeltasOnly() throws {
        let events = try fixtureLines("claude-partial-turn").flatMap(HarnessKind.claude.events(from:))
        #expect(events == [
            .session("3828fcae-6391-4c6c-b69f-f7bb9354d5cf"),
            .textDelta("hi "), .textDelta("there"),
            .done,
        ])
    }

    @Test func anErrorResultIsAFailureWithItsReason() {
        let line = #"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["Credit balance is too low"]}"#
        #expect(HarnessKind.claude.events(from: line) == [.failed("Credit balance is too low")])
    }

    @Test func aSubagentsTextIsNotTheReply() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"inner"}},"parent_tool_use_id":"toolu_9"}"#
        #expect(HarnessKind.claude.events(from: line).isEmpty)
    }

    @Test func toolResultContentMayBeABlockArray() {
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":[{"type":"text","text":"no such file"}]}]},"parent_tool_use_id":null}"#
        #expect(HarnessKind.claude.events(from: line) == [.toolResult(id: "t1", output: "no such file", isError: true)])
    }

    @Test func garbageIsIgnored() {
        #expect(HarnessKind.claude.events(from: "not json").isEmpty)
        #expect(HarnessKind.claude.events(from: "").isEmpty)
        #expect(HarnessKind.claude.events(from: "[1,2]").isEmpty)
    }

    @Test func argumentsNeverCarryThePrompt() {
        let request = TurnRequest(
            prompt: "--help me", directory: URL(filePath: "/tmp"), model: "opus",
            mode: .editFiles, resumeID: "abc"
        )
        #expect(HarnessKind.claude.arguments(for: request) == [
            "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--permission-mode", "acceptEdits", "--model", "opus", "--resume", "abc",
        ])
    }
}
