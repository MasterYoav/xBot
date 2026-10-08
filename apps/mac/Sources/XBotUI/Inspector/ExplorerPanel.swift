import QuickLook
import SwiftUI
import XBotCore

/// The project's files: a tree that opens as you go, coloured by git, dimmed where git ignores.
/// Click previews; double-click opens; a file can be mentioned to the agent or dragged to it.
struct ExplorerPanel: View {
    let workspace: Workspace
    let project: Project
    let git: ProjectGit
    @State private var expanded: Set<URL> = []
    @State private var children: [URL: [FileNode]] = [:]
    @State private var ignored: Set<String> = []
    @State private var letters: [String: Character] = [:]
    @State private var selection: URL?
    @State private var preview: URL?
    @State private var renaming: URL?
    @State private var renameText = ""
    @State private var filter = ""
    @State private var filtering = false
    @FocusState private var renameFocused: Bool

    private var root: URL { project.url }

    var body: some View {
        VStack(spacing: 0) {
            header
            if filtering {
                TextField(String(localized: "Filter"), text: $filter)
                    .textFieldStyle(.plain)
                    .bodyText()
                    .padding(.horizontal, Space.s)
                    .frame(height: Metrics.row)
                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .padding(.horizontal, Space.s)
                    .padding(.bottom, Space.xs)
                    .onExitCommand { filter = ""; filtering = false }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.node.id) { row in
                        Row(node: row.node, depth: row.depth, panel: self)
                    }
                }
                .padding(.horizontal, Space.xs)
                .padding(.bottom, Space.s)
            }
            .scrollIndicators(.never)
        }
        .quickLookPreview($preview)
        .task(id: git.generation) { await reload() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.xxs) {
            MonoLabel(project.name)
            Spacer()
            IconButton("doc.badge.plus", help: String(localized: "New File")) { create(folder: false) }
            IconButton("folder.badge.plus", help: String(localized: "New Folder")) { create(folder: true) }
            IconButton("arrow.down.right.and.arrow.up.left", help: String(localized: "Collapse All")) { expanded = [] }
            IconButton("line.3.horizontal.decrease", help: String(localized: "Filter")) {
                filtering.toggle()
                if !filtering { filter = "" }
            }
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .padding(.vertical, Space.xs)
    }

    // MARK: Tree

    /// The visible rows: the root's children, and the children of every open folder beneath them.
    /// A filter shows matching names wherever they are among the folders already read.
    private var rows: [(node: FileNode, depth: Int)] {
        if !filter.isEmpty {
            return children.values.joined()
                .filter { $0.name.localizedCaseInsensitiveContains(filter) }
                .sorted { $0.url.path < $1.url.path }
                .map { ($0, 0) }
        }
        var result: [(FileNode, Int)] = []
        func walk(_ folder: URL, _ depth: Int) {
            for node in children[folder] ?? [] {
                result.append((node, depth))
                if node.isFolder, expanded.contains(node.url) { walk(node.url, depth + 1) }
            }
        }
        walk(root, 0)
        return result
    }

    private var deletedPaths: [String] { (git.status?.files ?? []).filter { $0.letter == "D" }.map(\.path) }

    /// Reads the root and every open folder again, with git's view of them.
    private func reload() async {
        letters = FileTree.letters(git.status ?? GitStatus())
        for folder in [root] + expanded.sorted(by: { $0.path < $1.path }) { await load(folder) }
    }

    private func load(_ folder: URL) async {
        let nodes = FileTree.children(of: folder, root: root, deleted: deletedPaths)
        children[folder] = nodes
        let paths = nodes.filter { !$0.isDeleted }.map { FileTree.relativePath($0.url, in: root) }
        ignored.formUnion(await git.ignored(paths))
    }

    func toggle(_ node: FileNode) {
        if expanded.contains(node.url) {
            expanded.remove(node.url)
        } else {
            expanded.insert(node.url)
            Task { await load(node.url) }
        }
    }

    // MARK: Actions

    func select(_ node: FileNode) {
        selection = node.url
        if node.isFolder { toggle(node) } else if !node.isDeleted { preview = node.url }
    }

    func open(_ node: FileNode) {
        guard !node.isDeleted else { return }
        NSWorkspace.shared.open(node.url)
    }

    func startRename(_ url: URL) {
        renameText = url.lastPathComponent
        renaming = url
        renameFocused = true
    }

    func finishRename(_ node: FileNode) {
        defer { renaming = nil }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != node.name, !name.contains("/") else { return }
        do {
            try FileManager.default.moveItem(at: node.url, to: node.url.deletingLastPathComponent().appending(path: name))
        } catch {
            workspace.toasts.show(error.localizedDescription, systemImage: "exclamationmark.triangle")
        }
        Task { await reload() }
    }

    func trash(_ node: FileNode) {
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            workspace.toasts.show(String(localized: "Moved \(node.name) to the Trash"), systemImage: "trash")
        } catch {
            workspace.toasts.show(error.localizedDescription, systemImage: "exclamationmark.triangle")
        }
        Task { await reload() }
    }

    /// A new file or folder in the selected folder (or the selected file's), named so it does not
    /// collide, then renamed in place.
    private func create(folder: Bool) {
        var parent = root
        if let selection {
            let isFolder = (try? selection.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            parent = isFolder ? selection : selection.deletingLastPathComponent()
        }
        let name = FileTree.newName(folder ? String(localized: "untitled folder") : String(localized: "untitled"), in: parent)
        let url = parent.appending(path: name)
        do {
            if folder {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } else {
                try Data().write(to: url, options: .withoutOverwriting)
            }
        } catch {
            workspace.toasts.show(error.localizedDescription, systemImage: "exclamationmark.triangle")
            return
        }
        if parent != root { expanded.insert(parent) }
        Task {
            await reload()
            selection = url
            startRename(url)
        }
    }

    // MARK: Row

    private struct Row: View {
        let node: FileNode
        let depth: Int
        let panel: ExplorerPanel
        @State private var hovering = false

        var body: some View {
            let relative = FileTree.relativePath(node.url, in: panel.root)
            let isIgnored = panel.ignored.contains(relative)
            let letter = panel.letters[relative]
            HStack(spacing: Space.xs) {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(Palette.textTertiary)
                    .rotationEffect(.degrees(panel.expanded.contains(node.url) ? 90 : 0))
                    .opacity(node.isFolder ? 1 : 0)
                    .frame(width: Space.m)
                    .motion(Motion.quick, value: panel.expanded.contains(node.url))
                Image(systemName: FileIcon.symbol(for: node.name, isFolder: node.isFolder))
                    .foregroundStyle(FileIcon.tint(for: node.name, isFolder: node.isFolder))
                    .frame(width: Space.l)
                if panel.renaming == node.url {
                    TextField("", text: panel.$renameText)
                        .textFieldStyle(.plain)
                        .bodyText()
                        .focused(panel.$renameFocused)
                        .onSubmit { panel.finishRename(node) }
                        .onExitCommand { panel.renaming = nil }
                } else {
                    Text(node.name)
                        .bodyText()
                        .italic(isIgnored)
                        .strikethrough(node.isDeleted)
                        .foregroundStyle(isIgnored ? Palette.textTertiary : (letter == nil ? Palette.textPrimary : gitColour(letter)))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let letter, !node.isFolder {
                    Text(String(letter)).font(Typography.mono).foregroundStyle(gitColour(letter))
                }
            }
            .padding(.leading, CGFloat(depth) * Space.l + Space.xs)
            .padding(.trailing, Space.s)
            .frame(height: Metrics.row)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(panel.selection == node.url ? Palette.hover : (hovering ? Palette.hover.opacity(0.6) : .clear))
            )
            .contentShape(Rectangle())
            .gesture(TapGesture(count: 2).onEnded { panel.open(node) }.exclusively(before: TapGesture().onEnded { panel.select(node) }))
            .onHover { hovering = $0 }
            .draggable(node.url)
            .contextMenu {
                Button(String(localized: "Mention in Chat")) { panel.workspace.mention(node.url) }
                Divider()
                Button(String(localized: "Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                Button(String(localized: "Copy Path")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.url.path(percentEncoded: false), forType: .string)
                }
                Divider()
                Button(String(localized: "Rename")) { panel.startRename(node.url) }.disabled(node.isDeleted)
                Button(String(localized: "Move to Trash")) { panel.trash(node) }.disabled(node.isDeleted)
            }
        }
    }
}
