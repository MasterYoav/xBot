import Foundation
import Testing
@testable import XBotEngine

/// What a tool call's arguments say it did.
///
/// `TOOL_CALL_START` carries only the tool's name, so an Activity row built from it alone says
/// "computer_navigate" and nothing about where. The arguments arrive separately as
/// `TOOL_CALL_ARGS`, and this is the translation from that JSON into the command, file and page
/// rows docs/09-ui-spec.md describes.
///
/// The rule throughout: say what the arguments actually show. A tool whose arguments are
/// unrecognised stays `.tool(name:)` rather than being forced into a richer case, because the
/// richer cases carry claims — an exit code says a command finished, a byte count says something
/// was written — and inventing either is worse than showing the tool's name.
@Suite
struct ToolArgumentsTests {
    private func kind(_ name: String, _ json: String) -> ActivityEntry.Kind {
        ToolArguments.kind(toolName: name, argumentsJSON: json)
    }

    @Test func aNavigationCarriesItsPage() {
        #expect(
            kind("computer_navigate", #"{"url":"https://airline.example/bookings"}"#)
                == .navigate(url: "https://airline.example/bookings")
        )
    }

    @Test func aWriteCarriesItsPathAndSize() {
        // The size comes from the content the agent supplied, and the content itself never leaves
        // this function — an agent may be saving something it was told in confidence.
        #expect(
            kind("write_file", #"{"path":"/workspace/notes.md","content":"hello"}"#)
                == .fileWrite(path: "/workspace/notes.md", bytes: 5)
        )
    }

    @Test func aReadCarriesItsPath() {
        #expect(kind("read_file", #"{"path":"/workspace/notes.md"}"#) == .fileRead(path: "/workspace/notes.md"))
    }

    /// An exit code is a claim about how a command ended, and the stream does not carry one —
    /// `TOOL_CALL_RESULT` is free text. So a shell call names the tool rather than asserting it
    /// succeeded.
    @Test func aCommandDoesNotInventAnExitCode() {
        #expect(kind("bash", #"{"command":"ls -la"}"#) == .tool(name: "bash"))
    }

    @Test func unrecognisedArgumentsKeepTheToolName() {
        #expect(kind("some_tool", #"{"whatever":1}"#) == .tool(name: "some_tool"))
        #expect(kind("some_tool", "not json") == .tool(name: "some_tool"))
        #expect(kind("some_tool", "") == .tool(name: "some_tool"))
    }

    /// A `url` that is not one must not become a page row — the panel would render it as a visited
    /// address, which is a claim about where the agent went.
    @Test func aUrlThatIsNotOneIsNotAPage() {
        #expect(kind("computer_navigate", #"{"url":""}"#) == .tool(name: "computer_navigate"))
        #expect(kind("computer_navigate", #"{"url":123}"#) == .tool(name: "computer_navigate"))
    }
}

@Suite
struct ToolSummaryTests {
    @Test func aSummaryNamesTheToolAndItsTarget() {
        #expect(
            ToolArguments.summary(toolName: "computer_navigate", argumentsJSON: #"{"url":"https://x.test/a"}"#)
                == "computer_navigate https://x.test/a"
        )
    }

    @Test func aToolWithNothingToShowIsJustItsName() {
        #expect(ToolArguments.summary(toolName: "think", argumentsJSON: "{}") == "think")
    }

    /// The whole argument blob is never the summary. It can hold whatever the agent was told, and
    /// the panel sits on screen next to whoever walks past.
    @Test func theArgumentsThemselvesAreNeverShown() {
        let secret = #"{"note":"the door code is 4417","path":"/workspace/a"}"#
        let summary = ToolArguments.summary(toolName: "write_file", argumentsJSON: secret)
        #expect(!summary.contains("4417"))
        #expect(summary.contains("/workspace/a"))
    }
}

/// Recognising the engine's "ask a person" tool, which is what the attention badge reads.
@Suite
struct AskPersonTests {
    @Test func theQuestionComesFromTheArguments() {
        // Not from the result — that is a sentence written for the model ("Ask it in your own words
        // now"), while the arguments carry what was actually asked.
        #expect(
            ToolArguments.questionForPerson(
                toolName: "ask_person",
                argumentsJSON: #"{"question":"Should I cancel the Lisbon flight?"}"#
            ) == "Should I cancel the Lisbon flight?"
        )
    }

    @Test func whyStandsInWhenNoQuestionWasGiven() {
        #expect(
            ToolArguments.questionForPerson(
                toolName: "ask_person",
                argumentsJSON: #"{"why":"the booking is non-refundable"}"#
            ) == "the booking is non-refundable"
        )
    }

    @Test func anyOtherToolIsNotAQuestion() {
        #expect(ToolArguments.questionForPerson(toolName: "bash", argumentsJSON: #"{"question":"x"}"#) == nil)
        #expect(ToolArguments.questionForPerson(toolName: "ask_person", argumentsJSON: "{}") == nil)
        #expect(ToolArguments.questionForPerson(toolName: "ask_person", argumentsJSON: "junk") == nil)
    }
}
