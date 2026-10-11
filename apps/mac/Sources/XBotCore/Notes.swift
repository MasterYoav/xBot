import Foundation
import Observation

/// A project's notes: markdown files in `<project>/notes/`, so they live in the repository, travel
/// with it through git, and an agent asked about "the release notes" can simply read them.
@MainActor @Observable
public final class ProjectNotes {
    public struct Note: Identifiable, Equatable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let title: String
        public let modified: Date
    }

    public let folder: URL
    public private(set) var notes: [Note] = []
    public private(set) var selected: URL?
    /// The open note's text, as the editor has it.
    public var text = "" { didSet { if text != saved { dirty = true } } }
    public private(set) var dirty = false
    @ObservationIgnored private var saved = ""

    public var notesFolder: URL { folder.appending(path: "notes", directoryHint: .isDirectory) }

    public init(folder: URL) { self.folder = folder }

    /// Reads the folder again. The open note's text is replaced from disk only when the editor has
    /// nothing unsaved: an agent's edit is shown, the person's typing is never thrown away.
    public func reload() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: notesFolder.path)) ?? []
        notes = names.filter { $0.lowercased().hasSuffix(".md") && !$0.hasPrefix(".") }.compactMap { name in
            let url = notesFolder.appending(path: name)
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Note(url: url, title: Self.title(of: body), modified: modified)
        }
        .sorted { $0.modified > $1.modified }
        if let selected, notes.contains(where: { $0.url == selected }) {
            if !dirty { load(selected) }
        } else if let first = notes.first {
            load(first.url)
        } else {
            selected = nil
            setText("")
        }
    }

    public func open(_ url: URL) {
        if dirty { try? save() }
        load(url)
    }

    @discardableResult
    public func create() throws -> Note {
        if dirty { try save() }
        try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        // Empty: the first thing typed is the title. A placeholder heading was left behind above it.
        let url = uniqueURL(for: "untitled")
        let body = ""
        try body.write(to: url, atomically: true, encoding: .utf8)
        reload()
        load(url)
        return notes.first { $0.url == url } ?? Note(url: url, title: Self.title(of: body), modified: .now)
    }

    /// Writes the open note, and names its file after its title when the title has changed.
    public func save() throws {
        guard let current = selected else { return }
        try text.write(to: current, atomically: true, encoding: .utf8)
        saved = text
        dirty = false
        var url = current
        let wanted = Self.slug(Self.title(of: text))
        let stem = current.deletingPathExtension().lastPathComponent
        if !wanted.isEmpty, stem != wanted, !Self.isNumbered(stem, of: wanted) {
            let target = uniqueURL(for: wanted)
            try FileManager.default.moveItem(at: current, to: target)
            url = target
        }
        selected = url
        let unsaved = text
        reload()
        // reload() keeps the text when clean; make sure the editor still has exactly what it had.
        if text != unsaved { setText(unsaved) }
    }

    /// Moves the note to the Trash. Returns what puts it back, for Undo.
    public func delete(_ url: URL) throws -> () throws -> Void {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        if selected == url { selected = nil; dirty = false }
        reload()
        let from = trashed as URL?
        return { [weak self] in
            guard let from else { return }
            try FileManager.default.moveItem(at: from, to: url)
            self?.reload()
            self?.open(url)
        }
    }

    // MARK: Naming

    public static func title(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let stripped = line.map { String($0.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
        return stripped.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Untitled")
    }

    public static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .init(identifier: "en"))
        var result = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                result.unicodeScalars.append(scalar)
            } else if !result.hasSuffix("-"), !result.isEmpty {
                result += "-"
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return String(result.prefix(60))
    }

    /// "ideas-2" is already the right name for a note titled "Ideas" whose "ideas.md" was taken.
    private static func isNumbered(_ stem: String, of base: String) -> Bool {
        guard stem.hasPrefix(base + "-") else { return false }
        return Int(stem.dropFirst(base.count + 1)) != nil
    }

    private func uniqueURL(for stem: String) -> URL {
        var url = notesFolder.appending(path: "\(stem).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = notesFolder.appending(path: "\(stem)-\(n).md")
            n += 1
        }
        return url
    }

    private func load(_ url: URL) {
        selected = url
        setText((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    private func setText(_ value: String) {
        saved = value
        text = value
        dirty = false
    }
}
