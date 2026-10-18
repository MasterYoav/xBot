import Foundation
import Observation
import XBotBrain

/// Whether a CLI is signed in, as far as xBot can tell without reading a token.
public enum SignInStatus: Equatable, Sendable {
    case signedIn, signedOut
    /// The CLI keeps its session where xBot can't look (the Keychain) and documents no status
    /// command: it signs in on first use.
    case unknown
}

/// One CLI's place on the agents step.
public enum AgentState: Equatable, Sendable {
    case checking
    case missing
    case installing
    /// Installed, not signed in.
    case installed
    case signingIn
    case ready
    /// The official installer needs a program this Mac doesn't have; offer its download page.
    case needsTool(name: String, url: URL)
    case failed(String)
}

/// What a lookup found: each CLI's binary, and the PATH it was found on.
public struct AgentLocation: Sendable {
    public var found: [HarnessKind: URL]
    public var path: String

    public init(found: [HarnessKind: URL], path: String) {
        self.found = found
        self.path = path
    }
}

/// An install or a sign-in, run in the install sheet's terminal.
public struct SetupRun: Identifiable, Equatable, Sendable {
    public enum Purpose: Sendable { case install, signIn }

    public let id = UUID()
    public let kind: HarnessKind
    public let purpose: Purpose
    /// What the sheet shows: the documented command.
    public let command: String
    /// What the login shell runs.
    public let shellCommand: String
    /// The PATH the CLIs were found on, for the shell to start with.
    public let path: String
}

/// How AgentSetup looks at the Mac. Scripted in tests.
public struct AgentProbes: Sendable {
    public var locate: @Sendable () async -> AgentLocation
    /// Whether a program is on the PATH.
    public var hasTool: @Sendable (_ name: String, _ path: String) -> Bool
    /// Whether the CLI found at the URL is signed in.
    public var signIn: @Sendable (_ kind: HarnessKind, _ executable: URL, _ path: String) async -> SignInStatus

    public init(
        locate: @escaping @Sendable () async -> AgentLocation,
        hasTool: @escaping @Sendable (_ name: String, _ path: String) -> Bool,
        signIn: @escaping @Sendable (_ kind: HarnessKind, _ executable: URL, _ path: String) async -> SignInStatus
    ) {
        self.locate = locate
        self.hasTool = hasTool
        self.signIn = signIn
    }
}

/// The agents step: which CLIs this Mac has, which are signed in, and the installs and sign-ins
/// the person starts from it. Nothing runs without a click; the commands themselves run in a
/// terminal the person can see (the install sheet), and when one ends this looks again.
@MainActor
@Observable
public final class AgentSetup {
    public private(set) var states: [HarnessKind: AgentState]
    /// Ready, though nothing could confirm the sign-in (it happens on first use).
    public private(set) var signInUnverified: Set<HarnessKind> = []
    /// The install or sign-in running now. One at a time.
    public private(set) var running: SetupRun?

    @ObservationIgnored private let probes: AgentProbes
    @ObservationIgnored private let recipes: @Sendable (HarnessKind) -> AgentRecipe
    @ObservationIgnored private var location = AgentLocation(found: [:], path: "")

    public init(
        probes: AgentProbes = .live,
        recipes: @escaping @Sendable (HarnessKind) -> AgentRecipe = { AgentInstaller.recipe(for: $0) }
    ) {
        self.probes = probes
        self.recipes = recipes
        states = Dictionary(uniqueKeysWithValues: HarnessKind.allCases.map { ($0, .checking) })
    }

    public func state(of kind: HarnessKind) -> AgentState { states[kind] ?? .checking }

    public func recipe(for kind: HarnessKind) -> AgentRecipe { recipes(kind) }

    public var anyReady: Bool { states.values.contains(.ready) }

    /// Looks for every CLI and its sign-in. A CLI with a run going keeps its state.
    public func detect() async {
        for kind in HarnessKind.allCases where running?.kind != kind { states[kind] = .checking }
        let location = await probes.locate()
        self.location = location
        var unverified: Set<HarnessKind> = []
        var found: [HarnessKind: AgentState] = [:]
        for kind in HarnessKind.allCases {
            if let executable = location.found[kind] {
                switch await probes.signIn(kind, executable, location.path) {
                case .signedIn: found[kind] = .ready
                case .signedOut: found[kind] = .installed
                case .unknown:
                    found[kind] = .ready
                    unverified.insert(kind)
                }
            } else if let tool = missingTool(for: kind) {
                found[kind] = .needsTool(name: tool.name, url: tool.downloadPage)
            } else {
                found[kind] = .missing
            }
        }
        for kind in HarnessKind.allCases where running?.kind != kind {
            states[kind] = found[kind]
        }
        signInUnverified = unverified
    }

    /// Starts an install or a sign-in: the command for the sheet to run, or nil when one is
    /// already running or the installer needs a program the Mac doesn't have (the card then
    /// offers its download page).
    public func start(_ purpose: SetupRun.Purpose, for kind: HarnessKind) -> SetupRun? {
        guard running == nil else { return nil }
        let recipe = recipes(kind)
        let run: SetupRun
        switch purpose {
        case .install:
            if let tool = missingTool(for: kind) {
                states[kind] = .needsTool(name: tool.name, url: tool.downloadPage)
                return nil
            }
            run = SetupRun(kind: kind, purpose: .install, command: recipe.install, shellCommand: recipe.install,
                           path: location.path)
        case .signIn:
            run = SetupRun(kind: kind, purpose: .signIn, command: recipe.login,
                           shellCommand: recipe.loginCommand(executable: location.found[kind]), path: location.path)
        }
        running = run
        states[kind] = busyState(for: run)
        return run
    }

    /// A failed card's Try again: the install if the CLI still isn't there, else the sign-in.
    public func retry(_ kind: HarnessKind) -> SetupRun? {
        start(location.found[kind] == nil ? .install : .signIn, for: kind)
    }

    /// The sheet's process ended (or the person cancelled it): look again. An install that left
    /// no CLI behind, or a sign-in that didn't take, says so on the card.
    public func finished(_ run: SetupRun, exitCode: Int32?, cancelled: Bool = false) async {
        guard running?.id == run.id else { return }
        running = nil
        states[run.kind] = .checking
        await detect()
        guard !cancelled else { return }
        let name = run.kind.executableName
        switch (run.purpose, states[run.kind]) {
        case (.install, .missing), (.install, .needsTool):
            if let exitCode, exitCode != 0 {
                states[run.kind] = .failed(String(localized: "The installer stopped with code \(Int(exitCode))."))
            } else {
                states[run.kind] = .failed(String(localized: "The installer finished, but xBot can't find \(name)."))
            }
        case (.signIn, .installed):
            states[run.kind] = .failed(String(localized: "The sign-in didn't finish."))
        default:
            break
        }
    }

    private func busyState(for run: SetupRun) -> AgentState {
        run.purpose == .install ? .installing : .signingIn
    }

    private func missingTool(for kind: HarnessKind) -> RequiredTool? {
        recipes(kind).requires.first { !probes.hasTool($0.name, location.path) }
    }
}

extension AgentProbes {
    /// The Mac itself: the login shell's PATH (`HarnessLocator`), and each CLI's own sign-in check.
    public static let live = AgentProbes(
        locate: {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let path = HarnessLocator.searchPath(loginShellPath: await HarnessLocator.loginShellPath(shell: shell), home: home)
            var found: [HarnessKind: URL] = [:]
            for kind in HarnessKind.allCases {
                if let url = HarnessLocator.find(kind, in: path) { found[kind] = url }
            }
            return AgentLocation(found: found, path: path)
        },
        hasTool: { name, path in HarnessLocator.find(executable: name, in: path) != nil },
        signIn: { kind, executable, path in
            switch kind {
            case .claude:
                // The account block Claude Code writes to ~/.claude.json when signed in.
                return ClaudeAccount.isSignedIn() ? .signedIn : .signedOut
            case .codex:
                let env = HarnessLocator.environment(path: path, base: ProcessInfo.processInfo.environment)
                return await codexSignIn(
                    home: URL.homeDirectory, codexHome: ProcessInfo.processInfo.environment["CODEX_HOME"],
                    status: { await exitCode(of: executable, arguments: ["login", "status"], environment: env) }
                )
            case .copilot, .antigravity:
                // Both keep the session in the Keychain and document no status command (Copilot's
                // is `/user` inside a session; Antigravity's is the session itself).
                return .unknown
            }
        }
    )

    /// Codex keeps its login in `$CODEX_HOME/auth.json` (~/.codex by default) or, configured so,
    /// in the Keychain (https://developers.openai.com/codex/auth, "Credential storage"). The file
    /// holds tokens, so only its presence is checked; without it, `codex login status`, which
    /// exits 0 when signed in, decides.
    static func codexSignIn(
        home: URL, codexHome: String?, status: @Sendable () async -> Int32?
    ) async -> SignInStatus {
        let folder = codexHome.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? home.appending(path: ".codex")
        if FileManager.default.fileExists(atPath: folder.appending(path: "auth.json").path) { return .signedIn }
        return await status() == 0 ? .signedIn : .signedOut
    }

    /// A short check's exit status; nil if it couldn't start or ran past the timeout.
    static func exitCode(
        of executable: URL, arguments: [String], environment: [String: String], timeout: Duration = .seconds(10)
    ) async -> Int32? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let race = Race()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
            process.terminationHandler = { ended in
                continuation.resume(returning: race.end() ? ended.terminationStatus : nil)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
                return
            }
            let pid = process.processIdentifier
            Task.detached {
                try? await Task.sleep(for: timeout)
                // Only a process still running: once it has ended its pid may be someone else's.
                if race.timeOut() { kill(pid, SIGKILL) }
            }
        }
    }
}

/// A process ending against its timeout: whichever comes first wins.
private final class Race: @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    private var timedOut = false

    /// The process ended; true if it did so before the timeout.
    func end() -> Bool { lock.withLock { ended = true; return !timedOut } }

    /// The timeout fired; true if the process is still running (and should be killed).
    func timeOut() -> Bool { lock.withLock { guard !ended else { return false }; timedOut = true; return true } }
}
