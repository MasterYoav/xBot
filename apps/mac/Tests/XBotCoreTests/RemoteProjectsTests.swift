import Foundation
import Testing
import XBotBrain
import XBotRemote
@testable import XBotCore

/// Projects from the phone: the Explorer, files, Changes, and adding a project.
@MainActor @Suite(.serialized) struct RemoteProjectsTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    /// A repository with one commit, then: a.txt changed, b.txt new, sub/c.txt new, a binary file.
    func makeRepo() throws -> URL {
        let parent = FileManager.default.temporaryDirectory.appending(path: "remote-projects-\(UUID().uuidString)")
        let repo = parent.appending(path: "Demo")
        try FileManager.default.createDirectory(at: repo.appending(path: "sub"), withIntermediateDirectories: true)
        func git(_ args: String...) throws {
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/env")
            p.arguments = ["git"] + args
            p.currentDirectoryURL = repo
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
        }
        try git("init", "-q", "-b", "main")
        try git("config", "user.name", "Test")
        try git("config", "user.email", "test@example.com")
        try "one\n".write(to: repo.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try git("add", "-A")
        try git("commit", "-q", "-m", "first")
        try "one\ntwo\n".write(to: repo.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: repo.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        try "deep\n".write(to: repo.appending(path: "sub/c.txt"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 0, 255]).write(to: repo.appending(path: "blob.bin"))
        return repo
    }

    func setUp() async throws -> (Workspace, RemoteHost, FakeLink, Project, URL) {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await w.refreshHarnesses()
        let host = RemoteHost(workspace: w, macName: "Mac", macID: UUID(), localInterval: .milliseconds(20), cloudInterval: .milliseconds(200))
        let repo = try makeRepo()
        let project = w.addProject(at: repo)
        let link = FakeLink()
        host.attach(link)
        return (w, host, link, project, repo)
    }

    /// The answer to one request, data or refusal.
    func answer(_ link: FakeLink, _ request: UUID) async -> HostMessage? {
        let end = Date.now.addingTimeInterval(20)
        while Date.now < end {
            if let found = link.sent.first(where: { Self.requestID(of: $0) == request }) { return found }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    static func requestID(of message: HostMessage) -> UUID? {
        switch message {
        case .reply(let r, _, _, _), .folder(let r, _), .file(let r, _), .git(let r, _), .diff(let r, _), .macFolders(let r, _, _), .notes(let r, _, _), .automations(let r, _, _, _), .crew(let r, _, _), .avatarImage(let r, _): r
        default: nil
        }
    }

    @Test func theExplorerListsFoldersFirstWithGitLetters() async throws {
        let (_, host, link, project, _) = try await setUp()
        defer { withExtendedLifetime(host) {} }
        let top = UUID(), sub = UUID(), escape = UUID()
        link.say(.listFolder(requestID: top, projectID: project.id, path: ""))
        guard case .folder(_, let entries) = await answer(link, top) else { Issue.record("no folder"); return }
        #expect(entries.map(\.name) == ["sub", "a.txt", "b.txt", "blob.bin"])
        #expect(entries.first { $0.name == "a.txt" }?.letter == "M")
        #expect(entries.first { $0.name == "b.txt" }?.letter == "U")
        #expect(entries.first { $0.name == "sub" }?.isFolder == true && entries.first { $0.name == "sub" }?.letter == "U")
        #expect(!entries.contains { $0.name == ".git" })

        link.say(.listFolder(requestID: sub, projectID: project.id, path: "sub"))
        guard case .folder(_, let inside) = await answer(link, sub) else { Issue.record("no sub"); return }
        #expect(inside.map(\.path) == ["sub/c.txt"])

        link.say(.listFolder(requestID: escape, projectID: project.id, path: "../.."))
        guard case .reply(_, false, _, _) = await answer(link, escape) else { Issue.record("left the project"); return }
    }

    @Test func filesAreReadTextOrBinaryAndNeverOutsideTheProject() async throws {
        let (_, host, link, project, _) = try await setUp()
        defer { withExtendedLifetime(host) {} }
        let text = UUID(), binary = UUID(), outside = UUID(), missing = UUID()
        link.say(.readFile(requestID: text, projectID: project.id, path: "a.txt"))
        guard case .file(_, let a) = await answer(link, text) else { Issue.record("no file"); return }
        #expect(a.text == "one\ntwo\n" && a.size == 8 && !a.truncated)

        link.say(.readFile(requestID: binary, projectID: project.id, path: "blob.bin"))
        guard case .file(_, let blob) = await answer(link, binary) else { Issue.record("no blob"); return }
        #expect(blob.text == nil && blob.size == 5)

        link.say(.readFile(requestID: outside, projectID: project.id, path: "sub/../../../etc/hosts"))
        guard case .reply(_, false, _, _) = await answer(link, outside) else { Issue.record("read outside"); return }
        link.say(.readFile(requestID: missing, projectID: project.id, path: "nope.txt"))
        guard case .reply(_, false, _, _) = await answer(link, missing) else { Issue.record("read nothing"); return }
    }

    @Test func changesDiffStageAndCommit() async throws {
        let (_, host, link, project, _) = try await setUp()
        defer { withExtendedLifetime(host) {} }
        let status = UUID(), diff = UUID(), stage = UUID(), commit = UUID()
        link.say(.gitStatus(requestID: status, projectID: project.id))
        guard case .git(_, let git) = await answer(link, status) else { Issue.record("no status"); return }
        #expect(git.isRepository && git.branch == "main")
        #expect(Set(git.files.map(\.path)) == ["a.txt", "b.txt", "sub/c.txt", "blob.bin"])

        link.say(.gitDiff(requestID: diff, projectID: project.id, path: "a.txt"))
        guard case .diff(_, let lines) = await answer(link, diff) else { Issue.record("no diff"); return }
        #expect(lines.contains { $0.kind == "added" && $0.text == "two" })

        link.say(.gitAction(requestID: stage, projectID: project.id, action: .stage(path: "b.txt")))
        guard case .git(_, let staged) = await answer(link, stage) else { Issue.record("no stage"); return }
        #expect(staged.files.first { $0.path == "b.txt" }?.isStaged == true)
        #expect(staged.files.first { $0.path == "a.txt" }?.isStaged == false)

        link.say(.gitAction(requestID: commit, projectID: project.id, action: .commit(message: "From the phone")))
        guard case .git(_, let after) = await answer(link, commit) else { Issue.record("no commit"); return }
        // Only what was staged went in.
        #expect(!after.files.contains { $0.path == "b.txt" } && after.files.contains { $0.path == "a.txt" })
    }

    @Test func newRenameAndTrash() async throws {
        let (_, host, link, project, repo) = try await setUp()
        defer { withExtendedLifetime(host) {} }
        let new = UUID(), folder = UUID(), rename = UUID(), trash = UUID(), clash = UUID()
        link.say(.fileAction(requestID: new, projectID: project.id, action: .newFile(folder: "sub")))
        guard case .reply(_, true, _, _) = await answer(link, new) else { Issue.record("no new file"); return }
        #expect(FileManager.default.fileExists(atPath: repo.appending(path: "sub/untitled").path))
        link.say(.fileAction(requestID: folder, projectID: project.id, action: .newFolder(folder: "")))
        guard case .reply(_, true, _, _) = await answer(link, folder) else { Issue.record("no new folder"); return }
        link.say(.fileAction(requestID: rename, projectID: project.id, action: .rename(path: "sub/untitled", to: "notes.md")))
        guard case .reply(_, true, _, _) = await answer(link, rename) else { Issue.record("no rename"); return }
        #expect(FileManager.default.fileExists(atPath: repo.appending(path: "sub/notes.md").path))
        link.say(.fileAction(requestID: clash, projectID: project.id, action: .rename(path: "sub/notes.md", to: "../a.txt")))
        guard case .reply(_, false, _, _) = await answer(link, clash) else { Issue.record("renamed out"); return }
        link.say(.fileAction(requestID: trash, projectID: project.id, action: .trash(path: "sub/notes.md")))
        guard case .reply(_, true, _, _) = await answer(link, trash) else { Issue.record("no trash"); return }
        #expect(!FileManager.default.fileExists(atPath: repo.appending(path: "sub/notes.md").path))
    }

    @Test func pickAFolderOnTheMacAddItThenRemoveIt() async throws {
        let (w, host, link, project, repo) = try await setUp()
        defer { withExtendedLifetime(host) {} }
        let parent = repo.deletingLastPathComponent()
        let other = parent.appending(path: "Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let browse = UUID(), add = UUID(), remove = UUID()
        link.say(.browseMac(requestID: browse, path: parent.path))
        guard case .macFolders(_, _, let folders) = await answer(link, browse) else { Issue.record("no folders"); return }
        #expect(folders.map(\.name) == ["Demo", "Other"])
        #expect(folders.first { $0.name == "Demo" }?.isProject == true && folders.first { $0.name == "Other" }?.isProject == false)

        link.say(.addProject(requestID: add, path: other.path))
        guard case .reply(_, true, _, _) = await answer(link, add) else { Issue.record("not added"); return }
        #expect(w.projects.contains { $0.name == "Other" })
        let sentProjects = link.sent.contains { if case .workspace(let projects, _, _) = $0 { projects.contains { $0.name == "Other" } } else { false } }
        let end = Date.now.addingTimeInterval(5)
        while !sentProjects, Date.now < end,
              !link.sent.contains(where: { if case .workspace(let p, _, _) = $0 { p.contains { $0.name == "Other" } } else { false } }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(link.sent.contains { if case .workspace(let p, _, _) = $0 { p.contains { $0.name == "Other" && $0.path == other.path } } else { false } })

        link.say(.removeProject(requestID: remove, projectID: project.id))
        guard case .reply(_, true, _, _) = await answer(link, remove) else { Issue.record("not removed"); return }
        #expect(!w.projects.contains { $0.id == project.id })
    }
}

/// Notes from the phone: written as Markdown in the project's notes/ folder, named after the title.
@MainActor @Suite(.serialized) struct RemoteNotesTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    @Test func writeRenameReadDeleteAndUndo() async throws {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await w.refreshHarnesses()
        let host = RemoteHost(workspace: w, macName: "Mac", macID: UUID(), localInterval: .milliseconds(20), cloudInterval: .milliseconds(200))
        defer { withExtendedLifetime(host) {} }
        let folder = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let project = w.addProject(at: folder)
        let link = FakeLink()
        host.attach(link)
        let tests = RemoteProjectsTests()

        let empty = UUID()
        link.say(.listNotes(requestID: empty, projectID: project.id))
        guard case .notes(_, let none, nil) = await tests.answer(link, empty) else { Issue.record("no list"); return }
        #expect(none.isEmpty)

        // A new note is named after its title.
        let create = UUID()
        link.say(.saveNote(requestID: create, projectID: project.id, name: nil, text: "# Trip ideas\nLisbon"))
        guard case .notes(_, let one, let saved?) = await tests.answer(link, create) else { Issue.record("not saved"); return }
        #expect(saved == "trip-ideas.md" && one.map(\.title) == ["Trip ideas"])
        #expect(try String(contentsOf: folder.appending(path: "notes/trip-ideas.md"), encoding: .utf8) == "# Trip ideas\nLisbon")

        // A new title renames the file; the Mac's own notes model sees it.
        let edit = UUID()
        link.say(.saveNote(requestID: edit, projectID: project.id, name: "trip-ideas.md", text: "# Summer trip\nLisbon, Porto"))
        guard case .notes(_, let renamed, let file?) = await tests.answer(link, edit) else { Issue.record("not edited"); return }
        #expect(file == "summer-trip.md" && renamed.count == 1)
        #expect(w.notes(for: project).notes.map(\.title) == ["Summer trip"])

        let read = UUID()
        link.say(.readFile(requestID: read, projectID: project.id, path: "notes/summer-trip.md"))
        guard case .file(_, let note) = await tests.answer(link, read) else { Issue.record("not read"); return }
        #expect(note.text == "# Summer trip\nLisbon, Porto")

        // Names can't leave notes/.
        let sneaky = UUID()
        link.say(.saveNote(requestID: sneaky, projectID: project.id, name: "../evil.md", text: "x"))
        guard case .reply(_, false, _, _) = await tests.answer(link, sneaky) else { Issue.record("wrote outside"); return }

        let delete = UUID(), undo = UUID()
        link.say(.deleteNote(requestID: delete, projectID: project.id, name: "summer-trip.md"))
        guard case .notes(_, let gone, nil) = await tests.answer(link, delete) else { Issue.record("not deleted"); return }
        #expect(gone.isEmpty)
        link.say(.undoDeleteNote(requestID: undo, projectID: project.id))
        guard case .notes(_, let back, nil) = await tests.answer(link, undo) else { Issue.record("not undone"); return }
        #expect(back.map(\.name) == ["summer-trip.md"])
    }
}

/// Automations from the phone.
@MainActor @Suite(.serialized) struct RemoteAutomationsTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    @Test func createEditRunAndDelete() async throws {
        let brain = ScriptedBrain([.textDelta("done"), .done])
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        let host = RemoteHost(workspace: w, macName: "Mac", macID: UUID(), localInterval: .milliseconds(20), cloudInterval: .milliseconds(200))
        defer { withExtendedLifetime(host) {} }
        let link = FakeLink()
        host.attach(link)
        let tests = RemoteProjectsTests()

        let list = UUID()
        link.say(.listAutomations(requestID: list))
        guard case .automations(_, let none, let apps, _) = await tests.answer(link, list) else { Issue.record("no list"); return }
        #expect(none.isEmpty)
        #expect(apps.prefix(3).map(\.key) == ["mail", "calendar", "reminders"])

        // Made on the phone: a weekday schedule and two steps.
        var made = RemoteAutomation(name: "Morning brief", schedule: .weekdays(hour: 8, minute: 30),
                                    steps: [RemoteStep(app: "calendar", text: "List today's events"),
                                            RemoteStep(app: "connector:Gmail", text: "Summarise unread mail")],
                                    agent: "claude", effort: "low")
        let save = UUID()
        link.say(.saveAutomation(requestID: save, automation: made))
        guard case .automations(_, let one, _, _) = await tests.answer(link, save) else { Issue.record("not saved"); return }
        let saved = try #require(one.first)
        #expect(saved.name == "Morning brief" && saved.schedule == .weekdays(hour: 8, minute: 30) && saved.nextRun != nil)
        let stored = try #require(w.automation(made.id))
        #expect(stored.trigger == .schedule(.weekdays(hour: 8, minute: 30)))
        #expect(stored.steps.map(\.app) == [.calendar, .connector("Gmail")] && stored.effort == .low)

        // Edited: manual, off.
        made.schedule = nil
        made.isEnabled = false
        let edit = UUID()
        link.say(.saveAutomation(requestID: edit, automation: made))
        guard case .automations(_, let edited, _, _) = await tests.answer(link, edit) else { Issue.record("not edited"); return }
        #expect(edited.first?.schedule == nil && edited.first?.isEnabled == false && w.automation(made.id)?.trigger == .manual)

        // An unknown step app is refused.
        var bad = made
        bad.steps = [RemoteStep(app: "spaceship", text: "fly")]
        let refused = UUID()
        link.say(.saveAutomation(requestID: refused, automation: bad))
        guard case .reply(_, false, _, _) = await tests.answer(link, refused) else { Issue.record("saved nonsense"); return }

        // Run now: a run chat the phone can open.
        let run = UUID()
        link.say(.runAutomation(requestID: run, automationID: made.id))
        guard case .reply(_, true, _, let chatID?) = await tests.answer(link, run) else { Issue.record("didn't run"); return }
        #expect(w.chat(chatID)?.automationID == made.id)
        let end = Date.now.addingTimeInterval(20)
        while w.isRunning(chatID), Date.now < end { try? await Task.sleep(for: .milliseconds(20)) }
        let again = UUID()
        link.say(.listAutomations(requestID: again))
        guard case .automations(_, let after, _, _) = await tests.answer(link, again) else { Issue.record("no list"); return }
        #expect(after.first?.runs.map(\.id) == [chatID] && after.first?.lastRunAt != nil)

        let delete = UUID()
        link.say(.deleteAutomation(requestID: delete, automationID: made.id))
        guard case .automations(_, let gone, _, _) = await tests.answer(link, delete) else { Issue.record("not deleted"); return }
        #expect(gone.isEmpty && w.automations.isEmpty)
    }
}

/// The crew from the phone.
@MainActor @Suite(.serialized) struct RemoteCrewTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    @Test func hireEditTalkDeleteAndUndo() async throws {
        let brain = ScriptedBrain([.textDelta("on it"), .done])
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        let host = RemoteHost(workspace: w, macName: "Mac", macID: UUID(), localInterval: .milliseconds(20), cloudInterval: .milliseconds(200))
        host.drawAvatar = { avatar in Data("png:\(avatar.skin)".utf8) }
        defer { withExtendedLifetime(host) {} }
        let link = FakeLink()
        host.attach(link)
        let tests = RemoteProjectsTests()

        let list = UUID()
        link.say(.listCrew(requestID: list))
        guard case .crew(_, let first, let parts) = await tests.answer(link, list) else { Issue.record("no crew"); return }
        #expect(parts.map(\.key) == AgentAvatar.Part.allCases.map(\.rawValue) && parts.first?.count == 6)
        let head = first.first { $0.isHeadMaster }
        #expect(head != nil)

        // Hired on the phone.
        var hired = RemoteCrewMember(name: "  Quill ", role: "Writer", instructions: "Short sentences.",
                                     avatar: RemoteAvatar(parts: ["skin": 2, "hair": 3]), agent: "claude")
        let save = UUID()
        link.say(.saveCrew(requestID: save, member: hired))
        guard case .crew(_, let crew, _) = await tests.answer(link, save) else { Issue.record("not hired"); return }
        let quill = try #require(crew.first { $0.id == hired.id })
        #expect(quill.name == "Quill" && quill.role == "Writer" && quill.image == Data("png:2".utf8) && quill.status == "idle")
        #expect(w.agent(hired.id)?.avatar.hair == 3)

        hired.role = "Editor"
        let edit = UUID()
        link.say(.saveCrew(requestID: edit, member: hired))
        guard case .crew = await tests.answer(link, edit) else { Issue.record("not edited"); return }
        #expect(w.agent(hired.id)?.role == "Editor")

        // A preview of a look.
        let draw = UUID()
        link.say(.drawAvatar(requestID: draw, avatar: RemoteAvatar(parts: ["skin": 5])))
        guard case .avatarImage(_, let png) = await tests.answer(link, draw) else { Issue.record("no picture"); return }
        #expect(png == Data("png:5".utf8))

        // Talk: a chat with Quill, not opened on the Mac.
        let talk = UUID()
        link.say(.talkTo(requestID: talk, memberID: hired.id, text: "Draft the intro"))
        guard case .reply(_, true, _, let chatID?) = await tests.answer(link, talk) else { Issue.record("no chat"); return }
        #expect(w.chat(chatID)?.agentID == hired.id && !w.openChatIDs.contains(chatID))
        let end = Date.now.addingTimeInterval(20)
        while brain.requests.withLock({ $0.isEmpty }), Date.now < end { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(brain.requests.withLock { $0.last?.prompt.contains("Draft the intro") } == true)

        // HeadMaster stays; Quill goes and comes back with the chat.
        let fire = UUID()
        link.say(.deleteCrew(requestID: fire, memberID: try #require(head).id))
        guard case .reply(_, false, _, _) = await tests.answer(link, fire) else { Issue.record("fired the founder"); return }
        let delete = UUID(), undo = UUID()
        link.say(.deleteCrew(requestID: delete, memberID: hired.id))
        guard case .crew(_, let without, _) = await tests.answer(link, delete) else { Issue.record("not deleted"); return }
        #expect(!without.contains { $0.id == hired.id } && w.chat(chatID)?.agentID == nil)
        link.say(.undoDeleteCrew(requestID: undo))
        guard case .crew(_, let back, _) = await tests.answer(link, undo) else { Issue.record("not undone"); return }
        #expect(back.contains { $0.id == hired.id } && w.chat(chatID)?.agentID == hired.id)
    }
}
