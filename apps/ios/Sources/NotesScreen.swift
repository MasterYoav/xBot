import SwiftUI
import XBotRemote

/// Notes: Markdown files in each project's notes/ folder on the Mac, like the Mac's Notes page.
struct NotesScreen: View {
    let client: RemoteClient
    @State private var projectID: UUID?
    @State private var notes: [RemoteNote]?
    @State private var lastDeleted: String?
    @State private var path: [NoteRoute] = []

    struct NoteRoute: Hashable { var projectID: UUID; var name: String? }

    private var project: RemoteProject? { projectID.flatMap(client.project) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(notes ?? []) { note in
                    NavigationLink(value: NoteRoute(projectID: projectID ?? UUID(), name: note.name)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.body.weight(.medium)).lineLimit(1)
                            Text(note.modified, format: .relative(presentation: .named)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { Task { await delete(note) } } label: { Label(String(localized: "Delete"), systemImage: "trash") }
                    }
                }
            }
            .overlay {
                if client.projects.isEmpty {
                    ContentUnavailableView(String(localized: "No projects"), systemImage: "folder",
                                           description: Text(String(localized: "Notes live in a project. Add one first.")))
                } else if notes == nil {
                    ProgressView()
                } else if notes?.isEmpty == true {
                    ContentUnavailableView {
                        Label(String(localized: "No notes yet"), systemImage: "note.text")
                    } description: {
                        Text(String(localized: "Notes are Markdown files in the project's notes folder. Your agents can read them too."))
                    } actions: {
                        Button(String(localized: "New note")) { newNote() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .refreshable { await load() }
            .closable()
            .navigationTitle(String(localized: "Notes"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Picker(String(localized: "Project"), selection: $projectID) {
                            ForEach(client.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(project?.name ?? String(localized: "Notes")).font(.headline)
                            Image(systemName: "chevron.down").font(.caption.bold())
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(String(localized: "Project: \(project?.name ?? "")"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: newNote) { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel(String(localized: "New note"))
                        .disabled(projectID == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let lastDeleted {
                    UndoBanner(text: String(localized: "Deleted “\(lastDeleted)”")) {
                        Task { await undo() }
                    } dismiss: { self.lastDeleted = nil }
                }
            }
            .animation(.snappy, value: lastDeleted)
            .navigationDestination(for: NoteRoute.self) { route in
                NoteEditor(client: client, projectID: route.projectID, name: route.name) { list in notes = list }
            }
        }
        .onAppear { if projectID == nil { projectID = client.projects.first?.id } }
        .task(id: projectID) { notes = nil; await load() }
    }

    private func newNote() {
        guard let projectID else { return }
        path.append(NoteRoute(projectID: projectID, name: nil))
    }

    private func load() async {
        guard let projectID else { return }
        if case .notes(_, let list, _) = await client.call({ .listNotes(requestID: $0, projectID: projectID) }) { notes = list }
        else if notes == nil { notes = [] }
    }

    private func delete(_ note: RemoteNote) async {
        guard let projectID else { return }
        if case .notes(_, let list, _) = await client.call({ .deleteNote(requestID: $0, projectID: projectID, name: note.name) }) {
            notes = list
            lastDeleted = note.title
        }
    }

    private func undo() async {
        guard let projectID else { return }
        lastDeleted = nil
        if case .notes(_, let list, _) = await client.call({ .undoDeleteNote(requestID: $0, projectID: projectID) }) { notes = list }
    }
}

/// One note. Saves a moment after typing stops, and on leaving; the file follows the first line.
struct NoteEditor: View {
    let client: RemoteClient
    let projectID: UUID
    @State var name: String?
    let saved: ([RemoteNote]) -> Void
    @State private var text = ""
    @State private var lastSaved = ""
    @State private var loaded = false
    @State private var saving = false
    @FocusState private var focused: Bool

    init(client: RemoteClient, projectID: UUID, name: String?, saved: @escaping ([RemoteNote]) -> Void) {
        self.client = client
        self.projectID = projectID
        _name = State(initialValue: name)
        self.saved = saved
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .focused($focused)
            .padding(.horizontal, 12)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("note-text")
            .overlay(alignment: .topLeading) {
                if loaded && text.isEmpty {
                    Text(String(localized: "Title on the first line…")).foregroundStyle(.tertiary)
                        .padding(.horizontal, 17).padding(.vertical, 8).allowsHitTesting(false)
                }
            }
            .overlay { if !loaded { ProgressView() } }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if saving { ProgressView() }
                    else if text != lastSaved { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary).accessibilityLabel(String(localized: "Not saved yet")) }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button(String(localized: "Done")) { focused = false; Task { await save() } } }
                }
            }
            .task {
                if let name, case .file(_, let file) = await client.call({ .readFile(requestID: $0, projectID: projectID, path: "notes/\(name)") }) {
                    text = file.text ?? ""
                    lastSaved = text
                }
                loaded = true
                if name == nil { focused = true }
            }
            .task(id: text) {
                guard loaded, text != lastSaved else { return }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                await save()
            }
            .onDisappear { Task { await save() } }
    }

    private var title: String {
        let first = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return first.map { String($0.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces) } ?? String(localized: "New note")
    }

    private func save() async {
        guard loaded, text != lastSaved, !saving else { return }
        // A new note isn't made until something is typed.
        if name == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        saving = true
        defer { saving = false }
        let snapshot = text
        if case .notes(_, let list, let file) = await client.call({ .saveNote(requestID: $0, projectID: projectID, name: name, text: snapshot) }) {
            name = file ?? name
            lastSaved = snapshot
            saved(list)
        }
    }
}
