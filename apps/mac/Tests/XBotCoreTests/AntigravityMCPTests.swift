import Foundation
import Synchronization
import Testing
@testable import XBotCore

/// Answers every command from a script and keeps what it was asked.
final class AgyRunner: CommandRunner {
    let asked = Mutex<[[String]]>([])
    let status: Int32

    init(status: Int32 = 0) { self.status = status }

    func run(_ executable: URL, _ arguments: [String], environment: [String: String], directory: URL?,
             timeout: Duration) async -> CommandResult {
        asked.withLock { $0.append([executable.path] + arguments) }
        return CommandResult(status: status, output: "", error: status == 0 ? "" : "agy: no such server")
    }
}

@MainActor
@Suite struct AntigravityMCPTests {
    let agy = URL(filePath: "/opt/agy")
    let xbot = URL(filePath: "/Applications/xBot.app/Contents/MacOS/XBot")

    func defaults() -> UserDefaults {
        let name = "agy-mcp-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func addsXBotOnceThenRemembers() async {
        let runner = AgyRunner()
        let store = defaults()
        let mcp = AntigravityMCP(runner: runner, defaults: store)
        #expect(!mcp.isInstalled)
        #expect(await mcp.ensureInstalled(agy: agy, xbot: xbot, environment: [:]))
        #expect(await mcp.ensureInstalled(agy: agy, xbot: xbot, environment: [:]))
        #expect(runner.asked.withLock { $0 } == [["/opt/agy", "mcp", "add", "xbot", "--", xbot.path, "--mcp"]])
        #expect(mcp.isInstalled)
    }

    @Test func aMovedAppIsAddedAgain() async {
        let runner = AgyRunner()
        let mcp = AntigravityMCP(runner: runner, defaults: defaults())
        _ = await mcp.ensureInstalled(agy: agy, xbot: xbot, environment: [:])
        _ = await mcp.ensureInstalled(agy: agy, xbot: URL(filePath: "/Users/me/Applications/xBot.app/Contents/MacOS/XBot"), environment: [:])
        #expect(runner.asked.withLock { $0.count } == 2)
    }

    @Test func aFailedAddIsNotRemembered() async {
        let mcp = AntigravityMCP(runner: AgyRunner(status: 1), defaults: defaults())
        #expect(!(await mcp.ensureInstalled(agy: agy, xbot: xbot, environment: [:])))
        #expect(!mcp.isInstalled)
    }

    @Test func removingTakesItOutOfAntigravity() async {
        let runner = AgyRunner()
        let mcp = AntigravityMCP(runner: runner, defaults: defaults())
        _ = await mcp.ensureInstalled(agy: agy, xbot: xbot, environment: [:])
        #expect(await mcp.remove(agy: agy, environment: [:]))
        #expect(runner.asked.withLock { $0.last } == ["/opt/agy", "mcp", "remove", "xbot"])
        #expect(!mcp.isInstalled)
    }
}
