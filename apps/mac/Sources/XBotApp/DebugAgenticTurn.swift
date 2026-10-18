#if DEBUG
import AppKit
import Foundation
import XBotCore

/// `XBOT_DEBUG_AGENTIC_PROMPT="…"` (debug builds only): a turn with xBot's tools attached, as a
/// thread has it, in a chat with HeadMaster, written to `XBOT_DEBUG_AGENTIC_OUT` when it ends.
/// How the MCP server and the hook are checked end to end with a real CLI. Point it at a sandboxed
/// library (CFFIXED_USER_HOME), never a real one. `XBOT_DEBUG_AGENTIC_HARNESS` picks the CLI
/// (claude by default); `XBOT_DEBUG_AGENTIC_APPROVE=allow|deny` answers approvals as a script;
/// `XBOT_DEBUG_AGENTIC_QUIT=1` quits when done.
@MainActor
enum DebugAgenticTurn {
    static func startIfAsked(_ workspace: Workspace) {
        let env = ProcessInfo.processInfo.environment
        guard let prompt = env["XBOT_DEBUG_AGENTIC_PROMPT"], !prompt.isEmpty else { return }
        let out = URL(filePath: env["XBOT_DEBUG_AGENTIC_OUT"] ?? NSTemporaryDirectory() + "xbot-agentic.txt")
        let harness = env["XBOT_DEBUG_AGENTIC_HARNESS"].flatMap(HarnessKind.init(rawValue:)) ?? .claude
        let answer = env["XBOT_DEBUG_AGENTIC_APPROVE"]
        Task {
            await workspace.refreshHarnesses()
            guard let head = workspace.headMaster, let chat = workspace.talk(to: head.id) else {
                try? "No HeadMaster or no agent CLI.".write(to: out, atomically: true, encoding: .utf8)
                return
            }
            workspace.setHarness(harness, for: chat.id)
            workspace.debugMakeThread(chat.id)
            guard workspace.send(prompt, in: chat.id) else {
                try? "The turn didn't start: \(workspace.sendBlockedReason(chat.id) ?? "?")".write(to: out, atomically: true, encoding: .utf8)
                return
            }
            let started = Date.now
            var answered: [String] = []
            while workspace.isRunning(chat.id), Date.now.timeIntervalSince(started) < 600 {
                if let answer, let pending = workspace.approvals.pending.first(where: { $0.chatID == chat.id }) {
                    workspace.approvals.answer(pending.approval.id, allow: answer == "allow", by: "debug script")
                    answered.append("\(answer): \(pending.approval.summary) — \(pending.approval.detail)")
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            var lines = ["harness: \(harness.rawValue)", "seconds: \(Int(Date.now.timeIntervalSince(started)))"]
            lines += answered.map { "approval \($0)" }
            for message in workspace.messages(in: chat.id) {
                for part in message.parts {
                    let line: String = switch part {
                    case .text(let text): "\(message.role.rawValue): \(text)"
                    case .tool(let tool): "tool \(tool.name) \(tool.summary) → \(tool.isError ? "ERROR " : "")\((tool.output ?? "").prefix(1500))"
                    case .notice(let text): "notice: \(text)"
                    case .failure(let text): "failure: \(text)"
                    case .image(let image): "image: \(image.path) \(image.width)×\(image.height)"
                    case .approval(let approval): "approval card: \(approval.summary) [\(approval.state.rawValue) by \(approval.answeredBy ?? "-")]"
                    case .lesson(let text): "lesson: \(text)"
                    case .plan: "plan"
                    }
                    lines.append(line)
                }
            }
            try? lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
            if env["XBOT_DEBUG_AGENTIC_QUIT"] == "1" { NSApp.terminate(nil) }
        }
    }
}
#endif
