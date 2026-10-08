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

    @Test func filesInANewFolderAreListedOneByOne() async throws {
        let repo = try TempRepo.make()
        try FileManager.default.createDirectory(at: repo.work.appending(path: "new"), withIntermediateDirectories: true)
        try repo.write("new/one.txt", "1\n")
        try repo.write("new/two.txt", "2\n")
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        #expect(git.status?.files.map(\.path) == ["new/one.txt", "new/two.txt"])
    }

    @Test func aRefreshThatFindsNothingNewChangesNothing() async throws {
        let repo = try TempRepo.make()
        try repo.write("a.txt", "changed\n")
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        let generation = git.generation
        await git.refresh(pullRequest: false)
        // The explorer reads its folders again on every new generation; nothing changed, so none.
        #expect(git.generation == generation)
        try repo.write("b.txt", "new\n")
        await git.refresh(pullRequest: false)
        #expect(git.generation == generation + 1)
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

    @Test func syncFetchesFirst() async throws {
        let repo = try TempRepo.make()
        let git = ProjectGit(directory: repo.work, tool: tool)
        await git.refresh()
        try repo.pushFromElsewhere("theirs.txt")
        try repo.write("mine.txt", "mine\n")
        #expect(await git.commit("Mine"))
        #expect(git.status?.state == .toPush(1))
        await git.sync()
        // It could not have known about "theirs" without fetching: now it does, and asks for a merge.
        #expect(git.needsMerge)
        #expect(git.status?.state == .diverged(ahead: 1, behind: 1))
    }

    @Test func aWatcherRefreshLeavesThePullRequestAlone() async throws {
        let repo = try TempRepo.make()
        try repo.sh("remote", "set-url", "origin", "https://github.com/o/r.git")
        let log = repo.root.appending(path: "gh.log")
        let gh = repo.root.appending(path: "gh")
        try "#!/bin/sh\necho called >> '\(log.path)'\nexit 1\n".write(to: gh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
        let git = ProjectGit(directory: repo.work, tool: GitTool(git: tool.git, gh: gh, environment: tool.environment))
        await git.refresh(pullRequest: false)
        #expect(!FileManager.default.fileExists(atPath: log.path))
        await git.refresh()
        #expect(FileManager.default.fileExists(atPath: log.path))
    }

    @Test func refreshesThatOverlapRunOneAfterAnother() async throws {
        let repo = try TempRepo.make()
        let git = ProjectGit(directory: repo.work, tool: tool)
        async let one: Void = git.refresh()
        try repo.write("late.txt", "x\n")
        async let two: Void = git.refresh()
        _ = await (one, two)
        // Whatever the timing, the last word is a refresh that started after the file was written.
        #expect(git.status?.files.map(\.path) == ["late.txt"])
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
