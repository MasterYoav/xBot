import Foundation

/// "Run when xBot is closed": a LaunchAgent that starts xBot's own binary headless every minute
/// (`XBot --automations-tick`). It runs what's due, waits for those runs, and quits; it does
/// nothing while the app is open, which runs them itself.
public enum AutomationHelper {
    public static let label = "dev.xbot.automations"
    public static let tickArgument = "--automations-tick"

    public static var plistURL: URL {
        URL.homeDirectory.appending(path: "Library/LaunchAgents/\(label).plist")
    }

    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    public static func plist(binary: URL) -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary.path, tickArgument],
            "StartInterval": 60,
            "RunAtLoad": false,
            "ProcessType": "Background",
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null",
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
    }

    /// Writes the agent and loads it. Throws with launchctl's words if loading fails.
    public static func install(binary: URL = Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])) throws {
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try? launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try plist(binary: binary).write(to: plistURL, options: .atomic)
        try launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    public static func uninstall() throws {
        _ = try? launchctl(["bootout", "gui/\(getuid())/\(label)"])
        if isInstalled { try FileManager.default.removeItem(at: plistURL) }
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            struct Failure: LocalizedError { let errorDescription: String? }
            throw Failure(errorDescription: "launchctl \(arguments.first ?? ""): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }
}
