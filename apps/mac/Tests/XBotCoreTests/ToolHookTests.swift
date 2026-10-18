import Foundation
import Testing
import XBotTools
@testable import XBotCore

@Suite struct ToolHookTests {
    func event(_ tool: String, _ input: String) -> Data {
        Data(#"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"\#(tool)","tool_input":\#(input),"tool_use_id":"t"}"#.utf8)
    }

    @Test func aSafeCommandRunsWithoutAskingTheApp() async {
        var asked = 0
        let decision = await ToolHook.decide(event("Bash", #"{"command":"git status"}"#), token: "t") { _ in asked += 1; return .text("") }
        #expect(decision == .allowed)
        #expect(decision.exitCode == 0)
        #expect(asked == 0, "no socket round trip for a safe call")
    }

    @Test func aRiskyCommandAsksTheAppWithTheToken() async {
        var calls: [ToolCall] = []
        let decision = await ToolHook.decide(event("Bash", #"{"command":"git push origin main"}"#), token: "tok") { call in
            calls.append(call)
            return .text("")
        }
        #expect(decision == .allowed)
        #expect(calls == [ToolCall(token: "tok", tool: "Bash", arguments: ["command": "git push origin main"], hook: true)])
    }

    @Test func aRefusalBlocksWithTheReason() async {
        let decision = await ToolHook.decide(event("Bash", #"{"command":"rm -rf build"}"#), token: "tok") { _ in .error(ToolHost.notAllowed) }
        #expect(!decision.allow)
        #expect(decision.exitCode == 2)
        #expect(decision.reason == ToolHost.notAllowed)
    }

    @Test func withTheAppClosedARiskyCommandIsBlocked() async {
        let decision = await ToolHook.decide(event("Bash", #"{"command":"rm -rf build"}"#), token: "tok") { _ in .error(ToolClient.notRunning) }
        #expect(decision.exitCode == 2)
        #expect(decision.reason.contains("xBot isn't running"))
    }

    @Test func withoutATokenARiskyCommandIsBlocked() async {
        let decision = await ToolHook.decide(event("Bash", #"{"command":"git push"}"#), token: nil) { _ in .text("") }
        #expect(decision.exitCode == 2)
    }

    @Test func unreadableInputIsNotBlocked() async {
        #expect(await ToolHook.decide(Data("nonsense".utf8), token: "t") { _ in .error("x") } == .allowed)
    }
}
