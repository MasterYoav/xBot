import SwiftUI
import XBotCore

/// The right-hand column for the project in view: its files, and its git changes. The header's
/// second tab is the change totals themselves, "+372 −33".
struct InspectorView: View {
    let workspace: Workspace
    let project: Project
    @AppStorage("inspectorTab") private var tab = Tab.changes

    enum Tab: String { case explorer, changes }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let git = workspace.git(for: project) {
                Group {
                    switch tab {
                    case .explorer: ExplorerPanel(workspace: workspace, project: project, git: git)
                    case .changes: ChangesPanel(workspace: workspace, project: project, git: git)
                    }
                }
                .task(id: project.id) {
                    await git.refresh()
                    git.startWatching()
                    // A quiet fetch every five minutes while the column is open, so "to pull" is true.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(300))
                        guard !Task.isCancelled else { break }
                        await git.fetch()
                    }
                    // Another project took this one's place: its watcher stops with it.
                    git.stopWatching()
                }
                .onDisappear { git.stopWatching() }
            } else {
                noGit
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            segment(.explorer) { Text(String(localized: "Explorer")) }
            segment(.changes) {
                let totals = workspace.git(for: project)?.totals ?? DiffTotals()
                HStack(spacing: Space.xs) {
                    Text(verbatim: "+\(totals.added)").foregroundStyle(Palette.success)
                    Text(verbatim: "−\(totals.removed)").foregroundStyle(Palette.failure)
                }
                .font(Typography.mono)
            }
            Spacer()
        }
        .padding(.horizontal, Space.s)
        .frame(height: Metrics.titleBar)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private func segment<Label: View>(_ value: Tab, @ViewBuilder label: () -> Label) -> some View {
        Button { tab = value } label: {
            label()
                .font(Typography.chip)
                .foregroundStyle(tab == value ? Palette.textPrimary : Palette.textSecondary)
                .padding(.horizontal, Space.s)
                .frame(height: Metrics.chipHeight - Space.xs)
                .background(tab == value ? Palette.hover : .clear,
                            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var noGit: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "arrow.triangle.branch").font(Typography.hero).foregroundStyle(Palette.textTertiary)
            Text(String(localized: "Git isn't installed on this Mac.")).bodyText().foregroundStyle(Palette.textSecondary)
            Button(String(localized: "Install Command Line Tools")) {
                // Apple's own installer dialog.
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/xcode-select")
                process.arguments = ["--install"]
                try? process.run()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.l)
    }
}

/// M amber, A and U green, D and C red.
func gitColour(_ letter: Character?) -> Color {
    switch letter {
    case "M", "R": Palette.warning
    case "A", "U": Palette.success
    case "D", "C": Palette.failure
    default: Palette.textPrimary
    }
}
