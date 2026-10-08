import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct FileTreeTests {
    func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "tree-\(UUID().uuidString)")
        for dir in ["src", "Docs"] {
            try FileManager.default.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true)
        }
        for file in ["b.swift", "a.md", ".DS_Store", "src/x.swift"] {
            try "".write(to: root.appending(path: file), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func foldersFirstThenFilesByName() throws {
        let root = try folder()
        #expect(FileTree.children(of: root, root: root, deleted: []).map(\.name) == ["Docs", "src", "a.md", "b.swift"])
    }

    @Test func deletedFilesAppearWhereTheyWere() throws {
        let root = try folder()
        let nodes = FileTree.children(of: root.appending(path: "src"), root: root, deleted: ["src/gone.swift", "other/no.swift"])
        #expect(nodes.map(\.name) == ["gone.swift", "x.swift"])
        #expect(nodes.first?.isDeleted == true)
    }

    @Test func aFolderTakesTheStrongestLetterInside() {
        let status = GitStatus(files: [
            GitFile(path: "src/a.swift", unstaged: "M"),
            GitFile(path: "src/deep/b.swift", isUntracked: true),
            GitFile(path: "docs/c.md", unstaged: "D"),
        ])
        let letters = FileTree.letters(status)
        #expect(letters["src"] == "M" && letters["src/deep"] == "U" && letters["docs"] == "D")
        #expect(letters["src/a.swift"] == "M")
    }

    @Test func mentionIsRelative() throws {
        let root = try folder()
        #expect(FileTree.mention(root.appending(path: "src/x.swift"), in: root) == "@src/x.swift")
        #expect(FileTree.relativePath(root, in: root) == "")
    }

    @Test func newNamesDoNotCollide() throws {
        let root = try folder()
        try "".write(to: root.appending(path: "untitled"), atomically: true, encoding: .utf8)
        #expect(FileTree.newName("untitled", in: root) == "untitled 2")
        #expect(FileTree.newName("fresh", in: root) == "fresh")
    }

    @Test func mentionReachesTheComposer() async throws {
        let w = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory, discover: { [:] },
                          defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let root = try folder()
        let project = w.addProject(at: root)
        w.startDraft(in: project.id)
        let before = w.mentionRequest
        w.mention(root.appending(path: "a.md"))
        #expect(w.pendingMention == "@a.md" && w.mentionRequest == before + 1)
    }
}
