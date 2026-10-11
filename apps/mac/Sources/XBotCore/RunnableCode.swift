import Foundation

/// Which code blocks in a reply can be run in a terminal, and what exactly to run.
public enum RunnableCode {
    /// Fenced-block languages that mean "type this at a shell".
    static let shells: Set<String> = ["bash", "sh", "zsh", "shell", "console", "terminal", "shell-session", "shellsession", "fish"]

    /// The command to send, or nil when the block isn't shell (or is empty). Untagged blocks don't
    /// run: they're as often output or prose as commands. In a transcript (lines starting `$ ` or
    /// `% `), only the prompted lines are commands; the rest is what they printed.
    public static func command(from code: String, language: String?) -> String? {
        guard let language = language?.lowercased(), shells.contains(language) else { return nil }
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let prompted = lines.filter { $0.hasPrefix("$ ") || $0.hasPrefix("% ") }
        let command = prompted.isEmpty
            ? lines.joined(separator: "\n")
            : prompted.map { String($0.dropFirst(2)) }.joined(separator: "\n")
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension TerminalDeck {
    /**
     Runs `command` in the chat's terminal: in its selected tab if that shell is at a prompt, else
     in a new tab, so it never types into vim or a job that's running. Opens the terminal if the
     chat has none, and shows it if hidden.
     */
    public func run(_ command: String, in chatID: UUID, directory: URL) {
        let target: TerminalTab
        if let selected = panel(chatID)?.selectedTabID, let tab = tab(selected), !isBusy(selected) {
            target = tab
            showTerminal(chatID)
        } else {
            target = openTab(chatID, in: directory)
        }
        onRun(target.id, command)
    }
}

extension Workspace {
    public func runInTerminal(_ command: String, in chatID: UUID) {
        guard let chat = chat(chatID) else { return }
        terminals.run(command, in: chatID, directory: directory(for: chat))
    }
}
