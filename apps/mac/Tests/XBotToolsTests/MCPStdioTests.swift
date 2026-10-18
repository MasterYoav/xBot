import Foundation
import Testing
@testable import XBotTools

@Suite struct MCPStdioTests {
    /// The whole headless server as a CLI meets it: stdio JSON-RPC, through the socket client, to a
    /// fake app.
    @Test func aSessionOverPipesReachesTheFakeApp() async throws {
        let path = "/tmp/xbt-\(UUID().uuidString.prefix(8)).sock"
        let app = ToolSocketListener(path: path) { call in
            call.token == "good" ? .text("Forge, Builder") : .error("Unknown session.")
        }
        try app.start()
        defer { app.stop() }

        let input = Pipe(), output = Pipe()
        let server = MCPServer(tools: ToolCatalog.all, forwarder: ToolClient(socketPath: path, token: "good"))
        let serving = Task { await MCPStdio.serve(server, input: input.fileHandleForReading, output: output.fileHandleForWriting) }
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"xbot_crew","arguments":{}}}"#,
        ]
        try input.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
        try input.fileHandleForWriting.close()
        await serving.value
        try output.fileHandleForWriting.close()

        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let replies = try text.split(separator: "\n").map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        #expect(replies.count == 3, "the notification gets no answer")
        let byID = Dictionary(uniqueKeysWithValues: replies.compactMap { reply in reply["id"]?.intValue.map { ($0, reply) } })
        #expect(byID[1]?["result"]?["protocolVersion"] == "2025-06-18")
        #expect(byID[2]?["result"]?["tools"]?.arrayValue?.count == ToolCatalog.all.count)
        #expect(byID[3]?["result"]?["content"]?[0]?["text"] == "Forge, Builder")
    }
}
