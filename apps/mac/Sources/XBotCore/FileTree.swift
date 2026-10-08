import Foundation

public struct FileNode: Identifiable, Equatable, Sendable {
    public var url: URL
    public var name: String
    public var isFolder: Bool
    /// Gone from disk, still in git: shown struck through until the deletion is committed.
    public var isDeleted = false
    public var id: String { url.path }
}

/// The explorer's view of a folder: what is in it, and how git sees each thing.
public enum FileTree {
    static let hidden: Set<String> = [".DS_Store"]

    /// Folders first, then files, each by name as Finder sorts. Files git knows were deleted are
    /// listed where they were.
    public static func children(of folder: URL, root: URL, deleted: [String]) -> [FileNode] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var nodes = urls.filter { !hidden.contains($0.lastPathComponent) }.map { url in
            FileNode(url: url, name: url.lastPathComponent,
                     isFolder: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
        }
        let here = relativePath(folder, in: root)
        for path in deleted where (path as NSString).deletingLastPathComponent == here {
            let name = (path as NSString).lastPathComponent
            if !nodes.contains(where: { $0.name == name }) {
                nodes.append(FileNode(url: root.appending(path: path), name: name, isFolder: false, isDeleted: true))
            }
        }
        return nodes.sorted { a, b in
            a.isFolder != b.isFolder ? a.isFolder : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Each changed file's letter, and for each folder above it the strongest letter inside:
    /// conflict, then deleted, then modified, then added.
    public static func letters(_ status: GitStatus) -> [String: Character] {
        func rank(_ c: Character) -> Int {
            switch c {
            case "C": 4
            case "D": 3
            case "M", "R": 2
            default: 1
            }
        }
        var result: [String: Character] = [:]
        for file in status.files {
            result[file.path] = file.letter
            var folder = (file.path as NSString).deletingLastPathComponent
            while !folder.isEmpty {
                if result[folder].map({ rank($0) < rank(file.letter) }) ?? true { result[folder] = file.letter }
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return result
    }

    /// "docs/a.md" for a file in the project; "" for the project itself.
    public static func relativePath(_ url: URL, in root: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let base = root.standardizedFileURL.path(percentEncoded: false)
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let trimmedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        if trimmedPath == trimmedBase { return "" }
        return trimmedPath.hasPrefix(trimmedBase + "/") ? String(trimmedPath.dropFirst(trimmedBase.count + 1)) : trimmedPath
    }

    /// How a file is named to the agent: "@docs/a.md".
    public static func mention(_ url: URL, in root: URL) -> String { "@" + relativePath(url, in: root) }

    /// "untitled", or "untitled 2" if that is taken, and so on.
    public static func newName(_ base: String, in folder: URL) -> String {
        var name = base
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: name).path) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }
}
