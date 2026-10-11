import Foundation
import Testing
@testable import XBotBrain

/// GitHub Copilot CLI 1.0.83, `--output-format json`, recorded on a real Mac (paths scrubbed).
@Suite struct CopilotStreamTests {
    func events(_ fixture: String) throws -> [BrainEvent] {
        try fixtureLines(fixture).flatMap(CopilotStream.events(from:))
    }

    @Test func aReadTurnStreamsTheAnswerAndItsTool() throws {
        let events = try events("copilot-read-turn")
        // Copilot reports its session only at the end, on `result`.
        #expect(events.suffix(2) == [.session("5123995a-22d1-4115-a97f-9da48cc63be1"), .done])
        let text = events.compactMap { if case .textDelta(let t) = $0 { t } else { nil } }.joined()
        #expect(text == "it says hello")
        #expect(events.contains { if case .toolCall(_, "Read", let summary, _) = $0 { summary.hasSuffix("a.txt") } else { false } })
        #expect(events.contains { if case .toolResult(_, let output, false) = $0 { output.hasPrefix("hello") } else { false } })
        #expect(events.last == .done)
    }

    /// Reasoning has events of its own and stays out of the reply; a denied tool is an error result.
    @Test func reasoningIsLeftOutAndADeniedToolIsAnError() throws {
        let events = try events("copilot-denied-turn")
        let text = events.compactMap { if case .textDelta(let t) = $0 { t } else { nil } }.joined()
        #expect(text.hasPrefix("I’m unable to complete"))
        #expect(events.contains { if case .toolCall(_, "Bash", let s, _) = $0 { s.contains("b.txt") } else { false } })
        #expect(events.contains { if case .toolResult(_, let output, true) = $0 { output.contains("Permission denied") } else { false } })
    }

    @Test func aFailedResultIsAFailure() {
        let line = #"{"type":"result","sessionId":"s","exitCode":1}"#
        #expect(CopilotStream.events(from: line).last.map { if case .failed = $0 { true } else { false } } == true)
        let error = #"{"type":"session.error","data":{"message":"Model is not available"}}"#
        #expect(CopilotStream.events(from: error) == [.failed("Model is not available")])
    }
}

/// Antigravity CLI 1.2.5 (`agy`, Google's successor to Gemini CLI), `--output-format stream-json`.
@Suite struct AntigravityStreamTests {
    @Test func aReadTurnStreamsTheAnswerAndItsTool() throws {
        let events = try fixtureLines("antigravity-read-turn").flatMap(AntigravityStream.events(from:))
        #expect(events.first == .session("f635f5d8-1588-4852-b3cf-2cc00526c88d"))
        let text = events.compactMap { if case .textDelta(let t) = $0 { t } else { nil } }.joined()
        #expect(text == "it says hello\n")
        let calls = events.filter { if case .toolCall = $0 { true } else { false } }
        #expect(calls.count == 1)
        #expect(events.contains { if case .toolCall(_, "Read", let s, _) = $0 { s.hasSuffix("a.txt") } else { false } })
        #expect(events.contains { if case .toolResult(_, "2 lines, 6 bytes", false) = $0 { true } else { false } })
        #expect(events.last == .done)
    }

    @Test func anUnsuccessfulResultIsAFailure() {
        let line = #"{"event":"result","result":{"status":"ERROR","response":"","error":"quota exceeded"}}"#
        #expect(AntigravityStream.events(from: line) == [.failed("quota exceeded")])
    }

    @Test func modelsAreReadFromItsList() throws {
        let url = try #require(Bundle.module.url(forResource: "antigravity-models", withExtension: "txt", subdirectory: "Fixtures"))
        let models = AntigravityStream.models(try String(contentsOf: url, encoding: .utf8))
        #expect(models.first?.id == "gemini-3.8-flash-high" && models.first?.name == "Gemini 3.8 Flash (High)")
        #expect(models.contains { $0.id == "gemini-3.1-pro-high" })
        #expect(!models.contains { $0.id.hasPrefix("Fetching") })
    }
}

@Suite struct NewHarnessArgumentTests {
    func request(_ mode: PermissionMode, resume: String? = nil, instructions: String? = nil, effort: Effort? = nil) -> TurnRequest {
        TurnRequest(prompt: "--help me", directory: URL(filePath: "/tmp"), model: "m1", mode: mode, resumeID: resume,
                    effort: effort, instructions: instructions)
    }

    /// Neither reads a prompt from stdin; attached to its flag, a prompt starting "-" is still a prompt.
    @Test func thePromptIsAttachedToItsFlag() {
        #expect(HarnessKind.copilot.arguments(for: request(.readOnly)).contains("--prompt=--help me"))
        #expect(HarnessKind.antigravity.arguments(for: request(.readOnly)).contains("--print=--help me"))
    }

    @Test func copilotPermissionsFollowTheMode() {
        let read = HarnessKind.copilot.arguments(for: request(.readOnly))
        #expect(!read.contains("--allow-all-tools") && !read.contains("--allow-tool"))
        let edit = HarnessKind.copilot.arguments(for: request(.editFiles))
        #expect(edit.contains("--allow-tool") && edit.contains("write") && !edit.contains("--allow-all-tools"))
        #expect(HarnessKind.copilot.arguments(for: request(.fullAccess)).contains("--allow-all-tools"))
    }

    /// Antigravity's plan mode reads but doesn't edit; its edit mode can't even read headless, so
    /// editing needs its full permissions (the composer says so).
    @Test func antigravityPermissionsFollowTheMode() {
        let read = HarnessKind.antigravity.arguments(for: request(.readOnly))
        #expect(read.contains("plan") && !read.contains("--dangerously-skip-permissions"))
        #expect(HarnessKind.antigravity.arguments(for: request(.editFiles)).contains("--dangerously-skip-permissions"))
        #expect(HarnessKind.antigravity.editingNeedsFullAccess && !HarnessKind.copilot.editingNeedsFullAccess)
    }

    @Test func resumeModelAndEffort() {
        let c = HarnessKind.copilot.arguments(for: request(.readOnly, resume: "s1", effort: .extra))
        #expect(c.contains("--resume") && c.contains("s1") && c.contains("--model") && c.contains("xhigh"))
        let a = HarnessKind.antigravity.arguments(for: request(.readOnly, resume: "c1", effort: .max))
        #expect(a.contains("--conversation") && a.contains("c1") && a.contains("--model"))
        #expect(a.firstIndex(of: "--effort").map { a[$0 + 1] } == "high")
    }

    /// No system-prompt option: who the agent is goes ahead of the prompt instead.
    @Test func instructionsGoAheadOfThePromptWhenThereIsNoFlag() {
        let a = HarnessKind.copilot.arguments(for: request(.readOnly, instructions: "You are Forge."))
        let prompt = a.first { $0.hasPrefix("--prompt=") } ?? ""
        #expect(prompt.contains("You are Forge.") && prompt.hasSuffix("--help me"))
        #expect(!HarnessKind.claude.needsInstructionsInPrompt && HarnessKind.copilot.needsInstructionsInPrompt)
    }

    @Test func onlyClaudeAndCodexGiveStructuredAnswers() {
        #expect(HarnessKind.claude.givesStructuredAnswers && HarnessKind.codex.givesStructuredAnswers)
        #expect(!HarnessKind.copilot.givesStructuredAnswers && !HarnessKind.antigravity.givesStructuredAnswers)
    }
}
