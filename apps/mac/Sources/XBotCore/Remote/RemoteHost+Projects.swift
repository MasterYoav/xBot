import Foundation
import XBotRemote

/// Projects from a phone: the Explorer, files, Changes, and adding or removing a project. Each
/// request is answered once, with data or with a refusal. Paths are relative to the project and
/// are refused if they'd lead outside it.
extension RemoteHost {
    func handleProject(_ message: ClientMessage, link: any RemoteLink) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (request, out) = await self.answerProject(message)
            guard let request else { return }
            link.send([out ?? .reply(requestID: request, ok: false, reason: String(localized: "The Mac couldn't do that right now."), chatID: nil)])
        }
    }

    private func refuse(_ request: UUID, _ reason: String) -> HostMessage {
        .reply(requestID: request, ok: false, reason: reason, chatID: nil)
    }

    private func ok(_ request: UUID) -> HostMessage { .reply(requestID: request, ok: true, reason: nil, chatID: nil) }

    private var projectGone: String { String(localized: "That project isn't on the Mac any more.") }
    private var outside: String { String(localized: "That isn't in the project.") }

    private func answerProject(_ message: ClientMessage) async -> (UUID?, HostMessage?) {
        switch message {
        case .listFolder(let request, let projectID, let path):
            guard let project = project(projectID) else { return (request, refuse(request, projectGone)) }
            guard let folder = Self.inside(project, path), Self.isFolder(folder) else { return (request, refuse(request, outside)) }
            return (request, .folder(requestID: request, entries: await entries(in: folder, of: project)))

        case .readFile(let request, let projectID, let path):
            guard let project = project(projectID) else { return (request, refuse(request, projectGone)) }
            guard let url = Self.inside(project, path), !path.isEmpty else { return (request, refuse(request, outside)) }
            guard let file = Self.read(url, path: path) else { return (request, refuse(request, String(localized: "That file can't be opened."))) }
            return (request, .file(requestID: request, file: file))

        case .gitStatus(let request, let projectID):
            guard let project = project(projectID) else { return (request, refuse(request, projectGone)) }
            guard let git = workspace.git(for: project) else { return (request, refuse(request, String(localized: "Git isn't installed on the Mac."))) }
            await git.refresh()
            return (request, .git(requestID: request, status: Self.remote(git)))

        case .gitDiff(let request, let projectID, let path):
            guard let project = project(projectID), let git = workspace.git(for: project) else { return (request, refuse(request, projectGone)) }
            if git.status == nil { await git.refresh(pullRequest: false) }
            guard let file = git.status?.files.first(where: { $0.path == path }) else {
                return (request, refuse(request, String(localized: "That file has no changes any more.")))
            }
            let lines = await git.diff(file).prefix(5000).map(Self.remote)
            return (request, .diff(requestID: request, lines: Array(lines)))

        case .gitAction(let request, let projectID, let action):
            guard let project = project(projectID), let git = workspace.git(for: project) else { return (request, refuse(request, projectGone)) }
            if git.status == nil { await git.refresh(pullRequest: false) }
            func file(_ path: String) -> GitFile? { git.status?.files.first { $0.path == path } }
            switch action {
            case .stage(let path):
                guard let f = file(path) else { return (request, refuse(request, String(localized: "That file has no changes any more."))) }
                await git.stage(f)
            case .unstage(let path):
                guard let f = file(path) else { return (request, refuse(request, String(localized: "That file has no changes any more."))) }
                await git.unstage(f)
            case .discard(let path):
                guard let f = file(path) else { return (request, refuse(request, String(localized: "That file has no changes any more."))) }
                await git.discard(f)
            case .commit(let text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return (request, refuse(request, String(localized: "A commit needs a message.")))
                }
                guard await git.commit(text) else {
                    return (request, refuse(request, git.problem ?? String(localized: "Nothing to commit.")))
                }
            case .sync: await git.sync()
            case .publish: await git.publish()
            case .fetch: await git.fetch()
            }
            await git.refresh()
            return (request, .git(requestID: request, status: Self.remote(git)))

        case .fileAction(let request, let projectID, let action):
            guard let project = project(projectID) else { return (request, refuse(request, projectGone)) }
            return (request, fileAction(action, in: project, request: request))

        case .browseMac(let request, let path):
            let folder = path.map { URL(filePath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
            guard Self.isFolder(folder) else { return (request, refuse(request, String(localized: "That folder isn't on the Mac."))) }
            let projectPaths = Set(workspace.projects.map(\.path))
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                                     options: [.skipsHiddenFiles])) ?? []
            let folders: [RemoteFolder] = urls.filter { (url: URL) -> Bool in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return values?.isDirectory == true && values?.isPackage != true
            }
            .map { (url: URL) -> RemoteFolder in
                let full = url.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
                return RemoteFolder(name: url.lastPathComponent, path: full, isProject: projectPaths.contains(full))
            }
            .sorted { (a: RemoteFolder, b: RemoteFolder) in a.name.localizedStandardCompare(b.name) == .orderedAscending }
            let shown = folder.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
            return (request, .macFolders(requestID: request, path: shown.isEmpty ? "/" : shown, folders: folders))

        case .addProject(let request, let path):
            let url = URL(filePath: path)
            guard Self.isFolder(url) else { return (request, refuse(request, String(localized: "That folder isn't on the Mac."))) }
            _ = workspace.addProject(at: url)
            return (request, ok(request))

        case .removeProject(let request, let projectID):
            guard project(projectID) != nil else { return (request, refuse(request, projectGone)) }
            workspace.removeProject(projectID)
            return (request, ok(request))

        case .listNotes(let request, let projectID):
            guard let project = project(projectID) else { return (request, refuse(request, projectGone)) }
            return (request, notesAnswer(request, project, saved: nil))

        case .saveNote(let request, let projectID, let name, let text):
            guard let project = project(projectID) else { return (request, refuse(request, projectGone)) }
            let folder = workspace.notes(for: project).notesFolder
            var current: URL?
            if let name {
                guard let url = Self.note(name, in: folder) else { return (request, refuse(request, String(localized: "That isn't a note."))) }
                current = url
            }
            do {
                let url = try ProjectNotes.write(text, to: current, in: folder)
                workspace.notes(for: project).reload()
                return (request, notesAnswer(request, project, saved: url.lastPathComponent))
            } catch {
                return (request, refuse(request, error.localizedDescription))
            }

        case .deleteNote(let request, let projectID, let name):
            guard let project = project(projectID) else { return (request, refuse(request, projectGone)) }
            guard let url = Self.note(name, in: workspace.notes(for: project).notesFolder),
                  FileManager.default.fileExists(atPath: url.path) else { return (request, refuse(request, String(localized: "That note isn't there any more."))) }
            var trashed: NSURL?
            do { try FileManager.default.trashItem(at: url, resultingItemURL: &trashed) } catch {
                return (request, refuse(request, error.localizedDescription))
            }
            deletedNote = (trashed as URL?).map { (projectID, url, $0) }
            workspace.notes(for: project).reload()
            return (request, notesAnswer(request, project, saved: nil))

        case .undoDeleteNote(let request, let projectID):
            guard let project = project(projectID) else { return (request, refuse(request, projectGone)) }
            guard let gone = deletedNote, gone.projectID == projectID, !FileManager.default.fileExists(atPath: gone.from.path) else {
                return (request, refuse(request, String(localized: "That note can't be brought back any more.")))
            }
            do { try FileManager.default.moveItem(at: gone.to, to: gone.from) } catch {
                return (request, refuse(request, error.localizedDescription))
            }
            deletedNote = nil
            workspace.notes(for: project).reload()
            return (request, notesAnswer(request, project, saved: nil))

        case .listAbilities, .setAbility, .removeAbility, .listPlugins, .installPlugin, .addMCP:
            return await answerAbilities(message)

        default:
            return answerAutomations(message)
        }
    }

    private func project(_ id: UUID) -> Project? { workspace.projects.first { $0.id == id } }

    private func notesAnswer(_ request: UUID, _ project: Project, saved: String?) -> HostMessage {
        let model = workspace.notes(for: project)
        model.reload()
        let notes = model.notes.map { RemoteNote(name: $0.url.lastPathComponent, title: $0.title, modified: $0.modified) }
        return .notes(requestID: request, notes: notes, saved: saved)
    }

    /// A note's file by name: a plain ".md" name directly in notes/, nothing else.
    static func note(_ name: String, in folder: URL) -> URL? {
        guard name.hasSuffix(".md"), !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return folder.appending(path: name)
    }

    // MARK: Files

    private func entries(in folder: URL, of project: Project) async -> [RemoteFileEntry] {
        let git = workspace.git(for: project)
        if let git, git.status == nil { await git.refresh(pullRequest: false) }
        let status = git?.status
        let deleted = status?.files.filter { $0.letter == "D" }.map(\.path) ?? []
        let letters = status.map(FileTree.letters) ?? [:]
        return FileTree.children(of: folder, root: project.url, deleted: deleted)
            .filter { $0.name != ".git" }
            .map { node in
                let path = FileTree.relativePath(node.url, in: project.url)
                return RemoteFileEntry(name: node.name, path: path, isFolder: node.isFolder, isDeleted: node.isDeleted,
                                       letter: letters[path].map(String.init))
            }
    }

    private func fileAction(_ action: RemoteFileAction, in project: Project, request: UUID) -> HostMessage {
        let fm = FileManager.default
        do {
            switch action {
            case .newFile(let folder), .newFolder(let folder):
                guard let parent = Self.inside(project, folder), Self.isFolder(parent) else { return refuse(request, outside) }
                let isFolder = if case .newFolder = action { true } else { false }
                let name = FileTree.newName(isFolder ? String(localized: "untitled folder") : String(localized: "untitled"), in: parent)
                let url = parent.appending(path: name)
                if isFolder {
                    try fm.createDirectory(at: url, withIntermediateDirectories: false)
                } else if !fm.createFile(atPath: url.path, contents: Data()) {
                    return refuse(request, String(localized: "The file couldn't be made."))
                }
            case .rename(let path, let name):
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                    return refuse(request, String(localized: "That name can't be used."))
                }
                guard !path.isEmpty, let url = Self.inside(project, path), fm.fileExists(atPath: url.path) else { return refuse(request, outside) }
                let target = url.deletingLastPathComponent().appending(path: name)
                guard !fm.fileExists(atPath: target.path) else { return refuse(request, String(localized: "Something there already has that name.")) }
                try fm.moveItem(at: url, to: target)
            case .trash(let path):
                guard !path.isEmpty, let url = Self.inside(project, path), fm.fileExists(atPath: url.path) else { return refuse(request, outside) }
                try fm.trashItem(at: url, resultingItemURL: nil)
            }
        } catch {
            return refuse(request, error.localizedDescription)
        }
        workspace.git(for: project).map { git in Task { await git.refresh(pullRequest: false) } }
        return ok(request)
    }

    /// The path's URL if it stays within the project (symlinks resolved), else nil.
    static func inside(_ project: Project, _ path: String) -> URL? {
        let root = project.url.standardizedFileURL.resolvingSymlinksInPath()
        let url = path.isEmpty ? project.url : project.url.appending(path: path)
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let base = root.path(percentEncoded: false).trimmingSuffix("/")
        let target = resolved.path(percentEncoded: false).trimmingSuffix("/")
        guard target == base || target.hasPrefix(base + "/") else { return nil }
        return url.standardizedFileURL
    }

    static func isFolder(_ url: URL) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && folder.boolValue
    }

    /// Text if it reads as UTF-8 without NUL bytes, cut at `RemoteFile.limit`; nil text for binary.
    static func read(_ url: URL, path: String) -> RemoteFile? {
        guard !isFolder(url), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let data = (try? handle.read(upToCount: RemoteFile.limit)) ?? Data()
        let truncated = size > data.count
        let binary = data.prefix(8192).contains(0) || (String(data: data, encoding: .utf8) == nil && !truncated)
        if binary { return RemoteFile(path: path, text: nil, size: size, truncated: false) }
        // A cut can split a character: decode leniently.
        return RemoteFile(path: path, text: String(decoding: data, as: UTF8.self), size: size, truncated: truncated)
    }

    // MARK: Git

    static func remote(_ git: ProjectGit) -> RemoteGit {
        let status = git.status
        return RemoteGit(
            isRepository: git.isRepository, branch: status?.branch, upstream: status?.upstream,
            ahead: status?.ahead ?? 0, behind: status?.behind ?? 0,
            files: (status?.files ?? []).map {
                RemoteGitFile(path: $0.path, originalPath: $0.originalPath, letter: String($0.letter), isStaged: $0.isStaged,
                              isConflicted: $0.isConflicted)
            },
            added: git.totals.added, removed: git.totals.removed, needsMerge: git.needsMerge,
            pullRequest: git.pullRequest.map(remote), problem: git.problem)
    }

    static func remote(_ pr: PullRequest) -> RemotePullRequest {
        let state = switch pr.state { case .open: "open"; case .draft: "draft"; case .merged: "merged"; case .closed: "closed" }
        let checks: String? = switch pr.checks { case .passing: "passing"; case .failing: "failing"; case .running: "running"; case nil: nil }
        let review: String? = switch pr.review {
        case .approved: "approved"; case .changesRequested: "changesRequested"; case .required: "reviewRequired"; case nil: nil
        }
        return RemotePullRequest(number: pr.number, title: "", state: state, url: pr.url?.absoluteString ?? "", checks: checks, review: review)
    }

    static func remote(_ line: DiffLine) -> RemoteDiffLine {
        let kind = switch line.kind { case .hunk: "hunk"; case .context: "context"; case .added: "added"; case .removed: "removed" }
        return RemoteDiffLine(id: line.id, kind: kind, old: line.old, new: line.new, text: line.text)
    }
}
