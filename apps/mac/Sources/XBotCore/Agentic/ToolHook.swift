import Foundation
import XBotTools

/// `XBot --hook`: Claude Code's PreToolUse hook (its contract: the event as JSON on stdin; exit 0
/// lets the tool run, exit 2 blocks it with stderr as the reason). Safe calls are decided here
/// without the app; a risky one asks the app over the socket, which asks the person.
public enum ToolHook {
    public struct Decision: Equatable, Sendable {
        public var allow: Bool
        public var reason: String

        public static let allowed = Decision(allow: true, reason: "")
        public static func blocked(_ reason: String) -> Decision { Decision(allow: false, reason: reason) }

        /// Claude Code's exit code for it.
        public var exitCode: Int32 { allow ? 0 : 2 }
    }

    /// `input` is the hook's stdin. Input that can't be read can't be classified, so it isn't
    /// blocked: a change to the hook format must not stop every tool.
    public static func decide(_ input: Data, token: String?, ask: (ToolCall) async -> ToolResult) async -> Decision {
        guard let event = try? JSONDecoder().decode(JSONValue.self, from: input),
              let tool = event["tool_name"]?.stringValue else { return .allowed }
        let arguments = event["tool_input"] ?? .object([:])
        guard RiskRules.check(hookTool: tool, input: arguments) != nil else { return .allowed }
        guard let token, !token.isEmpty else {
            return .blocked("xBot couldn't ask the person about this (the turn has no xBot session), so it wasn't run.")
        }
        let answer = await ask(ToolCall(token: token, tool: tool, arguments: arguments, hook: true))
        guard answer.isError else { return .allowed }
        return .blocked(answer.text.isEmpty ? ToolHost.notAllowed : answer.text)
    }
}
