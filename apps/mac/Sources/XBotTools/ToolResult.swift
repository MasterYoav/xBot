import Foundation

/// What a tool gives back: text and pictures, or an error the model reads and can act on.
public struct ToolResult: Codable, Equatable, Sendable {
    public enum Content: Codable, Equatable, Sendable {
        case text(String)
        /// Raw bytes; base64 only on the way to the model.
        case image(Data, mimeType: String)
    }

    public var content: [Content]
    public var isError: Bool

    public init(content: [Content], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ text: String) -> ToolResult { ToolResult(content: [.text(text)]) }
    public static func error(_ text: String) -> ToolResult { ToolResult(content: [.text(text)], isError: true) }

    /// Every text block, joined.
    public var text: String {
        content.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
    }

    /// As MCP's `tools/call` result has it.
    public var mcp: JSONValue {
        .object([
            "content": .array(content.map { item in
                switch item {
                case .text(let text): ["type": "text", "text": .string(text)]
                case .image(let data, let mimeType):
                    ["type": "image", "data": .string(data.base64EncodedString()), "mimeType": .string(mimeType)]
                }
            }),
            "isError": .bool(isError),
        ])
    }
}

/// One call from `XBot --mcp` (or `XBot --hook`) to the app over its socket, one JSON line each
/// way. The token says which turn is asking; the app knows the chat and agent behind it.
public struct ToolCall: Codable, Equatable, Sendable {
    public var token: String
    public var tool: String
    public var arguments: JSONValue
    /// A Claude Code PreToolUse hook asking whether one of the CLI's own tools may run. The answer
    /// is an empty result to allow, an error to block (its text the reason).
    public var hook: Bool?

    public init(token: String, tool: String, arguments: JSONValue, hook: Bool? = nil) {
        self.token = token
        self.tool = tool
        self.arguments = arguments
        self.hook = hook
    }
}
