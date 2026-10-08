import Foundation

/// One changed file, from `git status --porcelain=v2`.
public struct GitFile: Equatable, Hashable, Sendable, Identifiable {
    public var path: String
    public var originalPath: String? = nil
    /// The index's change (M, A, D, R, C), or nil.
    public var staged: Character? = nil
    /// The working tree's change, or nil.
    public var unstaged: Character? = nil
    public var isUntracked = false
    public var isConflicted = false

    public var id: String { path }
    public var isStaged: Bool { staged != nil }
    /// What the panel shows: C for a conflict, U untracked, else the working tree's change, else the index's.
    public var letter: Character { isConflicted ? "C" : isUntracked ? "U" : (unstaged ?? staged ?? "M") }
}

public enum GitState: Equatable, Sendable {
    case upToDate, changes(Int), toPush(Int), toPull(Int), diverged(ahead: Int, behind: Int), conflict(Int), local
}

public struct GitStatus: Equatable, Sendable {
    public var branch: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var files: [GitFile]

    public init(branch: String? = nil, upstream: String? = nil, ahead: Int = 0, behind: Int = 0, files: [GitFile] = []) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.files = files
    }

    /// The one state the panel leads with: conflicts, then what blocks a push, then work in hand.
    public var state: GitState {
        let conflicts = files.filter(\.isConflicted).count
        if conflicts > 0 { return .conflict(conflicts) }
        if ahead > 0 && behind > 0 { return .diverged(ahead: ahead, behind: behind) }
        if behind > 0 { return .toPull(behind) }
        if !files.isEmpty { return .changes(files.count) }
        if upstream == nil { return .local }
        if ahead > 0 { return .toPush(ahead) }
        return .upToDate
    }

    /// `git status --porcelain=v2 --branch -z`. Fields are space-separated up to the path, which may
    /// itself hold spaces; a rename's original path is the record after it.
    public static func parse(_ output: String) -> GitStatus {
        var status = GitStatus()
        var records = output.split(separator: "\0").map(String.init)[...]
        func flag(_ c: Character) -> Character? { c == "." ? nil : c }
        while let record = records.popFirst() {
            if record.hasPrefix("# ") {
                let parts = record.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count == 3 else { continue }
                switch parts[1] {
                case "branch.head": status.branch = parts[2] == "(detached)" ? nil : parts[2]
                case "branch.upstream": status.upstream = parts[2]
                case "branch.ab":
                    let ab = parts[2].split(separator: " ")
                    status.ahead = ab.first.flatMap { Int($0.dropFirst()) } ?? 0
                    status.behind = ab.dropFirst().first.flatMap { Int($0.dropFirst()) } ?? 0
                default: break
                }
                continue
            }
            switch record.first {
            case let kind? where kind == "1" || kind == "2" || kind == "u":
                let fields = kind == "1" ? 8 : kind == "2" ? 9 : 10
                let parts = record.split(separator: " ", maxSplits: fields, omittingEmptySubsequences: false)
                guard parts.count == fields + 1, parts[1].count == 2 else { continue }
                let xy = Array(parts[1])
                var file = GitFile(path: String(parts[fields]), staged: flag(xy[0]), unstaged: flag(xy[1]))
                if kind == "2" { file.originalPath = records.popFirst() }
                if kind == "u" { file.isConflicted = true }
                status.files.append(file)
            case "?":
                status.files.append(GitFile(path: String(record.dropFirst(2)), isUntracked: true))
            default:
                break
            }
        }
        return status
    }
}

public struct DiffTotals: Equatable, Sendable {
    public var added: Int
    public var removed: Int

    public init(added: Int = 0, removed: Int = 0) {
        self.added = added
        self.removed = removed
    }

    /// `git diff --numstat`: "added<TAB>removed<TAB>path"; binary files say "-" and are not counted.
    public static func parse(numstat: String) -> DiffTotals {
        numstat.split(separator: "\n").reduce(into: DiffTotals()) { totals, line in
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { return }
            totals.added += Int(parts[0]) ?? 0
            totals.removed += Int(parts[1]) ?? 0
        }
    }
}
