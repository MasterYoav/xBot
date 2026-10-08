import Foundation

/// The branch checked out in a folder, read straight from `.git/HEAD` — no `git` process.
public enum GitBranch {
    public static func current(in folder: URL) -> String? {
        var gitDir = folder.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            // A worktree: `.git` is a file pointing at the real git directory.
            guard let text = try? String(contentsOf: gitDir, encoding: .utf8),
                  let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: ") else { return nil }
            let path = String(line.dropFirst("gitdir: ".count))
            gitDir = path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)
        }
        guard let head = try? String(contentsOf: gitDir.appending(path: "HEAD"), encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        // A detached HEAD is a commit, not a branch.
        guard trimmed.hasPrefix("ref: refs/heads/") else { return nil }
        return String(trimmed.dropFirst("ref: refs/heads/".count))
    }
}
