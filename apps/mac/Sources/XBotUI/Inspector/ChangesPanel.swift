import SwiftUI
import XBotCore

/// The project's git: where it stands against its remote, its pull request, a commit box, and the
/// changed files. Conflicts are explained, not resolved here; merging is the agent's job.
struct ChangesPanel: View {
    let workspace: Workspace
    let project: Project
    let git: ProjectGit
    @State private var message = ""
    @State private var discarding: GitFile?

    var body: some View {
        ScrollView {
            // Lazy, so a burst of agent edits redraws the rows on screen, not one per changed file.
            LazyVStack(alignment: .leading, spacing: Space.m) {
                header
                if git.isRepository, let status = git.status {
                    stateLine(status)
                    if let pr = git.pullRequest { pullRequest(pr) }
                    if let problem = git.problem { problemCallout(problem) }
                    commitBox(status)
                    if git.needsMerge || isDiverged(status) { mergeCallout }
                    files(status)
                } else if !git.isRepository {
                    pill(.neutral, String(localized: "No git"), String(localized: "This folder isn't a git repository."))
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }
            }
            .padding(Space.m)
        }
        .scrollIndicators(.never)
        .confirmationDialog(
            String(localized: "Discard changes to \(discarding?.path ?? "")?"),
            isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })
        ) {
            Button(String(localized: "Discard Changes"), role: .destructive) {
                if let file = discarding { Task { await git.discard(file) } }
                discarding = nil
            }
        } message: {
            Text(String(localized: "This can't be undone."))
        }
    }

    // MARK: Header and state

    private var header: some View {
        HStack(spacing: Space.s) {
            Text(String(localized: "Changes")).emphasisText().foregroundStyle(Palette.textPrimary)
            if let status = git.status, let branch = status.branch {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                if status.behind > 0 { MonoLabel("↓\(status.behind)") }
                if status.ahead > 0 { MonoLabel("↑\(status.ahead)") }
            }
            Spacer(minLength: 0)
            if git.isBusy { ProgressView().controlSize(.mini) }
            Menu {
                Button(String(localized: "Fetch Now")) { Task { await git.fetch() } }
                if let remote = git.remote {
                    Button(String(localized: "Open on GitHub")) { NSWorkspace.shared.open(remote.webURL) }
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Palette.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func stateLine(_ status: GitStatus) -> some View {
        let upstream = status.upstream ?? "origin"
        switch status.state {
        case .upToDate:
            pill(.success, String(localized: "Up to date"), String(localized: "Nothing to commit. In step with \(upstream)."))
        case .changes(let n):
            pill(.accent, String(localized: "Changes"),
                 n == 1 ? String(localized: "1 file changed.") : String(localized: "\(n) files changed."))
        case .toPush(let n):
            pill(.running, String(localized: "To push"),
                 n == 1 ? String(localized: "1 commit to push.") : String(localized: "\(n) commits to push."))
        case .toPull(let n):
            pill(.warning, String(localized: "To pull"),
                 n == 1 ? String(localized: "1 commit to pull.") : String(localized: "\(n) commits to pull."))
        case .diverged(let ahead, let behind):
            pill(.warning, String(localized: "Diverged"),
                 String(localized: "Pull before you push: \(behind) to pull, \(ahead) to push."))
        case .conflict(let n):
            pill(.failure, String(localized: "Conflict"),
                 n == 1 ? String(localized: "Merge conflict in 1 file.") : String(localized: "Merge conflict in \(n) files."))
        case .local:
            VStack(alignment: .leading, spacing: Space.s) {
                pill(.neutral, String(localized: "Local"), String(localized: "This branch isn't on a remote yet."))
                Button(String(localized: "Publish Branch")) { Task { await git.publish() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(git.isBusy)
            }
        }
    }

    private func pill(_ state: PillState, _ label: String, _ sentence: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            StatusPill(state, label)
            Text(sentence).bodyText().foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func isDiverged(_ status: GitStatus) -> Bool {
        if case .diverged = status.state { true } else { false }
    }

    // MARK: Pull request

    private func pullRequest(_ pr: PullRequest) -> some View {
        Button { if let url = pr.url { NSWorkspace.shared.open(url) } } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "arrow.triangle.pull").foregroundStyle(Palette.textSecondary)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(String(localized: "PR #\(pr.number) · \(stateWord(pr.state))")).emphasisText()
                        .foregroundStyle(Palette.textPrimary)
                    if let review = pr.review {
                        Text(reviewWords(review)).captionText().foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                switch pr.checks {
                case .passing: StatusPill(.success, String(localized: "Passing"))
                case .failing: StatusPill(.failure, String(localized: "Failing"))
                case .running: StatusPill(.running, String(localized: "Running"))
                case nil: EmptyView()
                }
            }
            .padding(Space.s)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Open the pull request"))
    }

    private func stateWord(_ state: PullRequest.State) -> String {
        switch state {
        case .open: String(localized: "open")
        case .draft: String(localized: "draft")
        case .merged: String(localized: "merged")
        case .closed: String(localized: "closed")
        }
    }

    private func reviewWords(_ review: PullRequest.Review) -> String {
        switch review {
        case .required: String(localized: "Review requested")
        case .approved: String(localized: "Approved")
        case .changesRequested: String(localized: "Changes requested")
        }
    }

    // MARK: Problem, commit, merge

    private func problemCallout(_ problem: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text(problem)
                .font(Typography.mono)
                .foregroundStyle(Palette.failure)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { git.clearProblem() } label: {
                Image(systemName: "xmark").imageScale(.small).foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss"))
        }
        .padding(Space.s)
        .background(Palette.failureTint, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    private func commitBox(_ status: GitStatus) -> some View {
        let canCommit = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !status.files.isEmpty
        // With no upstream, the same button publishes the branch.
        let canSync = status.ahead > 0 || status.behind > 0 || status.upstream == nil
        return VStack(alignment: .leading, spacing: Space.s) {
            TextField(String(localized: "Message (⌘↩ to commit)"), text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .bodyText()
                .lineLimit(1...5)
                .padding(Space.s)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            HStack(spacing: Space.s) {
                Button(String(localized: "Commit")) {
                    Task { if await git.commit(message) { message = "" } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canCommit || git.isBusy)
                Button {
                    Task { await git.sync() }
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: status.upstream == nil ? "icloud.and.arrow.up" : "arrow.triangle.2.circlepath")
                        Text(status.upstream == nil ? String(localized: "Publish Branch") : String(localized: "Sync Changes"))
                        if status.behind > 0 { Text(verbatim: "↓\(status.behind)") }
                        if status.ahead > 0 { Text(verbatim: "↑\(status.ahead)") }
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(!canSync || git.isBusy)
            }
        }
    }

    private var mergeCallout: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(String(localized: "Your branch and the remote both have new commits. They need merging before you can push."))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Ask the agent to merge")) { workspace.askToMerge() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Space.s)
        .background(Palette.warningTint, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    // MARK: Files

    @ViewBuilder
    private func files(_ status: GitStatus) -> some View {
        if !status.files.isEmpty {
            LazyVStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Changed files")).captionText().foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, Space.xs)
                ForEach(status.files) { file in
                    FileRow(file: file, git: git, open: { workspace.showDiff(file, in: project) },
                            discard: { discarding = file })
                }
            }
        }
    }

    private struct FileRow: View {
        let file: GitFile
        let git: ProjectGit
        let open: () -> Void
        let discard: () -> Void
        @State private var hovering = false

        var body: some View {
            let name = (file.path as NSString).lastPathComponent
            let folder = (file.path as NSString).deletingLastPathComponent
            HStack(spacing: Space.s) {
                Image(systemName: FileIcon.symbol(for: name, isFolder: false))
                    .foregroundStyle(FileIcon.tint(for: name, isFolder: false))
                    .frame(width: Space.l)
                Text(name).bodyText().foregroundStyle(Palette.textPrimary).lineLimit(1)
                    .strikethrough(file.letter == "D")
                    .layoutPriority(1)
                Text(folder).captionText().foregroundStyle(Palette.textTertiary).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                if hovering {
                    IconButton(file.isStaged ? "minus" : "plus",
                               help: file.isStaged ? String(localized: "Unstage") : String(localized: "Stage")) {
                        Task { if file.isStaged { await git.unstage(file) } else { await git.stage(file) } }
                    }
                    IconButton("arrow.uturn.backward", help: String(localized: "Discard Changes"), action: discard)
                }
                Text(String(file.letter))
                    .font(Typography.mono)
                    .foregroundStyle(gitColour(file.letter))
                    .frame(width: Space.m)
            }
            .padding(.horizontal, Space.xs)
            .frame(height: Metrics.row)
            .background(hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .onHover { hovering = $0 }
            .help(file.originalPath.map { String(localized: "Renamed from \($0)") } ?? file.path)
        }
    }
}
