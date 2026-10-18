import Foundation
import Synchronization
import Testing
@testable import XBotTools

@Suite struct UnixSocketTests {
    /// Short: a Unix socket's path is limited to 104 bytes, and the temporary folder's is long.
    func socketPath() -> String { "/tmp/xbt-\(UUID().uuidString.prefix(8)).sock" }

    func listen(_ path: String, _ answer: @escaping @Sendable (ToolCall) async -> ToolResult) throws -> ToolSocketListener {
        let listener = ToolSocketListener(path: path) { call in await answer(call) }
        try listener.start()
        return listener
    }

    @Test func aCallReachesTheAppWithItsTokenAndTheAnswerComesBack() async throws {
        let path = socketPath()
        let seen = Mutex<[ToolCall]>([])
        let listener = try listen(path) { call in
            seen.withLock { $0.append(call) }
            return .text("crew: Forge")
        }
        defer { listener.stop() }
        let client = ToolClient(socketPath: path, token: "t-1")
        let result = await client.call("xbot_crew", arguments: ["x": 1])
        #expect(result == .text("crew: Forge"))
        #expect(seen.withLock { $0 } == [ToolCall(token: "t-1", tool: "xbot_crew", arguments: ["x": 1])])
    }

    @Test func theSocketIsOnlyForThisUser() throws {
        let path = socketPath()
        let listener = try listen(path) { _ in .text("") }
        defer { listener.stop() }
        let mode = try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        #expect(mode & 0o777 == 0o600)
    }

    @Test func stoppingRemovesTheSocket() throws {
        let path = socketPath()
        let listener = try listen(path) { _ in .text("") }
        #expect(FileManager.default.fileExists(atPath: path))
        listener.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func aStaleSocketFromACrashIsReplaced() async throws {
        let path = socketPath()
        FileManager.default.createFile(atPath: path, contents: Data("old".utf8))
        let listener = try listen(path) { _ in .text("fresh") }
        defer { listener.stop() }
        #expect(await ToolClient(socketPath: path, token: "t").call("x", arguments: [:]) == .text("fresh"))
    }

    @Test func withTheAppClosedEveryToolSaysSo() async {
        let result = await ToolClient(socketPath: socketPath(), token: "t").call("xbot_crew", arguments: [:])
        #expect(result.isError)
        #expect(result.text.contains("xBot isn't running"))
    }

    @Test func withoutATokenNothingIsSent() async throws {
        let path = socketPath()
        let calls = Mutex(0)
        let listener = try listen(path) { _ in calls.withLock { $0 += 1 }; return .text("") }
        defer { listener.stop() }
        let result = await ToolClient(socketPath: path, token: nil).call("xbot_crew", arguments: [:])
        #expect(result.isError)
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func callsRunSideBySide() async throws {
        let path = socketPath()
        let listener = try listen(path) { call in
            // The first waits for the second: a slow ask must not hold up a quick call.
            if call.tool == "slow" { try? await Task.sleep(for: .milliseconds(300)) }
            return .text(call.tool)
        }
        defer { listener.stop() }
        let client = ToolClient(socketPath: path, token: "t")
        async let slow = client.call("slow", arguments: [:])
        try await Task.sleep(for: .milliseconds(50))
        let started = ContinuousClock.now
        let quick = await client.call("quick", arguments: [:])
        #expect(quick == .text("quick"))
        #expect(ContinuousClock.now - started < .milliseconds(250))
        #expect(await slow == .text("slow"))
    }

    @Test func aBigAnswerArrivesWhole() async throws {
        let path = socketPath()
        let picture = Data((0..<600_000).map { UInt8($0 % 251) })
        let listener = try listen(path) { _ in ToolResult(content: [.image(picture, mimeType: "image/jpeg")]) }
        defer { listener.stop() }
        let result = await ToolClient(socketPath: path, token: "t").call("mac_screenshot", arguments: [:])
        #expect(result.content == [.image(picture, mimeType: "image/jpeg")])
    }

    @Test func aPathTooLongForASocketIsAnErrorNotACrash() {
        let long = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
        #expect(throws: (any Error).self) { try ToolSocketListener(path: long) { _ in .text("") }.start() }
    }
}
