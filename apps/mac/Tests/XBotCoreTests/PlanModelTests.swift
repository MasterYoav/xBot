import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@Suite struct PlanModelTests {
    @Test func toolsRecordWhenTheyStartAndEndAndHowBig() {
        var tools: [ToolPart] = []
        let start = Date(timeIntervalSinceReferenceDate: 10)
        let end = Date(timeIntervalSinceReferenceDate: 11.4)
        tools.apply(.toolCall(id: "r", name: "Read", summary: "a.ts"), at: start)
        tools.apply(.toolResult(id: "r", output: "1\ta\n2\tb\n3\tc", isError: false), at: end)
        #expect(tools == [ToolPart(id: "r", name: "Read", summary: "a.ts", output: "1\ta\n2\tb\n3\tc",
                                   isError: false, size: "3 lines", startedAt: start, endedAt: end)])
    }

    @Test func aSizeFromTheCallIsKept() {
        var tools: [ToolPart] = []
        tools.apply(.toolCall(id: "w", name: "Write", summary: "a.ts", size: "+39"))
        tools.apply(.toolResult(id: "w", output: "File created", isError: false))
        #expect(tools.first?.size == "+39")
    }

    @Test func theSummaryLineReadsLikeTheRecording() {
        func tool(_ name: String) -> ToolPart { ToolPart(id: UUID().uuidString, name: name, summary: "", output: "", isError: false) }
        let tools = ["Read", "WebSearch", "Read", "Read", "LS", "Read"].map(tool)
        #expect(ToolLabel.summary(of: tools) == "Read 4 files, searched the web once, listed a folder")
        #expect(ToolLabel.summary(of: [tool("Bash"), tool("Bash"), tool("Write"), tool("Mystery")])
                == "Ran 2 commands, created a file, used 1 other tool")
        #expect(ToolLabel.summary(of: []) == "")
    }

    @Test func verbsFollowTheToolsState() {
        #expect(ToolLabel.verb("Read", running: true) == "Reading")
        #expect(ToolLabel.verb("Read", running: false) == "Read")
        #expect(ToolLabel.verb("Shell", running: true) == "Running")
        #expect(ToolLabel.verb("Frobnicate", running: false) == "Frobnicate")
    }

    @Test func answersDecodeAndBadOnesDoNot() {
        let plan = PlanAnswer.decode(#"{"summary":"S","steps":[{"title":"Do it","active":"Doing it"}]}"#)
        #expect(plan?.steps.map(\.title) == ["Do it"])
        #expect(PlanAnswer.decode("not json") == nil)
        let step = StepAnswer.decode(#"{"outcome":"failed","note":"1 failed","add":[{"title":"Fix","active":"Fixing"}]}"#)
        #expect(step?.failed == true)
        #expect(step?.add.map(\.title) == ["Fix"])
    }

    @Test func schemasAreValidJSONAndStrict() throws {
        for schema in [PlanSchemas.plan, PlanSchemas.step] {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
            #expect(object["additionalProperties"] as? Bool == false)
        }
    }

    @Test func aPlanRoundTripsThroughJSONInAMessage() throws {
        var plan = Plan(prompt: "Fix search", status: .running)
        plan.steps = [PlanStep(title: "Find it", active: "Finding it")]
        let parts: [Part] = [.plan(plan)]
        let decoded = try JSONDecoder().decode([Part].self, from: JSONEncoder().encode(parts))
        #expect(decoded == parts)
        #expect(ChatMessage(chatID: UUID(), role: .assistant, parts: decoded).plan == plan)
    }

    /// Rows saved before tools had sizes and times still decode.
    @Test func anOlderToolRowStillDecodes() throws {
        let old = #"[{"tool":{"_0":{"id":"t","name":"Read","summary":"a","output":"x","isError":false}}}]"#
        let parts = try JSONDecoder().decode([Part].self, from: Data(old.utf8))
        guard case .tool(let tool) = parts.first else { Issue.record("not a tool"); return }
        #expect(tool.size == nil)
    }

    @Test func countsAndCancellation() {
        var plan = Plan(prompt: "p", status: .stopped)
        plan.steps = [PlanStep(title: "a", active: "a", status: .done),
                      PlanStep(title: "b", active: "b", status: .failed),
                      PlanStep(title: "c", active: "c")]
        #expect(plan.doneCount == 1)
        #expect(plan.failedCount == 1)
        #expect(plan.isCancelled)
        plan.startedAt = .now
        #expect(!plan.isCancelled)
    }
}
