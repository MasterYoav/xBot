import Foundation
import Testing
@testable import XBotCore

@Suite struct RunnableCodeTests {
    @Test func shellLanguagesRun() {
        for language in ["bash", "sh", "zsh", "shell", "console", "terminal", "Bash", "shell-session"] {
            #expect(RunnableCode.command(from: "ls", language: language) == "ls", "\(language)")
        }
    }

    @Test func otherLanguagesAndUntaggedBlocksDont() {
        for language in ["swift", "json", "python", "diff", "text", ""] {
            #expect(RunnableCode.command(from: "ls", language: language) == nil, "\(language)")
        }
        #expect(RunnableCode.command(from: "ls", language: nil) == nil)
    }

    @Test func emptyBlocksDont() {
        #expect(RunnableCode.command(from: "  \n\n", language: "bash") == nil)
    }

    /// A transcript: the prompts go, and so do the lines of output after them.
    @Test func promptsAndOutputAreLeftOut() {
        let session = "$ git status\nOn branch main\n$ swift test\n✔ passed"
        #expect(RunnableCode.command(from: session, language: "console") == "git status\nswift test")
        #expect(RunnableCode.command(from: "% brew install jq", language: "zsh") == "brew install jq")
    }

    @Test func plainScriptsRunAsWritten() {
        let script = "cd apps/mac\nswift build \\\n  --build-tests\n"
        #expect(RunnableCode.command(from: script, language: "bash") == "cd apps/mac\nswift build \\\n  --build-tests")
    }
}

@MainActor @Suite struct RunInTerminalTests {
    let chat = UUID()
    let folder = URL(filePath: "/tmp")

    func deck() -> (TerminalDeck, () -> [(UUID, String)]) {
        let deck = TerminalDeck()
        var sent: [(UUID, String)] = []
        deck.onRun = { sent.append(($0, $1)) }
        return (deck, { sent })
    }

    @Test func withNoTerminalItOpensOneAndRunsThere() {
        let (deck, sent) = deck()
        deck.run("ls", in: chat, directory: folder)
        #expect(deck.isShown(chat) && deck.tabs(in: chat).count == 1)
        #expect(sent().map(\.0) == [deck.tabs(in: chat)[0].id] && sent().map(\.1) == ["ls"])
    }

    @Test func anIdleSelectedTabIsReused() {
        let (deck, sent) = deck()
        let tab = deck.openTab(chat, in: folder)
        deck.toggle(chat, in: folder)
        #expect(!deck.isShown(chat))
        deck.run("ls", in: chat, directory: folder)
        #expect(deck.isShown(chat) && deck.tabs(in: chat).count == 1 && sent().first?.0 == tab.id)
    }

    /// Never typed into vim or a running job: a busy tab gets a new one beside it.
    @Test func aBusyTabGetsANewOne() {
        let (deck, sent) = deck()
        let busy = deck.openTab(chat, in: folder)
        deck.isBusy = { $0 == busy.id }
        deck.run("ls", in: chat, directory: folder)
        #expect(deck.tabs(in: chat).count == 2)
        #expect(sent().first?.0 == deck.tabs(in: chat)[1].id)
        #expect(deck.panel(chat)?.selectedTabID == deck.tabs(in: chat)[1].id)
    }

    @Test func theWorkspaceRunsInTheChatsFolder() async throws {
        let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await w.refreshHarnesses()
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        let chat = try #require(w.newChat(in: project.id))
        var sent: [String] = []
        w.terminals.onRun = { sent.append($1) }
        w.runInTerminal("make", in: chat.id)
        #expect(sent == ["make"] && w.terminals.tabs(in: chat.id).first?.directory == project.url)
    }
}
