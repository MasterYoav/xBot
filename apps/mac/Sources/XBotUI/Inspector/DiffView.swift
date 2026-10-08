import SwiftUI
import XBotCore

/// A changed file, read-only: a unified diff with both sides' line numbers, additions and removals tinted.
struct DiffView: View {
    let workspace: Workspace
    let git: ProjectGit
    let file: GitFile
    @State private var lines: [DiffLine]?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Image(systemName: FileIcon.symbol(for: (file.path as NSString).lastPathComponent, isFolder: false))
                    .foregroundStyle(Palette.textSecondary)
                Text(file.path).font(Typography.mono).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Text(String(file.letter)).font(Typography.mono).foregroundStyle(gitColour(file.letter))
                Spacer()
                IconButton("xmark", help: String(localized: "Close (Esc)")) { workspace.page = .main }
            }
            .padding(.horizontal, Space.m)
            .frame(height: Metrics.topBar)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }

            if let lines {
                if lines.isEmpty {
                    Text(String(localized: "No changes to show.")).bodyText().foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        ScrollView([.vertical, .horizontal]) {
                            // At least the view's width, so every row's tint runs edge to edge.
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(lines) { row($0) }
                            }
                            .frame(minWidth: geometry.size.width, alignment: .leading)
                            .padding(.vertical, Space.s)
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.window)
        .task(id: file) { lines = await git.diff(file) }
        .onExitCommand { workspace.page = .main }
    }

    private func row(_ line: DiffLine) -> some View {
        HStack(spacing: Space.s) {
            number(line.old)
            number(line.new)
            Text(verbatim: marker(line.kind) + line.text)
                .font(Typography.mono)
                .foregroundStyle(line.kind == .hunk ? Palette.textTertiary : Palette.textPrimary)
                .fixedSize()
        }
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, minHeight: Metrics.row - Space.s, alignment: .leading)
        .background(tint(line.kind))
    }

    private func number(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(Typography.mono)
            .foregroundStyle(Palette.textTertiary)
            .frame(width: Space.xxl + Space.s, alignment: .trailing)
    }

    private func marker(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: "+ "
        case .removed: "− "
        case .context: "  "
        case .hunk: ""
        }
    }

    private func tint(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: Palette.successTint
        case .removed: Palette.failureTint
        case .hunk: Palette.inset
        case .context: .clear
        }
    }
}
