import Foundation

/// What a tool call's arguments say it did.
///
/// `TOOL_CALL_START` carries only the tool's name, so an Activity row built from it alone reads
/// "computer_navigate" and says nothing about where. The arguments arrive separately as
/// `TOOL_CALL_ARGS`, and this is the translation into the command, file and page rows
/// docs/09-ui-spec.md describes.
///
/// **Say what the arguments show, and nothing more.** A tool whose arguments are unrecognised stays
/// `.tool(name:)` rather than being forced into a richer case, because the richer cases each carry a
/// claim — an exit code says a command finished, a byte count says something was written — and
/// asserting either without evidence is worse than showing the tool's name.
public enum ToolArguments: Sendable {
    /// Keys an agent's tools use for the thing being acted on, in the order they are preferred.
    private static let targetKeys = ["url", "path", "file", "command", "query"]

    public static func kind(toolName: String, argumentsJSON: String) -> ActivityEntry.Kind {
        guard let arguments = object(from: argumentsJSON) else { return .tool(name: toolName) }

        if let url = string(arguments["url"]) {
            return .navigate(url: url)
        }

        if let path = string(arguments["path"]) ?? string(arguments["file"]) {
            // Content present means it was written. Its length is the size; its text is never read
            // out of here — an agent may be saving something it was told in confidence, and the
            // panel is on screen next to whoever walks past.
            if let content = string(arguments["content"]) ?? string(arguments["text"]) {
                return .fileWrite(path: path, bytes: content.utf8.count)
            }
            return .fileRead(path: path)
        }

        /*
         * A command names its tool rather than claiming an outcome.
         *
         * `.command(exitCode:)` asserts how the command ended, and nothing on this stream says:
         * `TOOL_CALL_RESULT` carries free text, not a status. Defaulting to zero would put a tick
         * beside every command the agent ran, including the ones that failed.
         */
        return .tool(name: toolName)
    }

    /// One line for the panel: the tool, and the thing it acted on.
    ///
    /// Never the argument blob itself. It can hold whatever the agent was told, and this row sits
    /// on screen beside whoever walks past.
    public static func summary(toolName: String, argumentsJSON: String) -> String {
        guard let arguments = object(from: argumentsJSON) else { return toolName }
        for key in targetKeys {
            if let value = string(arguments[key]), !value.isEmpty {
                return "\(toolName) \(value)"
            }
        }
        return toolName
    }

    private static func object(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    /// A string that is actually one, and actually has something in it.
    ///
    /// A number where a URL was expected is not a page the agent visited, and an empty string is
    /// not a path — either would render as a claim the arguments do not support.
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}
