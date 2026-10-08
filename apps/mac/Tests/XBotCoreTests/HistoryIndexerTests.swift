import Foundation
import Testing
@testable import XBotCore

@Suite struct HistoryIndexerTests {
    let utc = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    func user(_ ts: String, _ text: String = "do it") -> String {
        #"{"type":"user","timestamp":"\#(ts)","message":{"role":"user","content":"\#(text)"}}"#
    }

    func toolResult(_ ts: String) -> String {
        #"{"type":"user","timestamp":"\#(ts)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"ok"}]}}"#
    }

    func assistant(_ ts: String, id: String, tokens: Int = 10, tool: String? = nil, skill: String? = nil) -> String {
        let input = skill.map { #""skill":"\#($0)""# } ?? ""
        let block = tool.map { #"{"type":"tool_use","id":"t","name":"\#($0)","input":{\#(input)}}"# } ?? #"{"type":"text","text":"hi"}"#
        return #"{"type":"assistant","timestamp":"\#(ts)","effort":"medium","cwd":"/p/xBot","message":{"id":"\#(id)","usage":{"input_tokens":\#(tokens),"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[\#(block)]}}"#
    }

    @Test func aMessageSplitAcrossLinesCountsOnce() {
        var tally = HistoryTally(), carry = FileCarry()
        for line in [user("2026-10-08T10:00:00.000Z"),
                     assistant("2026-10-08T10:00:05.000Z", id: "m1", tokens: 100),
                     assistant("2026-10-08T10:00:06.000Z", id: "m1", tokens: 100, tool: "Read")] {
            tally.claude(line, carry: &carry, calendar: utc)
        }
        let day = tally.days[DayKey(day: "2026-10-08", agent: .claude)]
        #expect(day?.tokens == 100 && day?.tasks == 1)
        #expect(tally.counts[CountKey(kind: .tool, name: "Read")] == 1)
    }

    @Test func taskLengthRunsFromTheQuestionToTheLastReply() {
        var tally = HistoryTally(), carry = FileCarry()
        for line in [user("2026-10-08T10:00:00.000Z"),
                     assistant("2026-10-08T10:00:10.000Z", id: "a"),
                     toolResult("2026-10-08T10:00:20.000Z"),
                     assistant("2026-10-08T10:01:40.000Z", id: "b"),
                     user("2026-10-08T11:00:00.000Z"),
                     assistant("2026-10-08T11:00:05.000Z", id: "c")] {
            tally.claude(line, carry: &carry, calendar: utc)
        }
        let day = tally.days[DayKey(day: "2026-10-08", agent: .claude)]
        #expect(day?.tasks == 2)
        #expect(day?.longestTask == 100)
    }

    @Test func aLongSilenceEndsTheTask() {
        var tally = HistoryTally(), carry = FileCarry()
        for line in [user("2026-10-08T10:00:00.000Z"),
                     assistant("2026-10-08T10:01:00.000Z", id: "a"),
                     assistant("2026-10-09T12:00:00.000Z", id: "b")] {
            tally.claude(line, carry: &carry, calendar: utc)
        }
        #expect(tally.days[DayKey(day: "2026-10-08", agent: .claude)]?.longestTask == 60)
    }

    @Test func skillsEffortsAndProjectsAreCounted() {
        var tally = HistoryTally(), carry = FileCarry()
        tally.claude(user("2026-10-08T10:00:00.000Z"), carry: &carry, calendar: utc)
        tally.claude(assistant("2026-10-08T10:00:01.000Z", id: "a", tool: "Skill", skill: "brainstorming"), carry: &carry, calendar: utc)
        #expect(tally.counts[CountKey(kind: .skill, name: "brainstorming")] == 1)
        #expect(tally.counts[CountKey(kind: .effort, name: "medium")] == 1)
        #expect(tally.projects["/p/xBot"]?.tokens == 10)
    }

    @Test func codexTokensAreTheGrowthOfTheRunningTotal() {
        var tally = HistoryTally(), carry = FileCarry()
        let lines = [
            #"{"timestamp":"2026-10-08T10:00:00.000Z","type":"turn_context","payload":{"cwd":"/p/app","model":"gpt-6.1","effort":"high"}}"#,
            #"{"timestamp":"2026-10-08T10:00:01.000Z","type":"response_item","payload":{"type":"function_call","name":"shell"}}"#,
            #"{"timestamp":"2026-10-08T10:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":500}}}}"#,
            #"{"timestamp":"2026-10-08T10:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":500}}}}"#,
            #"{"timestamp":"2026-10-08T10:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":800}}}}"#,
            #"{"timestamp":"2026-10-08T10:00:05.000Z","type":"event_msg","payload":{"type":"task_complete","duration_ms":16365}}"#,
        ]
        for line in lines { tally.codex(line, carry: &carry, calendar: utc) }
        let day = tally.days[DayKey(day: "2026-10-08", agent: .codex)]
        #expect(day?.tokens == 800 && day?.tasks == 1 && day?.longestTask == 16.365)
        #expect(tally.counts[CountKey(kind: .tool, name: "shell")] == 1)
        #expect(tally.counts[CountKey(kind: .effort, name: "high")] == 1)
        #expect(tally.projects["/p/app"]?.tokens == 800)
    }

    @Test func aPartialLastLineWaitsForTheNextPass() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hist-\(UUID().uuidString)")
        let claude = root.appending(path: "claude/proj")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let file = claude.appending(path: "s.jsonl")
        let first = user("2026-10-08T10:00:00.000Z") + "\n"
        let second = assistant("2026-10-08T10:00:05.000Z", id: "m1", tokens: 42)
        try (first + second.prefix(30)).write(to: file, atomically: true, encoding: .utf8)
        let indexer = try HistoryIndexer(database: Database(), claude: root.appending(path: "claude"),
                                         codex: root.appending(path: "codex"), calendar: utc)
        await indexer.index()
        #expect(await indexer.summary().days["2026-10-08"] == nil)
        try (first + second + "\n").write(to: file, atomically: true, encoding: .utf8)
        await indexer.index()
        await indexer.index()  // a pass with nothing new adds nothing
        let summary = await indexer.summary()
        #expect(summary.days["2026-10-08"] == 42)
        #expect(summary.tasksByAgent[.claude] == 1)
        #expect(summary.found == [.claude])
    }
}
