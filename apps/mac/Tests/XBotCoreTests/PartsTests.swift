import Testing
import XBotBrain
@testable import XBotCore

@Suite struct PartsTests {
    @Test func deltasJoinAndToolsSplitText() {
        var parts: [Part] = []
        for event: BrainEvent in [
            .session("s"), .textDelta("Let me "), .textDelta("look."),
            .toolCall(id: "t", name: "Read", summary: "a.txt"),
            .toolResult(id: "t", output: "hello", isError: false),
            .textDelta("It says hello."), .done,
        ] { parts.apply(event) }
        #expect(parts == [
            .text("Let me look."),
            .tool(ToolPart(id: "t", name: "Read", summary: "a.txt", output: "hello", isError: false)),
            .text("It says hello."),
        ])
    }

    @Test func wholeTextBlocksStaySeparate() {
        var parts: [Part] = []
        parts.apply(.text("one")); parts.apply(.text("two"))
        #expect(parts == [.text("one"), .text("two")])
    }

    @Test func failureAndNoticeAreKept() {
        var parts: [Part] = []
        parts.apply(.notice("warn")); parts.apply(.failed("boom"))
        #expect(parts == [.notice("warn"), .failure("boom")])
    }
}
