import Foundation
import Observation

/// One project's git: the state it is in, and the everyday actions on it. Every action ends by
/// reading the status again; a failing command leaves git's own message in `problem`.
@MainActor
@Observable
public final class ProjectGit {
    public let directory: URL
    let tool: GitTool
    public private(set) var status: GitStatus?
    public private(set) var isRepository = true
    public private(set) var totals = DiffTotals()
    public private(set) var pullRequest: PullRequest?
    public private(set) var remote: GitHubRemote?
    public private(set) var problem: String?
    public private(set) var isBusy = false
    /// A sync's pull could not fast-forward: the branches must be merged, which is the agent's job.
    public private(set) var needsMerge = false
    /// Bumped by every refresh, so the explorer knows to read its folders and colours again.
    public private(set) var generation = 0
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var wantsPullRequest = false

    public init(directory: URL, tool: GitTool) {
        self.directory = directory
        self.tool = tool
    }

    /// Reads the state again. Overlapping calls do not race: one pass runs at a time, and a call
    /// that arrives during a pass waits for a pass that starts after it. The folder watcher leaves
    /// the pull request alone — asking GitHub on every saved file would be a network call a second.
    public func refresh(pullRequest: Bool = true) async {
        wantsPullRequest = wantsPullRequest || pullRequest
        if let running = refreshing {
            again = true
            await running.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                again = false
                let withPullRequest = wantsPullRequest
                wantsPullRequest = false
                await readState(pullRequest: withPullRequest)
            } while again
            // Cleared here, in the same step that saw `again` false, so no call can slip between.
            refreshing = nil
        }
        refreshing = task
        await task.value
    }

    /// Observation fires on every assignment, equal or not, and each one redraws the panels; so
    /// state is only set when it differs, and a new generation only begins when something changed.
    private func readState(pullRequest: Bool) async {
        guard await tool.git(["rev-parse", "--is-inside-work-tree"], in: directory).succeeded else {
            if isRepository || status != nil {
                isRepository = false
                status = nil
                totals = DiffTotals()
                generation += 1
            }
            return
        }
        let result = await tool.git(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: directory)
        guard result.succeeded else {
            problem = result.error
            return
        }
        let newStatus = GitStatus.parse(result.output)
        // A repository with no commit yet has no HEAD to compare with: no totals, and not an error.
        let numstat = await tool.git(["diff", "--numstat", "HEAD"], in: directory)
        let newTotals = numstat.succeeded ? DiffTotals.parse(numstat: numstat.output) : DiffTotals()
        if !isRepository { isRepository = true }
        if newStatus.behind == 0, needsMerge { needsMerge = false }
        if newTotals != totals { totals = newTotals }
        if newStatus != status {
            status = newStatus
            generation += 1
        }
        if pullRequest { await refreshPullRequest() }
    }

    /// The branch's pull request through gh, when gh is installed and signed in; otherwise none.
    private func refreshPullRequest() async {
        let url = await tool.git(["remote", "get-url", "origin"], in: directory)
        let parsedRemote = url.succeeded ? GitHubRemote.parse(url.output) : nil
        if parsedRemote != remote { remote = parsedRemote }
        guard let remote, let branch = status?.branch,
              let result = await tool.gh(["pr", "view", branch, "-R", remote.slug, "--json", PullRequest.fields], in: directory),
              result.succeeded else {
            if pullRequest != nil { pullRequest = nil }
            return
        }
        let parsed = PullRequest.parse(json: result.output)
        if parsed != pullRequest { pullRequest = parsed }
    }

    public func fetch() async { await perform(["fetch", "--quiet"]) }

    /// Commits what is staged, or everything when nothing is.
    @discardableResult
    public func commit(_ message: String) async -> Bool {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return false }
        if !(status?.files.contains(where: \.isStaged) ?? false) {
            guard await perform(["add", "-A"], refreshing: false) else { return false }
        }
        return await perform(["commit", "--quiet", "-m", message])
    }

    /// Pull (fast-forward only), then push. A pull that cannot fast-forward stops there and sets
    /// `needsMerge`.
    public func sync() async {
        // What the remote has now, not at the last fetch: otherwise the push is simply refused.
        guard await perform(["fetch", "--quiet"]) else { return }
        if (status?.behind ?? 0) > 0 {
            isBusy = true
            let pulled = await tool.git(["pull", "--ff-only", "--quiet"], in: directory)
            isBusy = false
            guard pulled.succeeded else {
                needsMerge = true
                await refresh()
                return
            }
        }
        if status?.upstream == nil {
            await publish()
        } else {
            await perform(["push", "--quiet"])
        }
    }

    /// Pushes a branch that has no upstream yet, and sets it.
    public func publish() async {
        guard let branch = status?.branch else { return }
        let remotes = await tool.git(["remote"], in: directory).output.split(separator: "\n").map(String.init)
        guard let remote = remotes.contains("origin") ? "origin" : remotes.first else {
            problem = String(localized: "This repository has no remote to publish to.")
            return
        }
        await perform(["push", "--quiet", "-u", remote, branch])
    }

    public func stage(_ file: GitFile) async {
        await perform(["add", "--"] + paths(file))
    }

    public func unstage(_ file: GitFile) async {
        await perform(["restore", "--staged", "--"] + paths(file))
    }

    /// Throws the file's changes away. An untracked file goes to the Trash; a newly added one leaves
    /// the index and goes to the Trash; anything else is restored from the last commit.
    public func discard(_ file: GitFile) async {
        let url = directory.appending(path: file.path)
        if file.isUntracked {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { problem = error.localizedDescription }
            await refresh()
        } else if file.staged == "A" {
            guard await perform(["rm", "--cached", "--quiet", "--", file.path], refreshing: false) else { return }
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            await refresh()
        } else {
            await perform(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + paths(file))
        }
    }

    /// The file's changes against the last commit. An untracked file is compared with nothing:
    /// `--no-index` exits 1 when the files differ, which here is the normal answer.
    public func diff(_ file: GitFile) async -> [DiffLine] {
        let result = file.isUntracked
            ? await tool.git(["diff", "--no-index", "--no-color", "--", "/dev/null", file.path], in: directory)
            : await tool.git(["diff", "--no-color", "HEAD", "--"] + paths(file), in: directory)
        guard result.status == 0 || (file.isUntracked && result.status == 1) else {
            problem = result.error
            return []
        }
        return UnifiedDiff.parse(result.output)
    }

    /// Of these project-relative paths, the ones git ignores.
    public func ignored(_ paths: [String]) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let result = await tool.git(["check-ignore", "--stdin", "-z"], in: directory,
                                    input: paths.joined(separator: "\0") + "\0")
        return Set(result.output.split(separator: "\0").map(String.init))
    }

    public func startWatching() {
        guard watcher == nil else { return }
        watcher = FolderWatcher(directory) { [weak self] in
            Task { await self?.refresh(pullRequest: false) }
        }
    }

    public func stopWatching() { watcher = nil }

    public func clearProblem() { problem = nil }

    private func paths(_ file: GitFile) -> [String] { [file.path] + (file.originalPath.map { [$0] } ?? []) }

    /// Runs a command; on failure keeps git's message. Reads the status again afterwards unless asked not to.
    @discardableResult
    private func perform(_ arguments: [String], refreshing: Bool = true) async -> Bool {
        isBusy = true
        let result = await tool.git(arguments, in: directory)
        isBusy = false
        problem = result.succeeded ? nil : (result.error.isEmpty ? result.output : result.error)
        if refreshing { await refresh() }
        return result.succeeded
    }
}
