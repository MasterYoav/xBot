import Foundation

// Projects on the phone: the Explorer, files, and the Changes panel, as the Mac shows them.

/// A row in a project's file list.
public struct RemoteFileEntry: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    /// Relative to the project's folder.
    public var path: String
    public var isFolder: Bool
    /// Git knows it was deleted; listed where it was.
    public var isDeleted: Bool
    /// Git's letter (M, A, D, U, C, R) for the file, or the strongest one inside a folder.
    public var letter: String?
    public var id: String { path }

    public init(name: String, path: String, isFolder: Bool, isDeleted: Bool = false, letter: String? = nil) {
        self.name = name
        self.path = path
        self.isFolder = isFolder
        self.isDeleted = isDeleted
        self.letter = letter
    }
}

/// A file's contents. `text` is nil for a binary file; long files come cut at `RemoteFile.limit`.
public struct RemoteFile: Codable, Equatable, Sendable {
    public var path: String
    public var text: String?
    public var size: Int
    public var truncated: Bool

    /// What fits comfortably in one iCloud record with room to spare.
    public static let limit = 256 * 1024

    public init(path: String, text: String?, size: Int, truncated: Bool) {
        self.path = path
        self.text = text
        self.size = size
        self.truncated = truncated
    }
}

public struct RemoteGitFile: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var originalPath: String?
    public var letter: String
    public var isStaged: Bool
    public var isConflicted: Bool
    public var id: String { path }

    public init(path: String, originalPath: String? = nil, letter: String, isStaged: Bool, isConflicted: Bool = false) {
        self.path = path
        self.originalPath = originalPath
        self.letter = letter
        self.isStaged = isStaged
        self.isConflicted = isConflicted
    }
}

public struct RemotePullRequest: Codable, Equatable, Sendable {
    public var number: Int
    public var title: String
    /// "open", "draft", "merged", "closed".
    public var state: String
    public var url: String
    /// "passing", "failing", "running", or nil when there are no checks.
    public var checks: String?
    /// "approved", "changesRequested", "reviewRequired", or nil.
    public var review: String?

    public init(number: Int, title: String, state: String, url: String, checks: String? = nil, review: String? = nil) {
        self.number = number
        self.title = title
        self.state = state
        self.url = url
        self.checks = checks
        self.review = review
    }
}

/// What the Changes panel shows.
public struct RemoteGit: Codable, Equatable, Sendable {
    public var isRepository: Bool
    public var branch: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var files: [RemoteGitFile]
    public var added: Int
    public var removed: Int
    /// A pull couldn't fast-forward: the branches need merging first.
    public var needsMerge: Bool
    public var pullRequest: RemotePullRequest?
    /// The last git command's error, if any.
    public var problem: String?

    public init(isRepository: Bool, branch: String? = nil, upstream: String? = nil, ahead: Int = 0, behind: Int = 0,
                files: [RemoteGitFile] = [], added: Int = 0, removed: Int = 0, needsMerge: Bool = false,
                pullRequest: RemotePullRequest? = nil, problem: String? = nil) {
        self.isRepository = isRepository
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.files = files
        self.added = added
        self.removed = removed
        self.needsMerge = needsMerge
        self.pullRequest = pullRequest
        self.problem = problem
    }
}

public struct RemoteDiffLine: Codable, Equatable, Sendable, Identifiable {
    /// "hunk", "context", "added", "removed".
    public var kind: String
    public var old: Int?
    public var new: Int?
    public var text: String
    public var id: Int

    public init(id: Int, kind: String, old: Int? = nil, new: Int? = nil, text: String) {
        self.id = id
        self.kind = kind
        self.old = old
        self.new = new
        self.text = text
    }
}

public enum RemoteGitAction: Codable, Equatable, Sendable {
    case stage(path: String)
    case unstage(path: String)
    case discard(path: String)
    /// Commits what is staged, or everything when nothing is.
    case commit(message: String)
    case sync
    case publish
    case fetch
}

public enum RemoteFileAction: Codable, Equatable, Sendable {
    /// In `folder` ("" for the project's top); the Mac picks a free name like "untitled 2".
    case newFile(folder: String)
    case newFolder(folder: String)
    case rename(path: String, to: String)
    /// To the Mac's Trash, so it can be put back from there.
    case trash(path: String)
}

/// A folder on the Mac, when picking one to add as a project.
public struct RemoteFolder: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    /// Absolute on the Mac.
    public var path: String
    public var isProject: Bool
    public var id: String { path }

    public init(name: String, path: String, isProject: Bool = false) {
        self.name = name
        self.path = path
        self.isProject = isProject
    }
}
