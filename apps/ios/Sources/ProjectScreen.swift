import SwiftUI
import XBotRemote

/// A project on the Mac: its files and its changes, like the Mac's inspector.
struct ProjectScreen: View {
    let client: RemoteClient
    let projectID: UUID
    let startChat: (_ projectID: UUID, _ text: String) -> Void
    @State private var tab = Tab.files
    @State private var removing = false
    @Environment(\.dismiss) private var dismiss

    enum Tab: Hashable { case files, changes }

    private var project: RemoteProject? { client.project(projectID) }

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .files: FolderView(client: client, projectID: projectID, path: "", startChat: startChat)
                case .changes: ChangesView(client: client, projectID: projectID, startChat: startChat)
                }
            }
            .navigationTitle(project?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker(String(localized: "Show"), selection: $tab) {
                    Text(String(localized: "Files")).tag(Tab.files)
                    Text(String(localized: "Changes")).tag(Tab.changes)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { startChat(projectID, "") } label: { Label(String(localized: "New chat here"), systemImage: "square.and.pencil") }
                        NavigationLink { TerminalScreen(client: client, projectID: projectID) } label: {
                            Label(String(localized: "Terminal here"), systemImage: "terminal")
                        }
                        if let path = project?.path {
                            Button { UIPasteboard.general.string = path } label: { Label(String(localized: "Copy path on the Mac"), systemImage: "doc.on.doc") }
                        }
                        Divider()
                        Button(role: .destructive) { removing = true } label: { Label(String(localized: "Remove from xBot"), systemImage: "minus.circle") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel(String(localized: "Project actions"))
                }
            }
            .confirmationDialog(String(localized: "Remove “\(project?.name ?? "")” from xBot?"), isPresented: $removing, titleVisibility: .visible) {
                Button(String(localized: "Remove"), role: .destructive) {
                    Task { if await client.act({ .removeProject(requestID: $0, projectID: projectID) }) { dismiss() } }
                }
            } message: {
                Text(String(localized: "Its chats are removed too. The folder and its files stay on the Mac."))
            }
        }
    }
}

// MARK: Files

struct FolderView: View {
    let client: RemoteClient
    let projectID: UUID
    let path: String
    let startChat: (UUID, String) -> Void
    @State private var entries: [RemoteFileEntry]?
    @State private var renaming: RemoteFileEntry?
    @State private var newName = ""
    @State private var trashing: RemoteFileEntry?

    var body: some View {
        List {
            ForEach(entries ?? []) { entry in
                NavigationLink {
                    if entry.isFolder {
                        FolderView(client: client, projectID: projectID, path: entry.path, startChat: startChat)
                            .navigationTitle(entry.name)
                    } else {
                        FileScreen(client: client, projectID: projectID, entry: entry, startChat: startChat)
                    }
                } label: {
                    FileRow(entry: entry)
                }
                .disabled(entry.isDeleted)
                .swipeActions(edge: .trailing) {
                    if !entry.isDeleted {
                        Button(role: .destructive) { trashing = entry } label: { Label(String(localized: "Trash"), systemImage: "trash") }
                        Button { newName = entry.name; renaming = entry } label: { Label(String(localized: "Rename"), systemImage: "pencil") }.tint(.indigo)
                    }
                }
                .contextMenu {
                    Button { startChat(projectID, "@\(entry.path) ") } label: { Label(String(localized: "Mention in a new chat"), systemImage: "at") }
                    Button { UIPasteboard.general.string = entry.path } label: { Label(String(localized: "Copy path"), systemImage: "doc.on.doc") }
                    if !entry.isDeleted {
                        Button { newName = entry.name; renaming = entry } label: { Label(String(localized: "Rename"), systemImage: "pencil") }
                        Button(role: .destructive) { trashing = entry } label: { Label(String(localized: "Move to Trash"), systemImage: "trash") }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if entries == nil { ProgressView() }
            else if entries?.isEmpty == true { ContentUnavailableView(String(localized: "Empty folder"), systemImage: "folder") }
        }
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    Button { Task { await make(.newFile(folder: path)) } } label: { Label(String(localized: "New File"), systemImage: "doc.badge.plus") }
                    Button { Task { await make(.newFolder(folder: path)) } } label: { Label(String(localized: "New Folder"), systemImage: "folder.badge.plus") }
                } label: { Label(String(localized: "New"), systemImage: "plus") }
            }
        }
        .alert(String(localized: "Rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: "Name"), text: $newName)
            Button(String(localized: "Cancel"), role: .cancel) { renaming = nil }
            Button(String(localized: "Rename")) {
                if let entry = renaming { let name = newName; Task { await make(.rename(path: entry.path, to: name)) } }
                renaming = nil
            }
        }
        .confirmationDialog(String(localized: "Move “\(trashing?.name ?? "")” to the Trash on the Mac?"),
                            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }), titleVisibility: .visible) {
            Button(String(localized: "Move to Trash"), role: .destructive) {
                if let entry = trashing { Task { await make(.trash(path: entry.path)) } }
            }
        }
    }

    private func load() async {
        if case .folder(_, let list) = await client.call({ .listFolder(requestID: $0, projectID: projectID, path: path) }) {
            entries = list
        } else if entries == nil {
            entries = []
        }
    }

    private func make(_ action: RemoteFileAction) async {
        if await client.act({ .fileAction(requestID: $0, projectID: projectID, action: action) }) { await load() }
    }
}

struct FileRow: View {
    let entry: RemoteFileEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isFolder ? "folder.fill" : FileKind.symbol(entry.name))
                .foregroundStyle(entry.isFolder ? Color.accentColor : .secondary)
                .frame(width: 22)
            Text(entry.name)
                .strikethrough(entry.isDeleted)
                .foregroundStyle(entry.isDeleted ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let letter = entry.letter { GitLetter(letter: letter) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct GitLetter: View {
    let letter: String
    var body: some View {
        Text(letter).font(.caption.monospaced().bold()).foregroundStyle(color)
            .accessibilityLabel(GitLetter.words(letter))
    }

    var color: Color {
        switch letter {
        case "M", "R": .orange
        case "A", "U": .green
        case "D": .red
        case "C": .purple
        default: .secondary
        }
    }

    static func words(_ letter: String) -> String {
        switch letter {
        case "M": String(localized: "modified")
        case "A": String(localized: "added")
        case "U": String(localized: "new")
        case "D": String(localized: "deleted")
        case "R": String(localized: "renamed")
        case "C": String(localized: "conflict")
        default: letter
        }
    }
}

enum FileKind {
    static func symbol(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift", "py", "js", "ts", "tsx", "jsx", "rb", "go", "rs", "c", "h", "m", "cpp", "java", "kt", "sh": "chevron.left.forwardslash.chevron.right"
        case "md", "txt", "rtf": "doc.text"
        case "json", "yml", "yaml", "toml", "plist", "xml": "curlybraces"
        case "png", "jpg", "jpeg", "gif", "heic", "svg", "webp", "icns": "photo"
        case "pdf": "doc.richtext"
        case "zip", "gz", "tar": "archivebox"
        default: "doc"
        }
    }
}

/// A file's text, with line numbers.
struct FileScreen: View {
    let client: RemoteClient
    let projectID: UUID
    let entry: RemoteFileEntry
    let startChat: (UUID, String) -> Void
    @State private var file: RemoteFile?
    @State private var failed = false
    @State private var wraps = false

    var body: some View {
        Group {
            if let file {
                if let text = file.text {
                    CodeText(text: text, wraps: wraps)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            if file.truncated {
                                Label(String(localized: "Showing the first \(RemoteFile.limit / 1024) KB of \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))."),
                                      systemImage: "scissors")
                                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(8).background(.bar)
                            }
                        }
                } else {
                    ContentUnavailableView(String(localized: "Not a text file"), systemImage: "doc",
                                           description: Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)))
                }
            } else if failed {
                ContentUnavailableView(String(localized: "Can't open it"), systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { startChat(projectID, "@\(entry.path) ") } label: { Label(String(localized: "Mention in a new chat"), systemImage: "at") }
                    Button { UIPasteboard.general.string = file?.text } label: { Label(String(localized: "Copy text"), systemImage: "doc.on.doc") }
                        .disabled(file?.text == nil)
                    Toggle(isOn: $wraps) { Label(String(localized: "Wrap lines"), systemImage: "text.word.spacing") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(String(localized: "File actions"))
            }
        }
        .task {
            if case .file(_, let f) = await client.call({ .readFile(requestID: $0, projectID: projectID, path: entry.path) }) { file = f } else { failed = true }
        }
    }
}

/// Monospaced text with line numbers; scrolls sideways unless it wraps.
struct CodeText: View {
    let text: String
    let wraps: Bool

    private var lines: [Substring] {
        var all = text.split(separator: "\n", omittingEmptySubsequences: false)
        if all.last == "" { all.removeLast() }
        return all
    }

    var body: some View {
        let lines = lines
        let width = CGFloat(String(lines.count).count) * 8 + 8
        ScrollView(wraps ? .vertical : [.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)").foregroundStyle(.tertiary).frame(width: width, alignment: .trailing)
                        Text(line.isEmpty ? " " : String(line))
                            .fixedSize(horizontal: !wraps, vertical: true)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.vertical, 1)
                }
            }
            .padding(12)
        }
    }
}

// MARK: Changes

struct ChangesView: View {
    let client: RemoteClient
    let projectID: UUID
    let startChat: (UUID, String) -> Void
    @State private var git: RemoteGit?
    @State private var message = ""
    @State private var busy = false
    @State private var discarding: RemoteGitFile?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            if let git {
                if !git.isRepository {
                    ContentUnavailableView(String(localized: "No git"), systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text(String(localized: "This folder isn't a git repository.")))
                } else {
                    branchSection(git)
                    if !git.files.isEmpty { commitSection(git) }
                    filesSection(git)
                }
            }
        }
        .overlay { if git == nil { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
        .disabled(busy)
        .confirmationDialog(String(localized: "Discard the changes to “\(discarding.map { ($0.path as NSString).lastPathComponent } ?? "")”?"),
                            isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }), titleVisibility: .visible) {
            Button(String(localized: "Discard Changes"), role: .destructive) {
                if let file = discarding { Task { await run(.discard(path: file.path)) } }
            }
        } message: { Text(String(localized: "This can't be undone.")) }
    }

    @ViewBuilder private func branchSection(_ git: RemoteGit) -> some View {
        Section {
            HStack {
                Label(git.branch ?? String(localized: "No branch"), systemImage: "arrow.triangle.branch").font(.headline)
                Spacer()
                if git.added + git.removed > 0 {
                    Text("+\(git.added)").foregroundStyle(.green).font(.footnote.monospaced())
                    Text("−\(git.removed)").foregroundStyle(.red).font(.footnote.monospaced())
                }
            }
            if let line = syncLine(git) { Text(line).font(.footnote).foregroundStyle(.secondary) }
            if git.needsMerge {
                Label(String(localized: "Your branch and the remote both have new commits. They need merging before you can push."),
                      systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                Button { startChat(projectID, String(localized: "Pull the latest changes from the remote and merge them with mine. Resolve any conflicts, run the tests, then tell me what you did.")) } label: {
                    Label(String(localized: "Ask the agent to merge"), systemImage: "sparkles")
                }
            }
            if let problem = git.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            if let pr = git.pullRequest { prRow(pr) }
            HStack {
                if git.upstream == nil, git.branch != nil {
                    Button { Task { await run(.publish) } } label: { Label(String(localized: "Publish Branch"), systemImage: "icloud.and.arrow.up") }
                } else {
                    Button { Task { await run(.sync) } } label: {
                        Label(String(localized: "Sync Changes"), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Spacer()
                Button { Task { await run(.fetch) } } label: { Label(String(localized: "Fetch"), systemImage: "arrow.down.circle") }
            }
            .buttonStyle(.borderless)
            .overlay { if busy { ProgressView() } }
        }
    }

    private func prRow(_ pr: RemotePullRequest) -> some View {
        Button {
            if let url = URL(string: pr.url) { openURL(url) }
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.pull").foregroundStyle(pr.state == "merged" ? .purple : pr.state == "closed" ? .red : .green)
                Text(String(localized: "PR #\(pr.number) · \(prState(pr.state))"))
                Spacer()
                if let checks = pr.checks {
                    Label(checksWord(checks), systemImage: checks == "passing" ? "checkmark.circle.fill" : checks == "failing" ? "xmark.circle.fill" : "clock")
                        .font(.footnote)
                        .foregroundStyle(checks == "passing" ? .green : checks == "failing" ? .red : .orange)
                }
            }
        }
    }

    @ViewBuilder private func commitSection(_ git: RemoteGit) -> some View {
        Section {
            TextField(String(localized: "Commit message"), text: $message, axis: .vertical).lineLimit(1...4)
            Button {
                let text = message
                Task { if await run(.commit(message: text)) { message = "" } }
            } label: {
                Label(git.files.contains(where: \.isStaged) ? String(localized: "Commit staged") : String(localized: "Commit all"),
                      systemImage: "checkmark.circle")
            }
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder private func filesSection(_ git: RemoteGit) -> some View {
        Section(git.files.isEmpty ? String(localized: "Nothing to commit") : String(localized: "\(git.files.count) changed")) {
            ForEach(git.files) { file in
                NavigationLink {
                    DiffScreen(client: client, projectID: projectID, file: file)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: file.isStaged ? "checkmark.square.fill" : "square")
                            .foregroundStyle(file.isStaged ? Color.accentColor : .secondary)
                            .accessibilityLabel(file.isStaged ? String(localized: "staged") : String(localized: "not staged"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text((file.path as NSString).lastPathComponent).lineLimit(1)
                            let folder = (file.path as NSString).deletingLastPathComponent
                            if !folder.isEmpty { Text(folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
                        }
                        Spacer()
                        GitLetter(letter: file.letter)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { Task { await run(file.isStaged ? .unstage(path: file.path) : .stage(path: file.path)) } } label: {
                        Label(file.isStaged ? String(localized: "Unstage") : String(localized: "Stage"), systemImage: file.isStaged ? "minus" : "plus")
                    }
                    .tint(file.isStaged ? .gray : .green)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { discarding = file } label: { Label(String(localized: "Discard"), systemImage: "arrow.uturn.backward") }
                }
                .contextMenu {
                    Button { Task { await run(file.isStaged ? .unstage(path: file.path) : .stage(path: file.path)) } } label: {
                        Label(file.isStaged ? String(localized: "Unstage") : String(localized: "Stage"), systemImage: file.isStaged ? "minus.circle" : "plus.circle")
                    }
                    Button { startChat(projectID, "@\(file.path) ") } label: { Label(String(localized: "Mention in a new chat"), systemImage: "at") }
                    Button(role: .destructive) { discarding = file } label: { Label(String(localized: "Discard Changes"), systemImage: "arrow.uturn.backward") }
                }
            }
        }
    }

    private func syncLine(_ git: RemoteGit) -> String? {
        guard let upstream = git.upstream else { return git.branch == nil ? nil : String(localized: "This branch isn't on a remote yet.") }
        if git.ahead == 0 && git.behind == 0 { return String(localized: "Up to date with \(upstream).") }
        return String(localized: "\(git.behind) to pull, \(git.ahead) to push.")
    }

    private func prState(_ state: String) -> String {
        switch state {
        case "draft": String(localized: "draft")
        case "merged": String(localized: "merged")
        case "closed": String(localized: "closed")
        default: String(localized: "open")
        }
    }

    private func checksWord(_ checks: String) -> String {
        switch checks {
        case "passing": String(localized: "Passing")
        case "failing": String(localized: "Failing")
        default: String(localized: "Running")
        }
    }

    private func load() async {
        if case .git(_, let status) = await client.call({ .gitStatus(requestID: $0, projectID: projectID) }) { git = status }
    }

    @discardableResult
    private func run(_ action: RemoteGitAction) async -> Bool {
        busy = true
        defer { busy = false }
        if case .git(_, let status) = await client.call({ .gitAction(requestID: $0, projectID: projectID, action: action) }) {
            git = status
            return true
        }
        return false
    }
}

struct DiffScreen: View {
    let client: RemoteClient
    let projectID: UUID
    let file: RemoteGitFile
    @State private var lines: [RemoteDiffLine]?
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            // At least as wide as the screen, so each row's color reaches the edge.
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines ?? []) { line in
                    HStack(spacing: 8) {
                        Text(line.old.map(String.init) ?? "").frame(width: 34, alignment: .trailing)
                        Text(line.new.map(String.init) ?? "").frame(width: 34, alignment: .trailing)
                        Text(mark(line) + line.text).fixedSize()
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(line.kind == "hunk" ? Color.secondary : .primary)
                    .padding(.vertical, 1)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(line))
                }
            }
            .frame(minWidth: width, alignment: .leading)
            .padding(.vertical, 8)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay {
            if lines == nil { ProgressView() }
            else if lines?.isEmpty == true { ContentUnavailableView(String(localized: "No text changes"), systemImage: "doc") }
        }
        .navigationTitle((file.path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .diff(_, let found) = await client.call({ .gitDiff(requestID: $0, projectID: projectID, path: file.path) }) { lines = found } else { lines = [] }
        }
    }

    private func mark(_ line: RemoteDiffLine) -> String {
        switch line.kind { case "added": "+ "; case "removed": "− "; case "context": "  "; default: "" }
    }

    private func background(_ line: RemoteDiffLine) -> Color {
        switch line.kind {
        case "added": .green.opacity(0.14)
        case "removed": .red.opacity(0.14)
        case "hunk": Color(.secondarySystemBackground)
        default: .clear
        }
    }
}

// MARK: Adding a project

/// Pick a folder on the Mac to add as a project.
struct AddProjectSheet: View {
    let client: RemoteClient
    let added: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MacFolderList(client: client, path: nil, added: added)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } } }
        }
    }
}

private struct MacFolderList: View {
    let client: RemoteClient
    let path: String?
    let added: (UUID?) -> Void
    @State private var shown: String?
    @State private var folders: [RemoteFolder]?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(folders ?? []) { folder in
                NavigationLink {
                    MacFolderList(client: client, path: folder.path, added: added)
                } label: {
                    HStack {
                        Image(systemName: folder.isProject ? "folder.fill.badge.person.crop" : "folder").foregroundStyle(Color.accentColor)
                        Text(folder.name)
                        Spacer()
                        if folder.isProject { Text(String(localized: "Added")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .overlay {
            if folders == nil { ProgressView() }
            else if folders?.isEmpty == true { ContentUnavailableView(String(localized: "No folders inside"), systemImage: "folder") }
        }
        .navigationTitle(shown.map { ($0 as NSString).lastPathComponent } ?? String(localized: "Your Mac"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let shown {
                Button {
                    adding = true
                    Task {
                        if await client.act({ .addProject(requestID: $0, path: shown) }) {
                            try? await Task.sleep(for: .milliseconds(400))
                            added(client.projects.first { $0.path == shown }?.id)
                        }
                        adding = false
                    }
                } label: {
                    Text(String(localized: "Add “\((shown as NSString).lastPathComponent)” as a project"))
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(adding || path == nil)
                .padding()
                .background(.bar)
                .opacity(path == nil ? 0 : 1)
            }
        }
        .task {
            if case .macFolders(_, let here, let list) = await client.call({ .browseMac(requestID: $0, path: path) }) {
                shown = here
                folders = list
            } else {
                folders = []
            }
        }
    }
}
