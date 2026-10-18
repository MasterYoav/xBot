import Foundation

/// Antigravity has no per-run flag for an MCP server, so xBot's is added to its own settings once
/// (`agy mcp add xbot -- <XBot> --mcp`), the first time an Agentic Mode turn runs on it, and can
/// be taken out again from Settings › Agents. The token still differs per turn: the server
/// inherits it from the `agy` process's environment, which HarnessBrain sets. Outside xBot the
/// server has no token and every tool says it can't act.
@MainActor
public final class AntigravityMCP {
    static let installedKey = "agentic.antigravityMCP"

    private let runner: any CommandRunner
    private let defaults: UserDefaults

    public init(runner: any CommandRunner = ProcessRunner(), defaults: UserDefaults = .standard) {
        self.runner = runner
        self.defaults = defaults
    }

    /// The XBot binary it was added with, if it was.
    public var installedPath: String? { defaults.string(forKey: Self.installedKey) }
    public var isInstalled: Bool { installedPath != nil }

    /// Adds xBot's server unless it's there for this binary already. True when it's there.
    @discardableResult
    public func ensureInstalled(agy: URL, xbot: URL, environment: [String: String]) async -> Bool {
        let path = xbot.path(percentEncoded: false)
        if installedPath == path { return true }
        // "--": the server's own "--mcp" isn't one of agy's flags.
        let result = await runner.run(agy, ["mcp", "add", "xbot", "--", path, "--mcp"], environment: environment,
                                      directory: nil, timeout: .seconds(30))
        guard result.succeeded else { return false }
        defaults.set(path, forKey: Self.installedKey)
        return true
    }

    @discardableResult
    public func remove(agy: URL, environment: [String: String]) async -> Bool {
        let result = await runner.run(agy, ["mcp", "remove", "xbot"], environment: environment, directory: nil,
                                      timeout: .seconds(30))
        defaults.removeObject(forKey: Self.installedKey)
        return result.succeeded
    }
}
