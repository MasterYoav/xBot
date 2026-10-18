import Foundation
import XBotBrain

/// A program an official installer needs that a Mac may not have.
public struct RequiredTool: Equatable, Sendable {
    public var name: String
    /// Where the person gets it. xBot never installs a package manager on its own.
    public var downloadPage: URL

    public static let npm = RequiredTool(name: "npm", downloadPage: URL(string: "https://nodejs.org/en/download")!)
    public static let homebrew = RequiredTool(name: "brew", downloadPage: URL(string: "https://brew.sh")!)
}

/// How one agent CLI is installed and signed in to, as its vendor documents it.
public struct AgentRecipe: Equatable, Sendable {
    public var kind: HarnessKind
    /// The official install command, run in a login shell in a terminal the person can see.
    public var install: String
    /// The CLI's own sign-in command (it opens the browser).
    public var login: String
    /// Programs `install` needs besides what every Mac has (`curl`, `bash`, `sh`).
    public var requires: [RequiredTool]
    /// The CLI's page, for when it can't be installed from here.
    public var downloadPage: URL
    /// The documentation the install command was copied from.
    public var source: String
    /// The documentation the sign-in command was copied from.
    public var loginSource: String

    /// `login`, with the CLI's name swapped for the binary that was found: a login shell started
    /// right after an install may not have the install folder on its PATH yet.
    public func loginCommand(executable: URL?) -> String {
        let name = kind.executableName
        guard let executable, login == name || login.hasPrefix(name + " ") else { return login }
        return AgentInstaller.shellQuoted(executable.path) + login.dropFirst(name.count)
    }
}

/// The official install and sign-in commands for each CLI xBot drives.
///
/// Each was copied from the vendor's own documentation on 2026-10-13 (the URL is beside it and in
/// `source`), and checked against the installed CLI's `--help`. They change without notice: when
/// one does, update the command and its source together, and the test that pins them.
public enum AgentInstaller {
    public static func recipe(for kind: HarnessKind) -> AgentRecipe {
        switch kind {
        case .claude:
            // Install: https://code.claude.com/docs/en/setup ("Native Install (Recommended)",
            // macOS, Linux, WSL). Puts `claude` in ~/.local/bin.
            // Sign in: https://code.claude.com/docs/en/cli-reference (`claude auth login`: "Sign in
            // to your Anthropic account"; `claude auth status` exits 0 when logged in).
            AgentRecipe(
                kind: kind,
                install: "curl -fsSL https://claude.ai/install.sh | bash",
                login: "claude auth login",
                requires: [],
                downloadPage: URL(string: "https://claude.com/product/claude-code")!,
                source: "https://code.claude.com/docs/en/setup",
                loginSource: "https://code.claude.com/docs/en/cli-reference"
            )
        case .codex:
            // Install: https://developers.openai.com/codex/cli (the standalone installer for macOS
            // and Linux; also the openai/codex README). Puts `codex` in ~/.local/bin; no npm.
            // Sign in: https://developers.openai.com/codex/auth ("Run codex login, then complete
            // the browser flow").
            AgentRecipe(
                kind: kind,
                install: "curl -fsSL https://chatgpt.com/codex/install.sh | sh",
                login: "codex login",
                requires: [],
                downloadPage: URL(string: "https://developers.openai.com/codex")!,
                source: "https://developers.openai.com/codex/cli",
                loginSource: "https://developers.openai.com/codex/auth"
            )
        case .copilot:
            // Install: https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli
            // ("Installing with the install script (macOS and Linux)"; also github/copilot-cli's
            // README). Puts `copilot` in ~/.local/bin for a non-root user; no npm.
            // Sign in: https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli
            // ("run /login from Copilot CLI or copilot login from your terminal").
            AgentRecipe(
                kind: kind,
                install: "curl -fsSL https://gh.io/copilot-install | bash",
                login: "copilot login",
                requires: [],
                downloadPage: URL(string: "https://github.com/github/copilot-cli")!,
                source: "https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli",
                loginSource: "https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli"
            )
        case .antigravity:
            // Install: https://antigravity.google/docs/cli/install ("Execute the native installer
            // script to download and install the executable to ~/.local/bin/agy"). A CLI of its
            // own, separate from the Antigravity app.
            // Sign in, same page: `agy` has no login subcommand. Started on its own it signs in
            // through the browser ("If no saved session is found … the CLI automatically launches
            // your local default web browser"), keeping the session in the Keychain.
            AgentRecipe(
                kind: kind,
                install: "curl -fsSL https://antigravity.google/cli/install.sh | bash",
                login: "agy",
                requires: [],
                downloadPage: URL(string: "https://antigravity.google")!,
                source: "https://antigravity.google/docs/cli/install",
                loginSource: "https://antigravity.google/docs/cli/install"
            )
        }
    }

    /// One word to a POSIX shell, whatever it contains.
    public static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
