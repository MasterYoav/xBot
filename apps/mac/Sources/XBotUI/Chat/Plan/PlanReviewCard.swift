import SwiftUI
import XBotCore

/// "Here's my plan." Steps the person can edit, reorder, remove and add before anything runs.
struct PlanReviewCard: View {
    let workspace: Workspace
    let chatID: UUID
    let messageID: UUID
    let plan: Plan
    @State private var steps: [PlanStep]
    @State private var hovered: UUID?
    @FocusState private var focused: UUID?

    init(workspace: Workspace, chatID: UUID, messageID: UUID, plan: Plan) {
        self.workspace = workspace
        self.chatID = chatID
        self.messageID = messageID
        self.plan = plan
        _steps = State(initialValue: plan.steps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(String(localized: "Here's my plan. Change anything you like, then run it.")).bodyText()
            Card(
                title: String(localized: "Review the plan"),
                meta: footer
            ) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(String(localized: "Edit, reorder or remove steps before the agent starts. Move a step with ⌥↑ and ⌥↓."))
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, Space.s)
                    InsetPanel {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            ForEach(Array($steps.enumerated()), id: \.element.id) { index, $step in
                                row(index, $step)
                            }
                            Button(action: add) {
                                Label(String(localized: "Add step"), systemImage: "plus")
                                    .font(Typography.chip)
                                    .foregroundStyle(Palette.textSecondary)
                                    .padding(.horizontal, Space.s)
                                    .frame(height: Metrics.row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } footer: {
                CardFooter(String(localized: "Read-only planning")) {
                    Button(String(localized: "Cancel")) { workspace.cancelPlan(messageID, in: chatID) }
                        .buttonStyle(QuietButtonStyle())
                    Button(action: run) {
                        HStack(spacing: Space.xs) {
                            Text(String(localized: "Run plan"))
                            Text(verbatim: "⌘↩").opacity(0.6)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(runnable.isEmpty || workspace.isRunning(chatID))
                }
            }
        }
        .motion(Motion.quick, value: steps.map(\.id))
    }

    private var runnable: [PlanStep] {
        steps.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var footer: String {
        runnable.isEmpty
            ? String(localized: "Add a step to run.")
            : runnable.count == 1 ? String(localized: "1 step") : String(localized: "\(runnable.count) steps")
    }

    private func row(_ index: Int, _ step: Binding<PlanStep>) -> some View {
        let id = step.wrappedValue.id
        let highlighted = focused == id || hovered == id
        return HStack(spacing: Space.s) {
            Text(verbatim: "\(index + 1)")
                .captionText()
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
                .frame(width: Space.l, alignment: .trailing)
            TextField("", text: step.title)
                .textFieldStyle(.plain)
                .bodyText()
                .focused($focused, equals: id)
                .onSubmit { focusAfter(index) }
                .onKeyPress(.upArrow, phases: .down) { press in move(press, index, by: -1) }
                .onKeyPress(.downArrow, phases: .down) { press in move(press, index, by: 1) }
                .onKeyPress(.delete) {
                    guard step.wrappedValue.title.isEmpty else { return .ignored }
                    remove(index)
                    return .handled
                }
            if highlighted {
                Button { remove(index) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                    .help(String(localized: "Remove step"))
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(highlighted ? Palette.raised : .clear,
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .overlay {
            if focused == id {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous).strokeBorder(Palette.hairline)
            }
        }
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
    }

    private func move(_ press: KeyPress, _ index: Int, by offset: Int) -> KeyPress.Result {
        guard press.modifiers.contains(.option) else { return .ignored }
        let target = index + offset
        guard steps.indices.contains(target) else { return .handled }
        steps.swapAt(index, target)
        return .handled
    }

    private func remove(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)
        focused = steps.indices.contains(index) ? steps[index].id : steps.last?.id
    }

    private func add() {
        let step = PlanStep(title: "", active: "")
        steps.append(step)
        focused = step.id
    }

    private func focusAfter(_ index: Int) {
        if steps.indices.contains(index + 1) { focused = steps[index + 1].id } else { add() }
    }

    private func run() {
        workspace.runPlan(messageID, in: chatID, steps: steps)
    }
}
