import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct UnifiedDiffTests {
    @Test func numbersFollowTheHunk() {
        let text = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -3,3 +3,3 @@ func x()
         keep
        -old
        +new
        \\ No newline at end of file
        """
        let lines = UnifiedDiff.parse(text)
        #expect(lines.map(\.kind) == [.hunk, .context, .removed, .added])
        #expect(lines[1].old == 3 && lines[1].new == 3)
        #expect(lines[2].old == 4 && lines[2].new == nil)
        #expect(lines[3].old == nil && lines[3].new == 4)
        #expect(lines[3].text == "new")
    }

    @Test func anUntrackedFileDiffsAsAllAdded() async throws {
        let repo = try TempRepo.make()
        try repo.write("fresh.txt", "a\nb\n")
        let git = ProjectGit(directory: repo.work, tool: GitTool.find()!)
        await git.refresh()
        let file = try #require(git.status?.files.first { $0.path == "fresh.txt" })
        let lines = await git.diff(file)
        #expect(lines.filter { $0.kind == .added }.map(\.text) == ["a", "b"])
        #expect(git.problem == nil)
    }

    @Test func aTrackedFileDiffsAgainstTheLastCommit() async throws {
        let repo = try TempRepo.make()
        try repo.write("a.txt", "two\n")
        let git = ProjectGit(directory: repo.work, tool: GitTool.find()!)
        await git.refresh()
        let lines = await git.diff(try #require(git.status?.files.first))
        #expect(lines.filter { $0.kind != .hunk }.map(\.text) == ["one", "two"])
    }
}
