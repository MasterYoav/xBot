import Foundation
import Testing
import XBotBrain
@testable import XBotCore

/// What a scripted Mac has: which CLIs, which are signed in, which tools. Changed between calls
/// to stand in for an installer or a sign-in that ran.
final class ScriptedMac: @unchecked Sendable {
    private let lock = NSLock()
    private var _found: [HarnessKind: URL] = [:]
    private var _signedIn: [HarnessKind: SignInStatus] = [:]
    private var _tools: Set<String> = []
    private(set) var locateCalls = 0

    var found: [HarnessKind: URL] {
        get { lock.withLock { _found } }
        set { lock.withLock { _found = newValue } }
    }
    var signedIn: [HarnessKind: SignInStatus] {
        get { lock.withLock { _signedIn } }
        set { lock.withLock { _signedIn = newValue } }
    }
    var tools: Set<String> {
        get { lock.withLock { _tools } }
        set { lock.withLock { _tools = newValue } }
    }

    func install(_ kind: HarnessKind) { found[kind] = URL(filePath: "/Users/me/.local/bin/\(kind.executableName)") }

    var probes: AgentProbes {
        AgentProbes(
            locate: { [self] in
                lock.withLock { locateCalls += 1 }
                return AgentLocation(found: found, path: "/scripted/bin")
            },
            hasTool: { [self] name, _ in tools.contains(name) },
            signIn: { [self] kind, _, _ in signedIn[kind] ?? .signedOut }
        )
    }
}

@MainActor @Suite struct AgentSetupTests {
    @Test func everyCLIIsCheckingUntilDetectionFinishes() async {
        let mac = ScriptedMac()
        let setup = AgentSetup(probes: mac.probes)
        #expect(HarnessKind.allCases.allSatisfy { setup.state(of: $0) == .checking })
        await setup.detect()
        #expect(HarnessKind.allCases.allSatisfy { setup.state(of: $0) == .missing })
        #expect(!setup.anyReady)
    }

    @Test func detectionSortsEachCLIIntoItsState() async {
        let mac = ScriptedMac()
        mac.install(.claude)
        mac.install(.codex)
        mac.install(.antigravity)
        mac.signedIn = [.claude: .signedIn, .codex: .signedOut, .antigravity: .unknown]
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()
        #expect(setup.state(of: .claude) == .ready)
        #expect(setup.state(of: .codex) == .installed)
        #expect(setup.state(of: .copilot) == .missing)
        // No way to ask Antigravity without starting it: usable, sign-in confirmed on first use.
        #expect(setup.state(of: .antigravity) == .ready)
        #expect(setup.signInUnverified.contains(.antigravity))
        #expect(!setup.signInUnverified.contains(.claude))
        #expect(setup.anyReady)
    }

    @Test func installThenSignInEndsReady() async throws {
        let mac = ScriptedMac()
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()

        let install = try #require(setup.start(.install, for: .codex))
        #expect(install.command == "curl -fsSL https://chatgpt.com/codex/install.sh | sh")
        #expect(install.shellCommand == install.command)
        #expect(setup.state(of: .codex) == .installing)

        mac.install(.codex)
        await setup.finished(install, exitCode: 0)
        #expect(setup.state(of: .codex) == .installed)

        let signIn = try #require(setup.start(.signIn, for: .codex))
        #expect(signIn.command == "codex login")
        #expect(signIn.shellCommand == "'/Users/me/.local/bin/codex' login")
        #expect(setup.state(of: .codex) == .signingIn)

        mac.signedIn[.codex] = .signedIn
        await setup.finished(signIn, exitCode: 0)
        #expect(setup.state(of: .codex) == .ready)
        #expect(setup.anyReady)
    }

    @Test func anInstallerThatFailsKeepsTheReason() async throws {
        let mac = ScriptedMac()
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()
        let run = try #require(setup.start(.install, for: .claude))
        await setup.finished(run, exitCode: 7)
        guard case .failed(let reason) = setup.state(of: .claude) else {
            Issue.record("expected failed, got \(setup.state(of: .claude))")
            return
        }
        #expect(reason.contains("7"))
    }

    @Test func anInstallerThatExitsCleanlyButLeavesNothingFails() async throws {
        let mac = ScriptedMac()
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()
        let run = try #require(setup.start(.install, for: .copilot))
        await setup.finished(run, exitCode: 0)
        guard case .failed(let reason) = setup.state(of: .copilot) else {
            Issue.record("expected failed")
            return
        }
        #expect(reason.contains("copilot"))
    }

    @Test func aSignInThatDidNotFinishSaysSo() async throws {
        let mac = ScriptedMac()
        mac.install(.claude)
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()
        let run = try #require(setup.start(.signIn, for: .claude))
        await setup.finished(run, exitCode: 1)
        guard case .failed = setup.state(of: .claude) else {
            Issue.record("expected failed")
            return
        }
        // Try again signs in again, because the CLI is there.
        let retry = try #require(setup.retry(.claude))
        #expect(retry.purpose == .signIn)
    }

    @Test func cancellingReDetectsWithoutCallingItAFailure() async throws {
        let mac = ScriptedMac()
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()
        let run = try #require(setup.start(.install, for: .antigravity))
        let before = mac.locateCalls
        await setup.finished(run, exitCode: nil, cancelled: true)
        #expect(mac.locateCalls == before + 1)
        #expect(setup.state(of: .antigravity) == .missing)
    }

    @Test func aRunEndingReDetectsOtherCLIsToo() async throws {
        let mac = ScriptedMac()
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()
        let run = try #require(setup.start(.install, for: .claude))
        // The person installed Codex some other way meanwhile.
        mac.install(.claude)
        mac.install(.codex)
        mac.signedIn = [.claude: .signedIn, .codex: .signedIn]
        await setup.finished(run, exitCode: 0)
        #expect(setup.state(of: .claude) == .ready)
        #expect(setup.state(of: .codex) == .ready)
    }

    @Test func aMissingPackageManagerOffersTheDownloadPage() async throws {
        let mac = ScriptedMac()
        let npm = RequiredTool.npm
        let setup = AgentSetup(probes: mac.probes, recipes: { kind in
            var recipe = AgentInstaller.recipe(for: kind)
            if kind == .copilot { recipe.requires = [npm] }
            return recipe
        })
        await setup.detect()
        #expect(setup.state(of: .copilot) == .needsTool(name: "npm", url: npm.downloadPage))
        #expect(setup.start(.install, for: .copilot) == nil)
        #expect(setup.state(of: .copilot) == .needsTool(name: "npm", url: npm.downloadPage))

        mac.tools = ["npm"]
        await setup.detect()
        #expect(setup.state(of: .copilot) == .missing)
        #expect(setup.start(.install, for: .copilot) != nil)
    }

    @Test func retryInstallsWhenTheCLIIsStillMissing() async throws {
        let mac = ScriptedMac()
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()
        let run = try #require(setup.start(.install, for: .claude))
        await setup.finished(run, exitCode: 2)
        #expect(setup.retry(.claude)?.purpose == .install)
    }

    @Test func nothingStartsWhileARunIsGoing() async throws {
        let mac = ScriptedMac()
        let setup = AgentSetup(probes: mac.probes)
        await setup.detect()
        _ = try #require(setup.start(.install, for: .claude))
        #expect(setup.start(.install, for: .claude) == nil)
    }
}

@Suite struct AgentSignInCheckTests {
    func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "codexhome-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url.appending(path: ".codex"), withIntermediateDirectories: true)
        return url
    }

    /// Only that the file is there: it holds tokens, and xBot never opens it. (Unreadable here,
    /// and still counted.)
    @Test func codexAuthFilePresenceIsEnough() async throws {
        let home = try home()
        let auth = home.appending(path: ".codex/auth.json")
        FileManager.default.createFile(atPath: auth.path, contents: Data("{}".utf8),
                                       attributes: [.posixPermissions: 0o000])
        let status = await AgentProbes.codexSignIn(home: home, codexHome: nil, status: {
            Issue.record("shouldn't ask the CLI when the file is there")
            return 1
        })
        #expect(status == .signedIn)
    }

    /// Codex can keep its login in the Keychain instead of the file: then its own status command
    /// (exit 0 when signed in) decides.
    @Test func withoutTheFileCodexsStatusCommandDecides() async throws {
        let home = try home()
        #expect(await AgentProbes.codexSignIn(home: home, codexHome: nil, status: { 0 }) == .signedIn)
        #expect(await AgentProbes.codexSignIn(home: home, codexHome: nil, status: { 1 }) == .signedOut)
        #expect(await AgentProbes.codexSignIn(home: home, codexHome: nil, status: { nil }) == .signedOut)
    }

    @Test func codexHomeIsHonoured() async throws {
        let home = try home()
        let other = home.appending(path: "elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: other.appending(path: "auth.json").path, contents: Data())
        #expect(await AgentProbes.codexSignIn(home: home, codexHome: other.path, status: { 1 }) == .signedIn)
    }

    @Test func aProcessExitCodeIsReadAndATimeoutGivesNil() async {
        #expect(await AgentProbes.exitCode(of: URL(filePath: "/usr/bin/true"), arguments: [], environment: [:]) == 0)
        #expect(await AgentProbes.exitCode(of: URL(filePath: "/usr/bin/false"), arguments: [], environment: [:]) == 1)
        #expect(await AgentProbes.exitCode(of: URL(filePath: "/bin/sleep"), arguments: ["5"], environment: [:],
                                           timeout: .milliseconds(200)) == nil)
        #expect(await AgentProbes.exitCode(of: URL(filePath: "/nonexistent/x"), arguments: [], environment: [:]) == nil)
    }
}
