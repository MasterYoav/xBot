import Foundation
import Testing
import XBotTools
@testable import XBotCore

/// Agentic Mode's guardrails: every rule, both ways.
@Suite struct RiskRulesTests {
    func shell(_ command: String) -> Risk.Kind? { RiskRules.check(shell: command)?.kind }

    // MARK: Shell (Claude Code's own Bash tool, through the hook)

    @Test func readingAndBuildingRun() {
        for command in ["git status", "ls -la", "swift test", "cat README.md | grep rm", "git log --oneline -5",
                        "echo 'rm -rf /' > notes.txt", "npm run build", "git commit -m 'remove old code'",
                        "grep -r 'git push' docs", "defaults read com.apple.dock", "git diff --stat",
                        "find . -name '*.swift'", "trashy=1 echo hi", "mkdir build && cd build",
                        "defaults write dev.xbot.app inspectorShown -bool true", "git reset --soft HEAD~1"] {
            #expect(shell(command) == nil, "\(command)")
        }
    }

    @Test func deletingAsks() {
        for command in ["rm -rf build", "rm notes.txt", "/bin/rm -f x", "trash ~/Desktop/old", "rmdir empty",
                        "git clean -fdx", "git reset --hard HEAD~3", "cd /tmp && rm -r old", "find . -name '*.o' -delete",
                        "ls | xargs rm", "sudo -u me rm x", "FOO=1 rm x", "echo $(rm -rf ~/x)", "unlink file",
                        "git branch -D feature", "mv report.pdf ~/.Trash/", "shred secret.txt", "git checkout -- .",
                        "srm -rf old"] {
            #expect(shell(command) != nil, "\(command)")
        }
        #expect(shell("rm -rf build") == .delete)
        #expect(shell("git clean -fd") == .delete)
        #expect(shell("git reset --hard") == .delete)
    }

    @Test func pushingAsks() {
        #expect(shell("git push") == .push)
        #expect(shell("git push --force origin main") == .push)
        #expect(shell("swift test && git push origin HEAD") == .push)
        #expect(shell("git -C ../repo push") == .push)
        #expect(shell("git pull") == nil)
        #expect(shell("git fetch origin") == nil)
    }

    @Test func sendingAsks() {
        #expect(shell(#"osascript -e 'tell application "Mail" to send (make new outgoing message)'"#) == .send)
        #expect(shell(#"osascript -e 'tell application "Messages" to send "hi" to buddy "x"'"#) == .send)
        #expect(shell("echo body | mail -s hi someone@example.com") == .send)
        #expect(shell("sendmail someone@example.com < message.txt") == .send)
        #expect(shell(#"osascript -e 'display notification "done"'"#) == nil)
        #expect(shell(#"osascript -e 'tell application "Finder" to get name of front window'"#) == nil)
    }

    @Test func systemSettingsAsk() {
        #expect(shell("sudo softwareupdate -i -a") == .settings)
        #expect(shell("defaults write com.apple.dock autohide -bool true") == .settings)
        #expect(shell("defaults delete com.apple.finder") == .settings)
        #expect(shell("networksetup -setairportpower en0 off") == .settings)
        #expect(shell("pmset -a sleep 0") == .settings)
        #expect(shell("launchctl unload ~/Library/LaunchAgents/x.plist") == .settings)
        #expect(shell("tccutil reset All") == .settings)
    }

    @Test func quittingAppsAsks() {
        #expect(shell("killall Safari") == .quit)
        #expect(shell("pkill -x Mail") == .quit)
        #expect(shell(#"osascript -e 'quit app "Safari"'"#) == .quit)
        #expect(shell(#"osascript -e 'tell application "Mail" to quit'"#) == .quit)
    }

    @Test func purchasesInTheShellAsk() {
        #expect(shell("mas purchase 497799835") == .purchase)
        #expect(shell("mas install 497799835") == nil, "installing a free or owned app isn't buying")
    }

    @Test func theRiskSaysWhatAndShowsTheCommand() throws {
        let risk = try #require(RiskRules.check(shell: "rm -rf build"))
        #expect(risk.detail == "rm -rf build")
        #expect(!risk.summary.isEmpty)
    }

    // MARK: Hooks: which of Claude Code's own tools reach the shell rules

    @Test func theHookRoutesBashAndOtherServersSendingTools() {
        #expect(RiskRules.check(hookTool: "Bash", input: ["command": "git push"])?.kind == .push)
        #expect(RiskRules.check(hookTool: "Bash", input: ["command": "git status"]) == nil)
        #expect(RiskRules.check(hookTool: "Read", input: ["file_path": "/etc/hosts"]) == nil)
        #expect(RiskRules.check(hookTool: "Edit", input: ["file_path": "a.swift"]) == nil)
        #expect(RiskRules.check(hookTool: "mcp__gmail__send_email", input: [:])?.kind == .send)
        #expect(RiskRules.check(hookTool: "mcp__github__delete_repository", input: [:])?.kind == .delete)
        #expect(RiskRules.check(hookTool: "mcp__github__get_issue", input: [:]) == nil)
        // xBot's own tools are checked by the app when they run, not twice.
        #expect(RiskRules.check(hookTool: "mcp__xbot__mac_quit", input: ["app": "Safari"]) == nil)
    }

    // MARK: xBot's tools, with what's on screen

    let textEdit = RiskRules.Screen(app: "TextEdit", bundleID: "com.apple.TextEdit", windowTitle: "Untitled")
    let mail = RiskRules.Screen(app: "Mail", bundleID: "com.apple.mail", windowTitle: "New Message")
    let messages = RiskRules.Screen(app: "Messages", bundleID: "com.apple.MobileSMS", windowTitle: "Messages")
    let settings = RiskRules.Screen(app: "System Settings", bundleID: "com.apple.systempreferences", windowTitle: "Wi-Fi")
    let checkout = RiskRules.Screen(app: "Safari", bundleID: "com.apple.Safari", windowTitle: "Checkout – Example Store")
    let terminal = RiskRules.Screen(app: "Terminal", bundleID: "com.apple.Terminal", windowTitle: "zsh")

    func tool(_ name: String, _ arguments: JSONValue = [:], on screen: RiskRules.Screen = .init()) -> Risk.Kind? {
        RiskRules.check(tool: name, arguments: arguments, screen: screen)?.kind
    }

    @Test func quittingAnAppAlwaysAsks() {
        #expect(tool("mac_quit", ["app": "Safari"]) == .quit)
        #expect(tool("mac_quit", ["app": "TextEdit"], on: textEdit) == .quit)
    }

    @Test func typingInTextEditRuns() {
        #expect(tool("mac_type", ["text": "Hello"], on: textEdit) == nil)
        #expect(tool("mac_keys", ["combo": "cmd+s"], on: textEdit) == nil)
        #expect(tool("mac_keys", ["combo": "return"], on: textEdit) == nil)
        #expect(tool("mac_click", ["x": 10, "y": 10], on: textEdit) == nil)
    }

    @Test func sendingInMailOrMessagesAsks() {
        #expect(tool("mac_keys", ["combo": "cmd+return"], on: mail) == .send)
        #expect(tool("mac_keys", ["combo": "cmd+shift+d"], on: mail) == .send)
        #expect(tool("mac_keys", ["combo": "cmd+enter"], on: messages) == .send)
        #expect(tool("mac_keys", ["combo": "return"], on: messages) == .send, "Return sends in Messages")
        #expect(tool("mac_type", ["text": "on my way\n"], on: messages) == .send)
        #expect(tool("mac_type", ["text": "on my way"], on: messages) == nil, "typing a draft isn't sending")
        #expect(tool("mac_keys", ["combo": "return"], on: mail) == nil, "a new line in a mail")
        let sendButton = RiskRules.Screen(app: "Mail", bundleID: "com.apple.mail", windowTitle: "New Message", elementTitle: "Send")
        #expect(tool("mac_click", ["element": "e4"], on: sendButton) == .send)
    }

    @Test func confirmingInACheckoutWindowAsks() {
        #expect(tool("mac_keys", ["combo": "return"], on: checkout) == .purchase)
        #expect(tool("mac_click", ["x": 300, "y": 400], on: checkout) == .purchase)
        let buy = RiskRules.Screen(app: "App Store", bundleID: "com.apple.AppStore", windowTitle: "App Store", elementTitle: "Buy")
        #expect(tool("mac_click", ["element": "e2"], on: buy) == .purchase)
        let shopping = RiskRules.Screen(app: "Safari", bundleID: "com.apple.Safari", windowTitle: "Shoes – Example Store")
        #expect(tool("mac_click", ["x": 300, "y": 400], on: shopping) == nil)
        #expect(tool("mac_scroll", ["dy": 300], on: checkout) == nil, "scrolling a checkout page buys nothing")
    }

    @Test func actingInSystemSettingsAsksButLookingDoesNot() {
        #expect(tool("mac_click", ["x": 1, "y": 1], on: settings) == .settings)
        #expect(tool("mac_keys", ["combo": "space"], on: settings) == .settings)
        #expect(tool("mac_type", ["text": "x"], on: settings) == .settings)
        #expect(tool("mac_screenshot", on: settings) == nil)
        #expect(tool("mac_ui", on: settings) == nil)
    }

    @Test func typingACommandIntoATerminalIsCheckedLikeTheShell() {
        #expect(tool("mac_type", ["text": "rm -rf ~/old\n"], on: terminal) == .delete)
        #expect(tool("mac_type", ["text": "git status\n"], on: terminal) == nil)
        #expect(tool("mac_type", ["text": "rm -rf ~/old"], on: textEdit) == nil, "words in a document are just words")
    }

    @Test func xBotsOwnToolsRunExceptDeleting() {
        for name in ["xbot_projects", "xbot_crew", "xbot_hire", "xbot_hand_off", "xbot_write_note", "xbot_set_world",
                     "xbot_set_appearance", "xbot_start_chat", "xbot_ask", "xbot_remember", "mac_open", "mac_apps",
                     "mac_screenshot", "mac_ui"] {
            #expect(tool(name, ["target": "Safari"]) == nil, "\(name)")
        }
        #expect(tool("xbot_delete_chat", ["id": "x"]) == .delete)
    }

    @Test func approvalTextNamesTheAgentAndTheAction() throws {
        let risk = try #require(RiskRules.check(tool: "mac_quit", arguments: ["app": "Safari"], screen: .init()))
        let approval = risk.approval(agent: "Forge")
        #expect(approval.summary == "Forge wants to quit Safari")
        #expect(approval.risk == "quit")
        #expect(approval.agent == "Forge")
        #expect(approval.state == .pending)
    }
}
