import Foundation
import Testing
@testable import XBotBrain

@Suite struct RateLimitsTests {
    @Test func claudeReportsBothWindows() {
        let line = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.55,"resetsAt":1791495000},"seven_day":{"utilization":0.11,"resetsAt":1791658800}}}}"#
        #expect(ClaudeStream.events(from: line) == [.limits(RateLimits(
            fiveHour: RateWindow(usedPercent: 55, resetsAt: Date(timeIntervalSince1970: 1791495000)),
            weekly: RateWindow(usedPercent: 11, resetsAt: Date(timeIntervalSince1970: 1791658800))))])
    }

    @Test func codexRolloutLine() {
        let line = #"{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":3.0,"window_minutes":300,"resets_at":1791495771},"secondary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1792082571},"plan_type":"plus"}}}"#
        #expect(CodexUsage.limits(fromLine: line) == RateLimits(
            fiveHour: RateWindow(usedPercent: 3, resetsAt: Date(timeIntervalSince1970: 1791495771)),
            weekly: RateWindow(usedPercent: 1, resetsAt: Date(timeIntervalSince1970: 1792082571)),
            plan: "ChatGPT Plus"))
    }

    @Test func codexLatestSkipsSessionsWithoutLimits() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "codex-\(UUID().uuidString)")
        let day = root.appending(path: "2026/10/08")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let with = #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40,"window_minutes":300,"resets_at":1}}}}"#
        try (with + "\n").write(to: day.appending(path: "rollout-2026-10-08T10-00-00-a.jsonl"), atomically: true, encoding: .utf8)
        try "{\"type\":\"session_meta\"}\n".write(to: day.appending(path: "rollout-2026-10-08T11-00-00-b.jsonl"), atomically: true, encoding: .utf8)
        #expect(CodexUsage.latest(in: root)?.fiveHour?.usedPercent == 40)
    }

    @Test func claudePlanFromOrganizationType() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "claude-\(UUID().uuidString).json")
        try #"{"oauthAccount":{"organizationType":"claude_max"}}"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(ClaudeAccount.plan(at: file) == "Claude Max")
        #expect(ClaudeAccount.isSignedIn(at: file))
    }
}
