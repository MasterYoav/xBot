import SwiftUI
import XBotCore

/// The Agents page: the workplace, then what the crew is doing.
struct AgentsView: View {
    let workspace: Workspace
    var stageBottomChanged: (CGFloat) -> Void = { _ in }
    @State private var editing: AgentDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                WorkplaceScene(workspace: workspace, edit: { editing = AgentDraft($0, isNew: false) })
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.frame(in: .named("workplaceBackdrop")).maxY
                    } action: { stageBottomChanged($0) }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    cards
                }
            }
            .frame(maxWidth: Metrics.agentsWidth)
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: workspace.wantsToHire, initial: true) {
            guard workspace.wantsToHire else { return }
            workspace.wantsToHire = false
            editing = AgentDraft(workspace.hire(), isNew: true)
        }
        .sheet(item: $editing) { draft in
            AgentEditor(workspace: workspace, draft: draft)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(String(localized: "Agents")).heroText().foregroundStyle(Palette.textPrimary)
                Text(String(localized: "Your crew, at work. Click someone to open their chat."))
                    .bodyText().foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Picker(String(localized: "World"), selection: Binding(
                get: { workspace.workplace },
                set: { world in withAnimation(Motion.standard) { workspace.workplace = world } }
            )) {
                ForEach(WorkplaceSetting.allCases, id: \.self) { world in
                    Label(world.title, systemImage: world.symbol).tag(world)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel(String(localized: "World"))
            .fixedSize()
            .help(String(localized: "Where your crew lives"))
            Button {
                editing = AgentDraft(workspace.hire(), isNew: true)
            } label: {
                Label(String(localized: "Hire"), systemImage: "person.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Space.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    // MARK: Cards

    private var cards: some View {
        let statuses = workspace.agents.map { ($0, workspace.status(of: $0.id)) }
        let working = statuses.filter { $0.1.isWorking }
        let done = statuses.filter { $0.1 == .done }
        return VStack(spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                Card(title: String(localized: "Working now"), meta: working.isEmpty ? nil : "\(working.count)") {
                    if working.isEmpty {
                        quiet(String(localized: "Nobody's working right now."))
                    } else {
                        ForEach(working, id: \.0.id) { agent, status in
                            if case .working(let activity, let since) = status {
                                row(agent, detail: activity ?? String(localized: "Thinking…"),
                                    trailing: since.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                            }
                        }
                    }
                }
                Card(title: String(localized: "Just finished")) {
                    if done.isEmpty {
                        quiet(String(localized: "Nothing new for you."))
                    } else {
                        ForEach(done, id: \.0.id) { agent, _ in
                            row(agent, detail: String(localized: "Finished — open to read"), trailing: nil)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: Space.m) {
                activity
                crew
            }
        }
    }

    private var activity: some View {
        let days = workspace.agentActivity(days: 14)
        let peak = max(days.max() ?? 0, 1)
        return Card(title: String(localized: "Activity"), meta: String(localized: "14 days")) {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(verbatim: "\(days.reduce(0, +))").font(Typography.hero).foregroundStyle(Palette.textPrimary)
                    Text(String(localized: "replies from the crew")).captionText().foregroundStyle(Palette.textTertiary)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, count in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == days.count - 1 ? Palette.accent : Palette.accent.opacity(0.45))
                            .frame(height: max(3, 64 * CGFloat(count) / CGFloat(peak)))
                            .frame(maxWidth: .infinity)
                            .help("\(count)")
                    }
                }
                .frame(height: 64, alignment: .bottom)
            }
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.m)
        }
    }

    private var crew: some View {
        Card(title: String(localized: "Crew"), meta: "\(workspace.agents.count)") {
            VStack(spacing: 0) {
                ForEach(workspace.agents) { agent in
                    HStack(spacing: Space.m) {
                        AgentFace(agent: agent, size: 34, status: workspace.status(of: agent.id))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: Space.xs) {
                                Text(agent.name).emphasisText().foregroundStyle(Palette.textPrimary)
                                if agent.isHeadMaster {
                                    Text(String(localized: "Founder")).captionText().foregroundStyle(AvatarPalette.gold)
                                }
                            }
                            Text(agent.role).captionText().foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: Space.s)
                        Text(agent.harness.displayName).captionText().foregroundStyle(Palette.textTertiary)
                        IconButton("pencil", help: String(localized: "Edit \(agent.name)")) {
                            editing = AgentDraft(agent, isNew: false)
                        }
                        Button(String(localized: "Talk")) { workspace.talk(to: agent.id) }
                            .buttonStyle(OutlineButtonStyle())
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.s)
                }
            }
            .padding(.bottom, Space.s)
        }
    }

    private func row(_ agent: Agent, detail: String, trailing: String?) -> some View {
        Button { workspace.openLatestChat(with: agent.id) } label: {
            HStack(spacing: Space.m) {
                AgentFace(agent: agent, size: 28, status: workspace.status(of: agent.id))
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name).emphasisText().foregroundStyle(Palette.textPrimary)
                    Text(detail).captionText().foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s)
                if let trailing { MonoLabel(trailing) }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quiet(_ text: String) -> some View {
        Text(text).bodyText().foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.m)
    }
}

struct AgentDraft: Identifiable {
    var agent: Agent
    let isNew: Bool
    var id: UUID { agent.id }

    init(_ agent: Agent, isNew: Bool) {
        self.agent = agent
        self.isNew = isNew
    }
}

// MARK: - Editor

/// Who they are and how they look: a character creator beside the persona.
struct AgentEditor: View {
    let workspace: Workspace
    @State private var agent: Agent
    let isNew: Bool
    @State private var walking = false
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, draft: AgentDraft) {
        self.workspace = workspace
        _agent = State(initialValue: draft.agent)
        isNew = draft.isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.xl) {
                creator
                persona
            }
            .padding(Space.xl)
            Divider()
            footer
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.m)
        }
        .frame(width: Metrics.agentEditorWidth)
    }

    private var creator: some View {
        VStack(spacing: Space.m) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "7CC8FF"), Color(hex: "DDF2FF")], startPoint: .top, endPoint: .bottom))
                Rectangle().fill(Color(hex: "5DBB63")).frame(height: 26)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: "9A6A43")).frame(height: 12) }
                LivingAvatar(avatar: agent.avatar, pixel: 5, legs: walking ? .stride : .stand, seed: agent.id.hashValue)
                    .padding(.bottom, 12)
            }
            .frame(width: 230, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .onTapGesture { walking.toggle() }
            .help(String(localized: "Click to make them walk"))
            VStack(spacing: Space.xs) {
                ForEach(AgentAvatar.Part.allCases, id: \.self) { part in
                    HStack {
                        Text(part.title).captionText().foregroundStyle(Palette.textSecondary)
                        Spacer()
                        IconButton("chevron.left", help: String(localized: "Previous \(part.title.lowercased())")) {
                            agent.avatar.step(part, by: -1)
                        }
                        Text(verbatim: "\(agent.avatar[part] + 1)/\(part.count)")
                            .font(Typography.mono).foregroundStyle(Palette.textTertiary)
                            .frame(width: 40)
                        IconButton("chevron.right", help: String(localized: "Next \(part.title.lowercased())")) {
                            agent.avatar.step(part, by: 1)
                        }
                    }
                }
            }
            Button {
                withAnimation(.snappy) { agent.avatar = .random() }
            } label: {
                Label(String(localized: "Randomize"), systemImage: "dice")
            }
            .buttonStyle(OutlineButtonStyle())
        }
        .frame(width: 230)
    }

    private var persona: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(isNew ? String(localized: "Hire an agent") : agent.name).titleText()
            field(String(localized: "Name")) {
                TextField(String(localized: "Name"), text: $agent.name, prompt: Text(verbatim: "Pixel"))
                    .textFieldStyle(.roundedBorder)
            }
            field(String(localized: "Role")) {
                TextField(String(localized: "Role"), text: $agent.role,
                          prompt: Text(String(localized: "One line: what they do")))
                    .textFieldStyle(.roundedBorder)
            }
            field(String(localized: "Role instructions")) {
                TextEditor(text: $agent.instructions)
                    .font(Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(Space.xs)
                    .frame(minHeight: 150)
                    .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).strokeBorder(Palette.hairline))
            }
            HStack(spacing: Space.m) {
                field(String(localized: "Brain")) {
                    Picker(String(localized: "Brain"), selection: $agent.harness) {
                        ForEach(HarnessKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: agent.harness) { agent.model = nil }
                }
                field(String(localized: "Model")) {
                    Picker(String(localized: "Model"), selection: $agent.model) {
                        Text(String(localized: "Default")).tag(String?.none)
                        ForEach(workspace.models(for: agent.harness)) { option in
                            Text(option.name).tag(String?.some(option.id))
                        }
                    }
                    .labelsHidden()
                }
            }
            field(String(localized: "Home project")) {
                Picker(String(localized: "Home project"), selection: $agent.projectID) {
                    Text(String(localized: "The one in view")).tag(UUID?.none)
                    ForEach(workspace.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
            }
            if agent.isHeadMaster {
                Text(String(localized: "HeadMaster founded this place: it can hand work to the crew, and it can't be let go."))
                    .captionText().foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            if !isNew && !agent.isHeadMaster {
                Button(String(localized: "Let go…"), role: .destructive) {
                    let name = agent.name
                    if let undo = workspace.deleteAgent(agent.id) {
                        workspace.toasts.show(String(localized: "\(name) left the crew"), systemImage: "person.badge.minus",
                                              action: .init(title: String(localized: "Undo"), run: undo))
                    }
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
            }
            Spacer()
            Button(String(localized: "Cancel")) { dismiss() }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button(isNew ? String(localized: "Hire") : String(localized: "Save")) {
                workspace.saveAgent(agent)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(agent.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func field(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).captionText().foregroundStyle(Palette.textSecondary)
            content()
        }
    }
}
