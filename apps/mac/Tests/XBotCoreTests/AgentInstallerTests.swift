import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@Suite struct AgentInstallerTests {
    /// The exact commands, as each vendor's own documentation gives them. If a vendor changes its
    /// installer, change the recipe and its source together.
    @Test func eachCLIsOfficialInstallAndLoginCommands() {
        let claude = AgentInstaller.recipe(for: .claude)
        #expect(claude.install == "curl -fsSL https://claude.ai/install.sh | bash")
        #expect(claude.login == "claude auth login")
        #expect(claude.source == "https://code.claude.com/docs/en/setup")
        #expect(claude.loginSource == "https://code.claude.com/docs/en/cli-reference")

        let codex = AgentInstaller.recipe(for: .codex)
        #expect(codex.install == "curl -fsSL https://chatgpt.com/codex/install.sh | sh")
        #expect(codex.login == "codex login")
        #expect(codex.source == "https://developers.openai.com/codex/cli")
        #expect(codex.loginSource == "https://developers.openai.com/codex/auth")

        let copilot = AgentInstaller.recipe(for: .copilot)
        #expect(copilot.install == "curl -fsSL https://gh.io/copilot-install | bash")
        #expect(copilot.login == "copilot login")
        #expect(copilot.source == "https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli")
        #expect(copilot.loginSource == "https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli")

        let agy = AgentInstaller.recipe(for: .antigravity)
        #expect(agy.install == "curl -fsSL https://antigravity.google/cli/install.sh | bash")
        #expect(agy.login == "agy")
        #expect(agy.source == "https://antigravity.google/docs/cli/install")
        #expect(agy.loginSource == "https://antigravity.google/docs/cli/install")
    }

    /// All four ship a native installer now: none needs npm or Homebrew.
    @Test func noneNeedsAPackageManager() {
        for kind in HarnessKind.allCases {
            #expect(AgentInstaller.recipe(for: kind).requires.isEmpty)
            #expect(AgentInstaller.recipe(for: kind).kind == kind)
        }
    }

    /// The sign-in runs the binary that was found, so a shell whose PATH doesn't have the new
    /// install folder yet still finds it.
    @Test func signInRunsTheFoundBinary() {
        let recipe = AgentInstaller.recipe(for: .claude)
        let run = recipe.loginCommand(executable: URL(filePath: "/Users/me/my bin/claude"))
        #expect(run == "'/Users/me/my bin/claude' auth login")
        #expect(AgentInstaller.recipe(for: .antigravity).loginCommand(executable: URL(filePath: "/x/agy")) == "'/x/agy'")
        #expect(recipe.loginCommand(executable: nil) == "claude auth login")
        #expect(AgentInstaller.shellQuoted("it's") == "'it'\\''s'")
    }
}
