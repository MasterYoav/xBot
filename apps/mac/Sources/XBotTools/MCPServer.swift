import Foundation

/// Where a tool call goes: the running app, over its socket (or a script, in tests).
public protocol ToolForwarding: Sendable {
    func call(_ name: String, arguments: JSONValue) async -> ToolResult
}

/// One tool as `tools/list` describes it to the model.
public struct ToolSpec: Equatable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    public init(name: String, description: String, properties: [String: JSONValue], required: [String]) {
        self.name = name
        self.description = description
        inputSchema = .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
        ])
    }

    var listing: JSONValue {
        ["name": .string(name), "description": .string(description), "inputSchema": inputSchema]
    }
}

/// The MCP server's side of JSON-RPC 2.0: one request line in, at most one response line out.
/// Stateless, so lines can be handled concurrently (a slow `xbot_ask` doesn't hold up a ping).
public struct MCPServer: Sendable {
    /// The version this server speaks first.
    public static let protocolVersion = "2025-06-18"
    /// Versions whose tool calls look the same to a tools-only server; a client asking for one of
    /// these gets it back.
    static let supportedVersions: Set<String> = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    public let tools: [ToolSpec]
    public let forwarder: any ToolForwarding
    public let version: String

    public init(tools: [ToolSpec], forwarder: any ToolForwarding, version: String = "1") {
        self.tools = tools
        self.forwarder = forwarder
        self.version = version
    }

    enum Code {
        static let parse = -32700
        static let invalidRequest = -32600
        static let methodNotFound = -32601
        static let invalidParams = -32602
    }

    /// The response to `line`, or nil for a notification (or a blank line).
    public func handle(_ line: String) async -> String? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
              message.objectValue != nil else {
            return Self.error(id: .null, code: Code.parse, message: "Parse error")
        }
        let id = message["id"]
        guard let method = message["method"]?.stringValue else {
            // A response from the client (we send no requests) or nonsense: answer only a request.
            return id.map { Self.error(id: $0, code: Code.invalidRequest, message: "Invalid request") }
        }
        // Notifications (no id) get no answer, whatever they are.
        guard let id else { return nil }
        let params = message["params"] ?? .object([:])

        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.stringValue ?? ""
            let version = Self.supportedVersions.contains(asked) ? asked : Self.protocolVersion
            return Self.result(id: id, [
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "xbot", "title": "xBot", "version": .string(self.version)],
                "instructions": "xBot's own tools: its projects, chats, crew, automations, notes and settings, and the Mac itself (screenshots, the screen through Accessibility, clicks, typing, keys, apps).",
            ])
        case "ping":
            return Self.result(id: id, .object([:]))
        case "tools/list":
            return Self.result(id: id, ["tools": .array(tools.map(\.listing))])
        case "tools/call":
            guard let name = params["name"]?.stringValue, tools.contains(where: { $0.name == name }) else {
                return Self.error(id: id, code: Code.invalidParams,
                                  message: "Unknown tool: \(params["name"]?.stringValue ?? "none")")
            }
            let arguments = params["arguments"] ?? .object([:])
            let result = await forwarder.call(name, arguments: arguments)
            return Self.result(id: id, result.mcp)
        default:
            return Self.error(id: id, code: Code.methodNotFound, message: "Method not found: \(method)")
        }
    }

    static func result(id: JSONValue, _ result: JSONValue) -> String {
        JSONValue.object(["jsonrpc": "2.0", "id": id, "result": result]).compactText
    }

    static func error(id: JSONValue, code: Int, message: String) -> String {
        JSONValue.object(["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]])
            .compactText
    }
}
