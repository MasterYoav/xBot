import Foundation
import Testing
@testable import XBotCore

/// A clone of a bare repository in a temporary folder, with one commit pushed.
struct TempRepo {
    let root = FileManager.default.temporaryDirectory.appending(path: "xbot-git-\(UUID().uuidString)")
    var remote: URL { root.appending(path: "remote.git") }
    var work: URL { root.appending(path: "work") }

    func sh(_ args: String..., in dir: URL? = nil) throws {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/env")
        p.arguments = ["git"] + args
        p.currentDirectoryURL = dir ?? work
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    func write(_ name: String, _ text: String, in dir: URL? = nil) throws {
        try text.write(to: (dir ?? work).appending(path: name), atomically: true, encoding: .utf8)
    }

    func configure(_ dir: URL) throws {
        for (k, v) in [("user.name", "Test"), ("user.email", "t@example.com"), ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] {
            try sh("config", k, v, in: dir)
        }
    }

    static func make() throws -> TempRepo {
        let repo = TempRepo()
        try FileManager.default.createDirectory(at: repo.root, withIntermediateDirectories: true)
        try repo.sh("init", "--bare", "-b", "main", repo.remote.path, in: repo.root)
        try repo.sh("clone", "--quiet", repo.remote.path, repo.work.path, in: repo.root)
        try repo.configure(repo.work)
        try repo.sh("switch", "--quiet", "-c", "main")
        try repo.write("a.txt", "one\n")
        try repo.sh("add", ".")
        try repo.sh("commit", "--quiet", "-m", "first")
        try repo.sh("push", "--quiet", "-u", "origin", "main")
        return repo
    }

    /// A second clone pushes a commit, so this one is behind.
    func pushFromElsewhere(_ name: String) throws {
        let other = root.appending(path: "other-\(UUID().uuidString)")
        try sh("clone", "--quiet", remote.path, other.path, in: root)
        try configure(other)
        try write(name, "theirs\n", in: other)
        try sh("add", ".", in: other)
        try sh("commit", "--quiet", "-m", "theirs", in: other)
        try sh("push", "--quiet", in: other)
    }
}

@MainActor @Suite struct ProjectGitTests {
    let tool = GitTool.find()!

    @Test func cleanIsUpToDate() async throws {
        let repo = try TempRepo.make()
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        #expect(git.status?.state == .upToDate && git.status?.branch == "main")
        #expect(git.isRepository)
    }

    @Test func notARepository() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let git = ProjectGit(directory: folder, tool: tool)
        await git.refresh()
        #expect(!git.isRepository && git.status == nil)
    }

    @Test func commitStagesEverythingWhenNothingIsStaged() async throws {
        let repo = try TempRepo.make()
        try repo.write("a.txt", "one\ntwo\n")
        try repo.write("b.txt", "new\n")
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        #expect(git.status?.state == .changes(2))
        #expect(git.totals == DiffTotals(added: 1, removed: 0))
        #expect(await git.commit("Two files"))
        #expect(git.status?.state == .toPush(1))
        await git.sync()
        #expect(git.status?.state == .upToDate)
    }

    @Test func commitOnlyWhatIsStaged() async throws {
        let repo = try TempRepo.make()
        try repo.write("a.txt", "changed\n")
        try repo.write("b.txt", "new\n")
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        let b = try #require(git.status?.files.first { $0.path == "b.txt" })
        await git.stage(b)
        #expect(git.status?.files.first { $0.path == "b.txt" }?.isStaged == true)
        let staged = try #require(git.status?.files.first { $0.path == "b.txt" })
        await git.unstage(staged)
        #expect(git.status?.files.first { $0.path == "b.txt" }?.isStaged == false)
        await git.stage(b)
        #expect(await git.commit("Just b"))
        #expect(git.status?.files.map(\.path) == ["a.txt"])
    }

    @Test func discardRestoresATrackedFileAndRemovesAnUntrackedOne() async throws {
        let repo = try TempRepo.make()
        try repo.write("a.txt", "changed\n")
        try repo.write("c.txt", "scratch\n")
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        for file in git.status?.files ?? [] { await git.discard(file) }
        #expect(git.status?.state == .upToDate)
        #expect(try String(contentsOf: repo.work.appending(path: "a.txt"), encoding: .utf8) == "one\n")
        #expect(!FileManager.default.fileExists(atPath: repo.work.appending(path: "c.txt").path))
    }

    @Test func syncPullsThenPushes() async throws {
        let repo = try TempRepo.make()
        try repo.pushFromElsewhere("theirs.txt")
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.fetch()
        #expect(git.status?.state == .toPull(1))
        await git.sync()
        #expect(git.status?.state == .upToDate)
        #expect(FileManager.default.fileExists(atPath: repo.work.appending(path: "theirs.txt").path))
    }

    @Test func divergedSyncAsksForAMerge() async throws {
        let repo = try TempRepo.make()
        try repo.pushFromElsewhere("theirs.txt")
        try repo.write("mine.txt", "mine\n")
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        #expect(await git.commit("Mine"))
        await git.fetch()
        #expect(git.status?.state == .diverged(ahead: 1, behind: 1))
        await git.sync()
        #expect(git.needsMerge)
        #expect(git.status?.state == .diverged(ahead: 1, behind: 1))
    }

    @Test func publishSetsTheUpstream() async throws {
        let repo = try TempRepo.make()
        try repo.sh("switch", "--quiet", "-c", "feature")
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        #expect(git.status?.state == .local)
        await git.publish()
        #expect(git.status?.upstream == "origin/feature")
    }

    @Test func ignoredPaths() async throws {
        let repo = try TempRepo.make()
        try repo.write(".gitignore", "build/\n*.log\n")
        // A folder-only pattern matches a folder that exists, as the explorer's always do.
        try FileManager.default.createDirectory(at: repo.work.appending(path: "build"), withIntermediateDirectories: true)
        let git = ProjectGit(directory: repo.work, tool: tool)
        #expect(await git.ignored(["build", "a.txt", "x.log"]) == ["build", "x.log"])
    }

    @Test func aFailedCommandIsShownNotThrown() async throws {
        let repo = try TempRepo.make()
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        #expect(await git.commit("nothing to commit") == false)
        #expect(git.problem != nil)
    }
}
