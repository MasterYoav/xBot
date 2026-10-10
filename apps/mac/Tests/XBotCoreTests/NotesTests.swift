import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct NotesTests {
    func project() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "proj-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aProjectWithNoNotesFolderHasNoNotes() throws {
        let notes = ProjectNotes(folder: try project())
        notes.reload()
        #expect(notes.notes.isEmpty && notes.selected == nil)
    }

    @Test func aNewNoteIsAMarkdownFileInTheProjectsNotesFolder() throws {
        let folder = try project()
        let notes = ProjectNotes(folder: folder)
        let note = try notes.create()
        #expect(note.url.deletingLastPathComponent().lastPathComponent == "notes")
        #expect(note.url.pathExtension == "md")
        #expect(notes.selected == note.url)
        #expect(notes.text.isEmpty)
        #expect(note.title == String(localized: "Untitled"))
        #expect(FileManager.default.fileExists(atPath: note.url.path))
        // A second one gets its own file.
        let second = try notes.create()
        #expect(second.url != note.url && notes.notes.count == 2)
    }

    /// The file is named after the note's first line, so the folder reads well in Finder and git.
    @Test func savingNamesTheFileAfterTheTitle() throws {
        let notes = ProjectNotes(folder: try project())
        _ = try notes.create()
        notes.text = "# v2.1 — Abilities & Notes!\n\n- connectors\n"
        try notes.save()
        let url = try #require(notes.selected)
        #expect(url.lastPathComponent == "v2-1-abilities-notes.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == notes.text)
        #expect(notes.notes.map(\.title) == ["v2.1 — Abilities & Notes!"])
    }

    @Test func twoNotesWithTheSameTitleKeepSeparateFiles() throws {
        let notes = ProjectNotes(folder: try project())
        for _ in 0..<2 {
            _ = try notes.create()
            notes.text = "# Ideas\n"
            try notes.save()
        }
        #expect(Set(notes.notes.map { $0.url.lastPathComponent }) == ["ideas.md", "ideas-2.md"])
    }

    @Test func newestFirstAndOnlyMarkdown() throws {
        let folder = try project()
        let dir = folder.appending(path: "notes")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# Old".write(to: dir.appending(path: "old.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: dir.appending(path: "old.md").path)
        try "# New".write(to: dir.appending(path: "new.md"), atomically: true, encoding: .utf8)
        try "not a note".write(to: dir.appending(path: "image.png"), atomically: true, encoding: .utf8)
        let notes = ProjectNotes(folder: folder)
        notes.reload()
        #expect(notes.notes.map(\.title) == ["New", "Old"])
        #expect(notes.selected?.lastPathComponent == "new.md" && notes.text == "# New")
    }

    @Test func deletingGoesToTheTrashAndUndoBringsItBack() throws {
        let notes = ProjectNotes(folder: try project())
        _ = try notes.create()
        notes.text = "# Keep me\nbody"
        try notes.save()
        let url = try #require(notes.selected)
        let restore = try notes.delete(url)
        #expect(notes.notes.isEmpty && !FileManager.default.fileExists(atPath: url.path))
        try restore()
        #expect(notes.notes.map(\.title) == ["Keep me"])
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Keep me\nbody")
    }

    /// An agent edited the note on disk: shown, unless there are unsaved changes in the editor.
    @Test func changesOnDiskAreReadUnlessTheEditorHasUnsavedText() throws {
        let notes = ProjectNotes(folder: try project())
        _ = try notes.create()
        notes.text = "# Plan\n"
        try notes.save()
        let url = try #require(notes.selected)
        try "# Plan\n- added by the agent\n".write(to: url, atomically: true, encoding: .utf8)
        notes.reload()
        #expect(notes.text == "# Plan\n- added by the agent\n")
        notes.text = "# Plan\n- mine, unsaved\n"
        try "# Plan\n- agent again\n".write(to: url, atomically: true, encoding: .utf8)
        notes.reload()
        #expect(notes.text == "# Plan\n- mine, unsaved\n")
    }

    @Test func titlesComeFromTheFirstLine() {
        #expect(ProjectNotes.title(of: "## Release 2.1\n\nstuff") == "Release 2.1")
        #expect(ProjectNotes.title(of: "\n\nplain first line\n") == "plain first line")
        #expect(ProjectNotes.title(of: "   ") == String(localized: "Untitled"))
        #expect(ProjectNotes.slug("Ünïcode: Spaces / Slashes!") == "unicode-spaces-slashes")
    }
}
