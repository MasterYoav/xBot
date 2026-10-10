import SwiftUI
import XBotCore

/// Notes: a project's ideas and next release notes, as markdown files in its `notes/` folder.
struct NotesView: View {
    let workspace: Workspace
    let addProject: () -> Void

    var body: some View {
        if let project = workspace.notesProject {
            ProjectNotesView(workspace: workspace, project: project, notes: workspace.notes(for: project))
                .id(project.id)
        } else {
            VStack(spacing: Space.m) {
                Image(systemName: "note.text").font(Typography.hero).foregroundStyle(Palette.textTertiary)
                Text(String(localized: "Notes belong to a project.")).titleText()
                Text(String(localized: "Add a project folder and its notes live in it, in notes/, next to the code."))
                    .bodyText().foregroundStyle(Palette.textSecondary)
                Button(String(localized: "Add a project"), action: addProject).buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProjectNotesView: View {
    let workspace: Workspace
    let project: Project
    @Bindable var notes: ProjectNotes
    @State private var previewing = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: Metrics.notesListWidth)
            Rectangle().fill(Palette.hairline).frame(width: 1)
            editor
        }
        // An agent may have written to the folder; look when the page appears and every few seconds.
        .task(id: project.id) {
            while !Task.isCancelled {
                notes.reload()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        // Saved a moment after typing stops, and on leaving.
        .task(id: notes.text) {
            guard notes.dirty else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            save()
        }
        .onDisappear { if notes.dirty { save() } }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Menu {
                    ForEach(workspace.projects) { other in
                        Button(other.name) { workspace.showNotes(for: other.id) }
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "folder").foregroundStyle(Palette.textTertiary)
                        Text(project.name).emphasisText().foregroundStyle(Palette.textPrimary).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(Palette.textTertiary)
                    }
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                Spacer()
                IconButton("square.and.pencil", help: String(localized: "New note")) { newNote() }
            }
            .padding(.horizontal, Space.s)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(notes.notes) { note in
                        Button { notes.open(note.url) } label: {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(note.title).bodyText().foregroundStyle(Palette.textPrimary).lineLimit(1)
                                Text(note.modified, format: .relative(presentation: .named))
                                    .captionText().foregroundStyle(Palette.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.s)
                            .padding(.vertical, Space.s)
                            .background(notes.selected == note.url ? Palette.hover : .clear,
                                        in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                            Button(String(localized: "Delete"), role: .destructive) { delete(note.url) }
                        }
                    }
                }
                .padding(.horizontal, Space.xs)
            }
            Text(String(localized: "In \(project.name)/notes — part of the project, so agents can read them."))
                .captionText().foregroundStyle(Palette.textTertiary)
                .padding(Space.s)
        }
        .padding(.top, Space.m)
        .background(Palette.sidebar.opacity(0.5))
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if notes.selected == nil {
            VStack(spacing: Space.m) {
                Image(systemName: "note.text").font(Typography.hero).foregroundStyle(Palette.textTertiary)
                Text(String(localized: "Ideas, plans, the next release notes — in whatever shape they're in."))
                    .bodyText().foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                Button(String(localized: "New note")) { newNote() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: Space.s) {
                    Picker(String(localized: "Mode"), selection: $previewing) {
                        Text(String(localized: "Edit")).tag(false)
                        Text(String(localized: "Preview")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Text(notes.dirty ? String(localized: "Editing…") : String(localized: "Saved"))
                        .captionText().foregroundStyle(Palette.textTertiary)
                    if let url = notes.selected {
                        IconButton("trash", help: String(localized: "Delete note")) { delete(url) }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                if previewing {
                    ScrollView {
                        MarkdownText(text: notes.text)
                            .frame(maxWidth: Metrics.readingWidth, alignment: .leading)
                            .padding(Space.xl)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    TextEditor(text: $notes.text)
                        .readingText()
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)
                        .frame(maxWidth: Metrics.readingWidth)
                        .padding(.horizontal, Space.xl)
                        .padding(.bottom, Space.l)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(String(localized: "Note"))
                }
            }
        }
    }

    // MARK: Actions

    private func newNote() {
        do {
            try notes.create()
            previewing = false
            editorFocused = true
        } catch {
            workspace.toasts.show(String(localized: "Couldn't create a note: \(error.localizedDescription)"))
        }
    }

    private func save() {
        do { try notes.save() } catch {
            workspace.toasts.show(String(localized: "Couldn't save the note: \(error.localizedDescription)"))
        }
    }

    private func delete(_ url: URL) {
        do {
            let restore = try notes.delete(url)
            workspace.toasts.show(String(localized: "Note deleted"), systemImage: "trash",
                                  action: .init(title: String(localized: "Undo")) { try? restore() })
        } catch {
            workspace.toasts.show(String(localized: "Couldn't delete the note: \(error.localizedDescription)"))
        }
    }
}
