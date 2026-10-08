import Foundation
import Testing
@testable import XBotCore

@Suite struct GitStatusTests {
    func z(_ records: String...) -> String { records.joined(separator: "\0") + "\0" }

    @Test func branchAndCounts() {
        let s = GitStatus.parse(z("# branch.oid abc", "# branch.head master", "# branch.upstream origin/master", "# branch.ab +2 -1"))
        #expect(s.branch == "master" && s.upstream == "origin/master" && s.ahead == 2 && s.behind == 1)
        #expect(s.state == .diverged(ahead: 2, behind: 1))
    }

    @Test func pathsWithSpacesAndRenames() {
        let s = GitStatus.parse(z(
            "# branch.head main",
            "1 .M N... 100644 100644 100644 aaa bbb docs/a b.md",
            "2 R. N... 100644 100644 100644 aaa bbb R100 new name.swift", "old name.swift",
            "? notes/to do.txt"))
        #expect(s.files.map(\.path) == ["docs/a b.md", "new name.swift", "notes/to do.txt"])
        #expect(s.files[0].letter == "M" && !s.files[0].isStaged)
        #expect(s.files[1].originalPath == "old name.swift" && s.files[1].letter == "R" && s.files[1].isStaged)
        #expect(s.files[2].letter == "U" && s.files[2].isUntracked)
        #expect(s.state == .changes(3))
    }

    @Test func conflictsAreConflicts() {
        let s = GitStatus.parse(z("# branch.head main", "u UU N... 100644 100644 100644 100644 a b c both.swift"))
        #expect(s.files.first?.path == "both.swift")
        #expect(s.files.first?.isConflicted == true && s.files.first?.letter == "C")
        #expect(s.state == .conflict(1))
    }

    @Test func detachedHeadHasNoBranch() {
        #expect(GitStatus.parse(z("# branch.head (detached)")).branch == nil)
    }

    @Test func stateOrder() {
        #expect(GitStatus(branch: "m", upstream: "o/m").state == .upToDate)
        #expect(GitStatus(branch: "m", upstream: "o/m", ahead: 3).state == .toPush(3))
        #expect(GitStatus(branch: "m", upstream: "o/m", behind: 1).state == .toPull(1))
        #expect(GitStatus(branch: "m", upstream: nil).state == .local)
        #expect(GitStatus(branch: "m", upstream: "o/m", ahead: 1, files: [GitFile(path: "a", unstaged: "M")]).state == .changes(1))
    }

    @Test func numstatTotalsSkipBinaries() {
        #expect(DiffTotals.parse(numstat: "10\t2\ta.swift\n-\t-\tlogo.png\n3\t0\tb.md\n") == DiffTotals(added: 13, removed: 2))
    }

    @Test func gitNeverPromptsOrLocks() throws {
        let tool = try #require(GitTool.find())
        #expect(tool.environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(tool.environment["GIT_OPTIONAL_LOCKS"] == "0")
        #expect(tool.environment["GIT_SSH_COMMAND"]?.contains("BatchMode=yes") == true
                || ProcessInfo.processInfo.environment["GIT_SSH_COMMAND"] != nil)
    }

    @Test func findSkipsTheStubWithoutCommandLineTools() {
        #expect(GitTool.find(searchPath: "/usr/bin", fileExists: { $0 == "/usr/bin/git" }) == nil)
        #expect(GitTool.find(searchPath: "/usr/bin", fileExists: {
            ["/usr/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git"].contains($0)
        })?.git.path == "/usr/bin/git")
    }

    @Test func runsGitAndReportsFailure() async throws {
        let tool = try #require(GitTool.find())
        let folder = FileManager.default.temporaryDirectory
        #expect(await tool.git(["--version"], in: folder).output.hasPrefix("git version"))
        let bad = await tool.git(["no-such-command"], in: folder)
        #expect(!bad.succeeded && !bad.error.isEmpty)
    }
}
