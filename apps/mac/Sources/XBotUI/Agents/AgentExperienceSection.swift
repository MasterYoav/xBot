import SwiftUI
import XBotCore

/// The agent editor's Experience: what this agent learnt in Agentic Mode (Harness2's cue → lesson),
/// to read, reword or forget. Changes apply at once, not on Save: forgetting has Undo instead.
struct AgentExperienceSection: View {
    let workspace: Workspace
    let agentID: UUID
    let name: String
    @State private var editingID: UUID?
    @State private var confirmingForgetAll = false

    var body: some View {
        let lessons = workspace.lessons(of: agentID)
        VStack(alignment: .leading, spacing: Space.s) {
            header(count: lessons.count)
            if lessons.isEmpty {
                empty
            } else {
                VStack(spacing: Space.xs) {
                    ForEach(lessons) { lesson in
                        if editingID == lesson.id {
                            LessonEditorRow(lesson: lesson, save: { edited in
                                workspace.editLesson(edited, of: agentID)
                                editingID = nil
                            }, cancel: { editingID = nil })
                        } else {
                            LessonRow(lesson: lesson, edit: { editingID = lesson.id }, forget: { forget(lesson) })
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            String(localized: "Forget everything \(name) has learnt?"), isPresented: $confirmingForgetAll
        ) {
            Button(String(localized: "Forget everything"), role: .destructive) { forgetAll() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "\(Self.count(lessons.count)) will go. \(name) starts learning again from its next task in Agentic Mode."))
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: "lightbulb").font(Typography.title).foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(String(localized: "Experience")).titleText().foregroundStyle(Palette.textPrimary)
                if count > 0 { MonoLabel(Self.count(count)) }
                Spacer(minLength: Space.s)
                if count > 0 {
                    Button(String(localized: "Forget everything…")) { confirmingForgetAll = true }
                        .buttonStyle(QuietButtonStyle(destructive: true))
                        .help(String(localized: "Remove every lesson \(name) has learnt"))
                }
            }
            // Empty, the panel below says it all.
            if count > 0 {
                Text(String(localized: "Lessons \(name) wrote down after its tasks. The surest and newest go into every turn it takes, up to 12."))
                    .captionText().foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, Space.xxs)
    }

    private var empty: some View {
        InsetPanel {
            HStack(spacing: Space.m) {
                Image(systemName: "sparkles")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
                Text(String(localized: "Nothing yet. In Agentic Mode, \(name) writes down what it learns after each task."))
                    .bodyText().foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.xs)
        }
    }

    private func forget(_ lesson: Lesson) {
        if editingID == lesson.id { editingID = nil }
        guard let undo = withAnimation(Motion.quick, { workspace.forgetLesson(lesson.id, of: agentID) }) else { return }
        let cue = lesson.cue.count > 48 ? lesson.cue.prefix(47) + "…" : lesson.cue
        workspace.toasts.show(String(localized: "Forgot “\(cue)”"), systemImage: "lightbulb.slash",
                              action: .init(title: String(localized: "Undo"), run: undo))
    }

    private func forgetAll() {
        editingID = nil
        guard let undo = withAnimation(Motion.quick, { workspace.forgetAllLessons(of: agentID) }) else { return }
        workspace.toasts.show(String(localized: "\(name) forgot everything it had learnt"), systemImage: "lightbulb.slash",
                              action: .init(title: String(localized: "Undo"), run: undo))
    }

    static func count(_ n: Int) -> String {
        n == 1 ? String(localized: "1 lesson") : String(localized: "\(n) lessons")
    }
}

extension Lesson.Confidence {
    var title: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        }
    }

    var pill: PillState {
        switch self {
        case .low: .neutral
        case .medium: .running
        case .high: .success
        }
    }
}

/// One lesson: the cue, what to do, how sure, and why it's believed.
private struct LessonRow: View {
    let lesson: Lesson
    let edit: () -> Void
    let forget: () -> Void

    static func uses(_ n: Int) -> String {
        switch n {
        case 0: String(localized: "Not used yet")
        case 1: String(localized: "Used once")
        default: String(localized: "Used \(n) times")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(lesson.cue).emphasisText().foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.s)
                    StatusPill(lesson.confidence.pill, lesson.confidence.title)
                        .help(String(localized: "How sure the agent is"))
                        .accessibilityLabel(String(localized: "\(lesson.confidence.title) confidence"))
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text(lesson.lesson).bodyText().foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if !lesson.evidence.isEmpty {
                    Text(lesson.evidence).captionText().italic().foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Space.l)
                }
                HStack(spacing: Space.s) {
                    MonoLabel(String(localized: "Learnt \(lesson.learnt.formatted(.relative(presentation: .named)))"))
                    MonoLabel("·")
                    MonoLabel(Self.uses(lesson.uses))
                }
                .padding(.leading, Space.l)
                .padding(.top, Space.xxs)
            }
            VStack(spacing: Space.xxs) {
                IconButton("pencil", help: String(localized: "Edit this lesson"), action: edit)
                IconButton("trash", help: String(localized: "Forget this lesson"), action: forget)
            }
        }
        .padding(Space.m)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline))
        .accessibilityElement(children: .contain)
    }
}

/// The same lesson, reworded in place: Return saves, Esc cancels.
private struct LessonEditorRow: View {
    let lesson: Lesson
    let save: (Lesson) -> Void
    let cancel: () -> Void
    @State private var draft: Lesson
    @FocusState private var focused: Bool

    init(lesson: Lesson, save: @escaping (Lesson) -> Void, cancel: @escaping () -> Void) {
        self.lesson = lesson
        self.save = save
        self.cancel = cancel
        _draft = State(initialValue: lesson)
    }

    private var canSave: Bool {
        !draft.cue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.lesson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            field(String(localized: "When this happens")) {
                TextField(String(localized: "When this happens"), text: $draft.cue,
                          prompt: Text(String(localized: "When Xcode asks to trust a package")))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focused)
            }
            field(String(localized: "Do this")) {
                TextField(String(localized: "Do this"), text: $draft.lesson,
                          prompt: Text(String(localized: "Choose Trust and Enable")), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .lineLimit(1...4)
            }
            HStack(spacing: Space.m) {
                field(String(localized: "Confidence")) {
                    Picker(String(localized: "Confidence"), selection: $draft.confidence) {
                        ForEach(Lesson.Confidence.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                // Not .cancelAction: that's the sheet's Cancel; Esc in a field is handled below.
                Button(String(localized: "Cancel"), action: cancel)
                    .buttonStyle(QuietButtonStyle())
                Button(String(localized: "Save lesson")) { save(draft) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSave)
            }
        }
        .padding(Space.m)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.accent.opacity(0.5)))
        .onSubmit { if canSave { save(draft) } }
        .onExitCommand(perform: cancel)
        .task { focused = true }
    }

    private func field(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).captionText().foregroundStyle(Palette.textSecondary)
            content()
        }
    }
}
