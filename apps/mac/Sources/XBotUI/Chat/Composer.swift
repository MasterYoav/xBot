import SwiftUI
import XBotCore

/// The one composer: on Home it writes the draft; docked in a chat it sends to that chat.
/// A context strip (project, branch, agents) on top; the text; then the chips and send.
struct Composer: View {
    enum Target: Equatable { case draft, chat(UUID) }

    let workspace: Workspace
    let target: Target
    let namespace: Namespace.ID
    let addProject: () -> Void
    @State private var chatText = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            contextStrip
            VStack(alignment: .leading, spacing: Space.s) {
                TextField(placeholder, text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .readingText()
                    .lineLimit(1...10)
                    .focused($focused)
                    .onSubmit(send)
                HStack(spacing: Space.xxs) {
                    agentMenu
                    EffortChip(effort: effort, recommended: recommendedEffort, onChange: setEffort)
                    permissionMenu
                    planMenu
                    Spacer(minLength: Space.s)
                    if let reason = blockedReason {
                        Text(reason).captionText().foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                    sendButton
                }
            }
            .padding(Space.m)
        }
        .background(Palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .strokeBorder(focused ? Palette.accent.opacity(0.4) : Palette.hairline)
        )
        .floatingShadow()
        .matchedGeometryEffect(id: "composer", in: namespace)
        .motion(Motion.quick, value: focused)
        .onAppear { focused = true }
        .onChange(of: workspace.composerFocusRequest) { focused = true }
        // A file mentioned from the explorer, or dropped on the composer: "@path " at the end.
        .onChange(of: workspace.mentionRequest) {
            guard let mention = workspace.pendingMention else { return }
            let current = text.wrappedValue
            text.wrappedValue = current + (current.isEmpty || current.hasSuffix(" ") ? "" : " ") + mention + " "
            focused = true
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach(workspace.mention)
            return !urls.isEmpty
        }
    }

    // MARK: Pieces

    private var contextStrip: some View {
        HStack(spacing: Space.s) {
            Menu {
                Button(String(localized: "Inbox")) { chooseProject(nil) }
                ForEach(workspace.projects) { project in
                    Button(project.name) { chooseProject(project.id) }
                }
                Divider()
                Button(String(localized: "Add a folder…"), action: addProject)
            } label: {
                Label(projectName, systemImage: "folder").font(Typography.chip)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(canChooseProject ? .visible : .hidden)
            .fixedSize()
            .disabled(!canChooseProject)
            if let branch = workspace.branch(for: projectID) {
                Label(branch, systemImage: "arrow.triangle.branch").font(Typography.mono).lineLimit(1)
            }
            Spacer()
            ForEach(workspace.availableHarnesses, id: \.self) { kind in
                Circle().fill(Palette.agent(kind)).frame(width: Metrics.dot, height: Metrics.dot).help(kind.displayName)
            }
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s - 2)
        .background(Palette.inset)
    }

    private var agentMenu: some View {
        Menu {
            ForEach(workspace.availableHarnesses, id: \.self) { kind in
                Section(kind.displayName) {
                    Button(String(localized: "Default model")) { choose(kind, nil) }
                    ForEach(workspace.models(for: kind)) { option in
                        Button(option.name) { choose(kind, option.id) }
                    }
                }
            }
        } label: {
            Chip(harness?.displayName ?? String(localized: "No agent"), detail: modelName.map { "· \($0)" },
                 dot: harness.map(Palette.agent), showsChevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isRunning)
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(PermissionMode.allCases, id: \.self) { mode in
                Button { setMode(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
            }
        } label: {
            Chip(mode.title, systemImage: mode.symbol, showsChevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var planMenu: some View {
        Menu {
            Toggle(String(localized: "Review plan first"), isOn: Binding(get: { reviewPlan }, set: setReview))
        } label: {
            Chip(String(localized: "Plan"), systemImage: "list.bullet.clipboard",
                 detail: planMode && !reviewPlan ? String(localized: "· runs at once") : nil, isOn: planMode)
        } primaryAction: {
            setPlan(!planMode)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Plan first: review the steps, then watch them run"))
    }

    @ViewBuilder private var sendButton: some View {
        let canSend = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && blockedReason == nil
        let button = Button {
            if isRunning, case .chat(let id) = target { workspace.stop(id) } else { send() }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                .font(Typography.emphasis.weight(.bold))
                .foregroundStyle(Palette.textInverse)
                .frame(width: Metrics.sendButton, height: Metrics.sendButton)
                .background(isRunning || canSend ? Palette.accent : Palette.textTertiary, in: Circle())
        }
        .buttonStyle(XBotButtonStyle())
        .disabled(!isRunning && !canSend)
        .help(isRunning ? String(localized: "Stop (⌘.)") : String(localized: "Send"))
        .motion(Motion.quick, value: canSend)
        // ⏎ already sends through the field's onSubmit; the button only adds ⌘. while running.
        if isRunning {
            button.keyboardShortcut(".", modifiers: .command)
        } else {
            button
        }
    }

    // MARK: State, by target

    private var chat: Chat? {
        if case .chat(let id) = target { workspace.chat(id) } else { nil }
    }

    private var text: Binding<String> {
        target == .draft
            ? Binding(get: { workspace.draft.text }, set: { workspace.draft.text = $0 })
            : $chatText
    }

    /// A draft, or a chat nothing has been said in yet (one just opened with an agent).
    private var canChooseProject: Bool {
        guard let chat else { return true }
        return workspace.messages(in: chat.id).isEmpty && !workspace.isRunning(chat.id)
    }

    private func chooseProject(_ id: UUID?) {
        if let chat { workspace.setProject(id, for: chat.id) } else { workspace.draft.projectID = id }
    }

    private var projectID: UUID? { chat?.projectID ?? (target == .draft ? workspace.draft.projectID : nil) }

    private var projectName: String {
        workspace.projects.first { $0.id == projectID }?.name ?? String(localized: "Inbox")
    }

    private var harness: HarnessKind? { chat?.harness ?? workspace.draftHarness }
    private var model: String? { chat.map(\.model) ?? (workspace.draft.harness == harness ? workspace.draft.model : nil) }
    private var mode: PermissionMode { chat?.mode ?? workspace.draft.mode }

    private var modelName: String? {
        guard let model, let harness else { return model }
        return workspace.models(for: harness).first { $0.id == model }?.name ?? model
    }

    private var recommendedEffort: Effort {
        harness.map { workspace.recommendedEffort(for: $0, model: model) } ?? .medium
    }

    /// Unset means the agent's default, which the slider shows as its recommended stop.
    private var effort: Effort { (chat.map(\.effort) ?? workspace.draft.effort) ?? recommendedEffort }

    private func setEffort(_ effort: Effort) {
        if let chat { workspace.setEffort(effort, for: chat.id) } else { workspace.draft.effort = effort }
    }
    private var planMode: Bool { chat?.planMode ?? workspace.draft.planMode }
    private var reviewPlan: Bool { chat?.reviewPlan ?? workspace.draft.reviewPlan }
    private var isRunning: Bool { chat.map { workspace.isRunning($0.id) } ?? false }

    private var blockedReason: String? {
        if let chat { return workspace.sendBlockedReason(chat.id) }
        return workspace.draftHarness == nil && !workspace.isDiscovering
            ? String(localized: "No agent found") : nil
    }

    private var placeholder: String {
        if !planMode, let agent = workspace.agent(chat?.agentID) {
            return String(localized: "Ask \(agent.name)…")
        }
        guard planMode else { return String(localized: "Describe a task, a bug to fix, an idea to try…") }
        return reviewPlan
            ? String(localized: "Describe the change. You'll review the plan first.")
            : String(localized: "Describe the change. The plan runs straight away.")
    }

    private func choose(_ kind: HarnessKind, _ model: String?) {
        if let chat {
            if chat.harness != kind { workspace.setHarness(kind, for: chat.id) }
            workspace.setModel(model, for: chat.id)
        } else {
            workspace.draft.harness = kind
            workspace.draft.model = model
        }
    }

    private func setMode(_ mode: PermissionMode) {
        if let chat { workspace.setMode(mode, for: chat.id) } else { workspace.draft.mode = mode }
    }

    private func setPlan(_ on: Bool) {
        if let chat { workspace.setPlanMode(on, for: chat.id) } else { workspace.draft.planMode = on }
    }

    private func setReview(_ on: Bool) {
        if let chat { workspace.setReviewPlan(on, for: chat.id) } else { workspace.draft.reviewPlan = on }
    }

    private func send() {
        switch target {
        case .draft:
            withAnimation(Motion.panel) { _ = workspace.sendDraft() }
        case .chat(let id):
            // Cleared only when the workspace took it: a refused send keeps what was typed.
            if workspace.send(chatText, in: id) { chatText = "" }
        }
    }
}

extension PermissionMode {
    var title: String {
        switch self {
        case .readOnly: String(localized: "Read only")
        case .editFiles: String(localized: "Can edit")
        case .fullAccess: String(localized: "Full access")
        }
    }

    var symbol: String {
        switch self {
        case .readOnly: "eye"
        case .editFiles: "pencil"
        case .fullAccess: "bolt"
        }
    }
}
