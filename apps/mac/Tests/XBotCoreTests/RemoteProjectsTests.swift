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
        case .reply(let r, _, _, _), .folder(let r, _), .file(let r, _), .git(let r, _), .diff(let r, _), .macFolders(let r, _, _): r
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
