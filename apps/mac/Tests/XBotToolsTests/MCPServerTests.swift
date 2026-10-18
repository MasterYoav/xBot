import Foundation
import Synchronization
import Testing
@testable import XBotTools

/// Answers every call from a script, and keeps what it was asked.
final class ScriptedForwarder: ToolForwarding {
    let asked = Mutex<[(String, JSONValue)]>([])
    let answer: @Sendable (String, JSONValue) -> ToolResult

    init(_ answer: @escaping @Sendable (String, JSONValue) -> ToolResult = { name, _ in .text("ran \(name)") }) {
        self.answer = answer
    }

    func call(_ name: String, arguments: JSONValue) async -> ToolResult {
        asked.withLock { $0.append((name, arguments)) }
        return answer(name, arguments)
    }
}

@Suite struct JSONValueTests {
    @Test func roundTripsEveryKind() throws {
        let text = #"{"a":[1,2.5,"x",true,null,{"b":false}]}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(value["a"]?[0] == .number(1))
        #expect(value["a"]?[3] == .bool(true))
        #expect(value["a"]?[4] == .null)
        #expect(value["a"]?[5]?["b"] == .bool(false))
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(again == value)
    }

    @Test func readsTypedValues() {
        let value: JSONValue = ["n": 3, "s": "hi", "b": true, "list": ["x", "y"]]
        #expect(value["n"]?.intValue == 3)
        #expect(value["s"]?.stringValue == "hi")
        #expect(value["b"]?.boolValue == true)
        #expect(value["list"]?.arrayValue?.compactMap(\.stringValue) == ["x", "y"])
        #expect(value["missing"] == nil)
        #expect(value.string("s") == "hi")
        #expect(value.string("n") == "3", "a number given where text was expected still reads")
    }
}

@Suite struct MCPServerTests {
    let catalog = [ToolSpec(name: "xbot_crew", description: "The crew.", properties: [:], required: [])]

    func server(_ forwarder: ScriptedForwarder = ScriptedForwarder()) -> MCPServer {
        MCPServer(tools: catalog, forwarder: forwarder)
    }

    func respond(_ server: MCPServer, _ line: String) async throws -> JSONValue {
        let reply = try #require(await server.handle(line))
        #expect(!reply.contains("\n"), "one response per line")
        return try JSONDecoder().decode(JSONValue.self, from: Data(reply.utf8))
    }

    @Test func initializeAnswersWithTheProtocolVersionAndTools() async throws {
        let reply = try await respond(server(), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude","version":"1"}}}"#)
        #expect(reply["jsonrpc"] == "2.0")
        #expect(reply["id"] == 1)
        #expect(reply["result"]?["protocolVersion"] == "2025-06-18")
        #expect(reply["result"]?["capabilities"]?["tools"] != nil)
        #expect(reply["result"]?["serverInfo"]?["name"] == "xbot")
    }

    @Test func anOlderSupportedVersionIsEchoedAndAnUnknownOneGetsOurs() async throws {
        let older = try await respond(server(), #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        #expect(older["id"] == "a")
        #expect(older["result"]?["protocolVersion"] == "2025-03-26")
        let unknown = try await respond(server(), #"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        #expect(unknown["result"]?["protocolVersion"] == .string(MCPServer.protocolVersion))
    }

    @Test func notificationsGetNoAnswer() async {
        #expect(await server().handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(await server().handle(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3}}"#) == nil)
    }

    @Test func pingAnswersEmpty() async throws {
        let reply = try await respond(server(), #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
        #expect(reply["result"] == .object([:]))
    }

    @Test func toolsListGivesTheCatalogWithSchemas() async throws {
        let reply = try await respond(server(), #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        let tools = try #require(reply["result"]?["tools"]?.arrayValue)
        #expect(tools.count == 1)
        #expect(tools[0]["name"] == "xbot_crew")
        #expect(tools[0]["description"] == "The crew.")
        #expect(tools[0]["inputSchema"]?["type"] == "object")
    }

    @Test func toolsCallForwardsAndWrapsTheResult() async throws {
        let forwarder = ScriptedForwarder()
        let reply = try await respond(server(forwarder), #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"xbot_crew","arguments":{"x":1}}}"#)
        #expect(reply["result"]?["content"]?[0]?["type"] == "text")
        #expect(reply["result"]?["content"]?[0]?["text"] == "ran xbot_crew")
        #expect(reply["result"]?["isError"] == false)
        #expect(forwarder.asked.withLock { $0.first?.1 } == ["x": 1])
    }

    @Test func anImageResultIsBase64JPEGContent() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let forwarder = ScriptedForwarder { _, _ in ToolResult(content: [.image(jpeg, mimeType: "image/jpeg"), .text("Main display")]) }
        let reply = try await respond(server(forwarder), #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"xbot_crew"}}"#)
        let first = try #require(reply["result"]?["content"]?[0])
        #expect(first["type"] == "image")
        #expect(first["mimeType"] == "image/jpeg")
        #expect(first["data"] == .string(jpeg.base64EncodedString()))
        #expect(reply["result"]?["content"]?[1]?["text"] == "Main display")
    }

    @Test func aToolErrorIsAResultNotAProtocolError() async throws {
        let forwarder = ScriptedForwarder { _, _ in .error("xBot isn't running.") }
        let reply = try await respond(server(forwarder), #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"xbot_crew"}}"#)
        #expect(reply["result"]?["isError"] == true)
        #expect(reply["error"] == nil)
    }

    @Test func unknownToolsMethodsAndGarbageAreProtocolErrors() async throws {
        let tool = try await respond(server(), #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"nope"}}"#)
        #expect(tool["error"]?["code"] == -32602)
        let method = try await respond(server(), #"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#)
        #expect(method["error"]?["code"] == -32601)
        #expect(method["id"] == 9)
        let garbage = try await respond(server(), "{not json")
        #expect(garbage["error"]?["code"] == -32700)
        #expect(garbage["id"] == .null)
        let noMethod = try await respond(server(), #"{"jsonrpc":"2.0","id":10}"#)
        #expect(noMethod["error"]?["code"] == -32600)
    }

    @Test func aBlankLineIsIgnored() async {
        #expect(await server().handle("   ") == nil)
    }
}

@Suite struct ToolCatalogTests {
    @Test func everyToolTheSpecNamesIsThereOnce() {
        let names = ToolCatalog.all.map(\.name)
        #expect(Set(names).count == names.count)
        for name in [
            "xbot_projects", "xbot_add_project", "xbot_chats", "xbot_start_chat", "xbot_read_chat", "xbot_crew",
            "xbot_hire", "xbot_hand_off", "xbot_automations", "xbot_save_automation", "xbot_run_automation",
            "xbot_notes", "xbot_write_note", "xbot_settings", "xbot_set_world", "xbot_set_appearance",
            "xbot_remember", "xbot_lessons", "xbot_ask", "mac_screenshot", "mac_ui", "mac_click", "mac_type",
            "mac_keys", "mac_scroll", "mac_open", "mac_apps", "mac_quit",
        ] {
            #expect(names.contains(name), "\(name)")
        }
    }

    @Test func everySchemaIsAnObjectWhoseRequiredPropertiesExist() {
        for tool in ToolCatalog.all {
            let schema = tool.inputSchema
            #expect(schema["type"] == "object", "\(tool.name)")
            let properties = schema["properties"]?.objectValue ?? [:]
            for required in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
                #expect(properties[required] != nil, "\(tool.name).\(required)")
            }
            #expect(!tool.description.isEmpty)
            #expect(tool.description.count < 600, "\(tool.name): descriptions go to the model on every turn")
        }
    }

    @Test func requiredArgumentsAreRequired() {
        func required(_ name: String) -> [String] {
            ToolCatalog.all.first { $0.name == name }?.inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        }
        #expect(required("xbot_add_project") == ["path"])
        #expect(Set(required("xbot_start_chat")) == ["agent", "message"])
        #expect(Set(required("xbot_remember")) == ["cue", "lesson", "confidence", "evidence"])
        #expect(required("xbot_ask") == ["question"])
        #expect(required("mac_quit") == ["app"])
        #expect(required("mac_type") == ["text"])
        #expect(required("mac_keys") == ["combo"])
    }
}
