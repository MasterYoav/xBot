import Foundation
import Testing
@testable import XBotBrain

@Suite struct HarnessLocatorTests {
    @Test func findsOnlyExecutables() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let claude = dir.appending(path: "claude")
        try "#!/bin/sh\n".write(to: claude, atomically: true, encoding: .utf8)
        try "".write(to: dir.appending(path: "codex"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

        #expect(HarnessLocator.find(.claude, in: "/nope:\(dir.path)") == claude)
        #expect(HarnessLocator.find(.codex, in: dir.path) == nil)
    }

    /// Launched from Claude Code during development, these are set, and a nested `claude` refuses
    /// to start inside what it thinks is its own session.
    @Test func environmentDropsClaudeCodesOwnMarkers() {
        let env = HarnessLocator.environment(path: "/a:/b", base: [
            "HOME": "/Users/me", "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "PATH": "/usr/bin",
        ])
        #expect(env == ["HOME": "/Users/me", "PATH": "/a:/b"])
    }

    @Test func searchPathPutsTheShellsFirstAndAddsTheUsualPlaces() {
        let path = HarnessLocator.searchPath(loginShellPath: "/custom/bin:/usr/bin", home: "/Users/me")
        let parts = path.split(separator: ":").map(String.init)
        #expect(parts.first == "/custom/bin")
        #expect(parts.contains("/Users/me/.local/bin"))
        #expect(parts.contains("/opt/homebrew/bin"))
        #expect(Set(parts).count == parts.count)
    }

    @Test func loginShellPathReadsBetweenMarkersAndIgnoresNoise() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shell = dir.appending(path: "fakesh")
        // Prints a greeting the way a chatty .zshrc does, then runs its last argument, the command.
        try "#!/bin/sh\necho 'welcome back!'\nfor a; do last=$a; done\nPATH=/from/shell:/usr/bin /bin/sh -c \"$last\"\n"
            .write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        #expect(await HarnessLocator.loginShellPath(shell: shell.path) == "/from/shell:/usr/bin")
    }
}
