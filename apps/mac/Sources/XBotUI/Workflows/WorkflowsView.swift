import SwiftUI
import XBotBrain
import XBotCore

/// Jev workflows: agent steps and Jev decision steps, in order, dragged in from the palette on the
/// right. Only while Jev Workflows is on (Settings › AI); without a key, the page says so.
struct WorkflowsView: View {
    let workspace: Workspace
    @State private var selectedID: UUID?
    @Environment(\.openSettings) private var openSettings

    private var selected: Workflow? { selectedID.flatMap(workspace.workflow) ?? workspace.workflows.first }

    var body: some View {
        if !workspace.showsWorkflows {
            notice(String(localized: "Jev Workflows is off."),
                   detail: String(localized: "Turn it on in Settings › AI to build workflows that mix your agents with Jev's quick decisions."))
        } else {
            VStack(spacing: 0) {
                if workspace.jevKeyMissing { keyBanner }
                HStack(spacing: 0) {
                    list
                        .frame(width: Metrics.notesListWidth)
                        .background(Palette.sidebar.opacity(0.5))
                    Divider()
                    if let workflow = selected {
                        WorkflowEditor(workspace: workspace, workflow: workflow).id(workflow.id)
                    } else {
                        empty
                    }
                }
            }
        }
    }

    // MARK: Without the feature or a key

    private var keyBanner: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "key").foregroundStyle(Palette.warning)
            Text(String(localized: "Workflows need a TypeSafe Jev key to ask Jev anything."))
                .bodyText().foregroundStyle(Palette.textPrimary)
            Spacer()
            Button(String(localized: "Open Settings › AI")) { showAISettings() }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .padding(.top, Metrics.titleBar)
        .background(Palette.warningTint)
    }

    private func notice(_ title: String, detail: String) -> some View {
        VStack(spacing: Space.m) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted").font(Typography.hero).foregroundStyle(Palette.accent)
            Text(title).titleText().foregroundStyle(Palette.textPrimary)
            Text(detail).bodyText().foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: Metrics.readingWidth / 2)
            Button(String(localized: "Open Settings › AI")) { showAISettings() }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func showAISettings() {
        SettingsTab.select(.ai)
        openSettings()
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(String(localized: "Workflows")).titleText().foregroundStyle(Palette.textPrimary)
                Spacer()
                IconButton("plus", help: String(localized: "New workflow")) { create() }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, workspace.jevKeyMissing ? Space.l : Space.l + Metrics.titleBar)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(workspace.workflows) { workflow in
                        Button { selectedID = workflow.id } label: {
                            SidebarRow(workflow.name, systemImage: icon(for: workflow), isSelected: workflow.id == selected?.id) {
                                if workspace.isRunning(workflow: workflow.id) {
                                    ProgressView().controlSize(.mini)
                                } else if !workflow.isEnabled {
                                    MonoLabel(String(localized: "off"))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.s)
            }
            Spacer(minLength: 0)
            Text(String(localized: "Scheduled workflows run while xBot is open, and through the automations helper while it's closed, if that's on."))
                .captionText().foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.m)
        }
    }

    private func icon(for workflow: Workflow) -> String {
        if case .schedule = workflow.trigger { return "clock" }
        return "point.3.connected.trianglepath.dotted"
    }

    private var empty: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted").font(Typography.hero).foregroundStyle(Palette.accent)
            Text(String(localized: "Let Jev steer your agents")).titleText().foregroundStyle(Palette.textPrimary)
            Text(String(localized: "Put agent steps in order, and Jev steps between them that decide in a blink whether to go on, which way to go, and which agent is cheapest for the job."))
                .bodyText().foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: Metrics.readingWidth / 2)
            Button(String(localized: "New workflow")) { create() }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func create() {
        let workflow = workspace.newWorkflow()
        workspace.saveWorkflow(workflow)
        selectedID = workflow.id
    }
}

// MARK: - Editor

private struct WorkflowEditor: View {
    let workspace: Workspace
    @State var workflow: Workflow
    @State private var dropTarget: Int?
    @State private var confirmingDelete = false
    @State private var askingInput = false
    @State private var input = ""

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    TriggerCard(trigger: $workflow.trigger)
                    steps
                    WorkflowRuns(workspace: workspace, workflowID: workflow.id)
                }
                .padding(Space.xl)
                .padding(.top, Metrics.titleBar)
                .frame(maxWidth: Metrics.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            Divider()
            StepPalette { (kind: Workflow.PaletteKind) in add(kind) }
                .frame(width: Metrics.inspectorIdealWidth - Space.xxl)
        }
        .onChange(of: workflow) { _, new in workspace.saveWorkflow(new) }
        .confirmationDialog(String(localized: "Delete \(workflow.name)?"), isPresented: $confirmingDelete) {
            Button(String(localized: "Delete"), role: .destructive) { workspace.deleteWorkflow(workflow.id) }
        } message: {
            Text(String(localized: "Its past runs stay as chats."))
        }
        .sheet(isPresented: $askingInput) { inputSheet }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                TextField(String(localized: "Name"), text: $workflow.name)
                    .textFieldStyle(.plain)
                    .font(Typography.hero)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Toggle("", isOn: $workflow.isEnabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .help(String(localized: "On: runs on its schedule. Run now always works."))
                Menu {
                    Button(String(localized: "Run with…")) { askingInput = true }
                    Divider()
                    Button(String(localized: "Delete…"), role: .destructive) { confirmingDelete = true }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                runButton
            }
            HStack(spacing: Space.s) {
                fallbackMenu
                projectMenu
                if let next = workflow.isEnabled ? workspace.workflow(workflow.id)?.nextRun() : nil {
                    Text(String(localized: "Next: \(next.formatted(date: .abbreviated, time: .shortened))"))
                        .captionText().foregroundStyle(Palette.textTertiary).lineLimit(1).fixedSize()
                }
            }
            if let reason = blockedReason {
                Text(reason).captionText().foregroundStyle(Palette.textTertiary)
            }
        }
    }

    /// Why Run now is off, unless it's only that it's running.
    private var blockedReason: String? {
        workspace.isRunning(workflow: workflow.id) ? nil : workspace.workflowBlockedReason(workflow)
    }

    private var runButton: some View {
        let running = workspace.isRunning(workflow: workflow.id)
        return Button {
            workspace.runWorkflow(workflow.id)
        } label: {
            Label(running ? String(localized: "Running…") : String(localized: "Run now"), systemImage: "play.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(running || blockedReason != nil)
    }

    private var inputSheet: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(String(localized: "Run \(workflow.name) with…")).titleText()
            Text(String(localized: "What you write here is the workflow's input: the first step and Jev both see it."))
                .captionText().foregroundStyle(Palette.textSecondary)
            TextEditor(text: $input)
                .font(Typography.body)
                .frame(minHeight: Metrics.toolOutputMaxHeight / 2)
                .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Palette.hairline))
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { askingInput = false }
                Button(String(localized: "Run")) {
                    workspace.runWorkflow(workflow.id, input: input)
                    input = ""
                    askingInput = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(blockedReason != nil)
            }
        }
        .padding(Space.xl)
        .frame(width: Metrics.composerWidth * 0.7)
    }

    /// The brain a "Jev picks" step falls back to when Jev can't be reached.
    private var fallbackMenu: some View {
        Menu {
            ForEach(workspace.availableHarnesses, id: \.self) { harness in
                Menu(harness.displayName) {
                    Button(String(localized: "Default model")) { workflow.harness = harness; workflow.model = nil }
                    ForEach(workspace.models(for: harness)) { option in
                        Button(option.name) { workflow.harness = harness; workflow.model = option.id }
                    }
                }
            }
        } label: {
            Chip(String(localized: "If Jev can't pick: \(workflow.harness.displayName)"),
                 detail: workflow.model.map { id in workspace.models(for: workflow.harness).first { $0.id == id }?.name ?? id },
                 dot: Palette.agent(workflow.harness), showsChevron: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(String(localized: "A step set to Jev picks runs on this when Jev can't be reached."))
    }

    private var projectMenu: some View {
        let project = workspace.projects.first { $0.id == workflow.projectID }
        return Menu {
            Button(String(localized: "No project")) { workflow.projectID = nil }
            Divider()
            ForEach(workspace.projects) { p in Button(p.name) { workflow.projectID = p.id } }
        } label: {
            Chip(project?.name ?? String(localized: "No project"), systemImage: "folder", showsChevron: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MonoLabel(String(localized: "STEPS"))
            ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                insertionLine(index)
                WorkflowStepCard(
                    workspace: workspace, number: index + 1, step: binding(for: step.id),
                    targets: targets(excluding: step.id),
                    remove: { workflow.removeStep(step.id) }
                )
                .draggable(Workflow.dragItem(for: step))
                .dropDestination(for: String.self) { items, _ in drop(items, at: index) } isTargeted: { (on: Bool) in
                    if on { dropTarget = index } else if dropTarget == index { dropTarget = nil }
                }
            }
            insertionLine(workflow.steps.count)
            dropZone
        }
    }

    private func targets(excluding id: UUID) -> [StepTargetItem] {
        workflow.steps.filter { $0.id != id }.map { StepTargetItem(id: $0.id, title: $0.title) }
    }

    private func insertionLine(_ index: Int) -> some View {
        Capsule().fill(Palette.accent).frame(height: Metrics.progressHeight).opacity(dropTarget == index ? 1 : 0)
    }

    private var dropZone: some View {
        let isTarget = dropTarget == workflow.steps.count
        return VStack(spacing: Space.xs) {
            Image(systemName: "square.and.arrow.down").font(Typography.title)
            Text(workflow.steps.isEmpty
                 ? String(localized: "Drag an agent step or a Jev step here to begin")
                 : String(localized: "Drag here to add a step"))
                .bodyText()
        }
        .foregroundStyle(isTarget ? Palette.accent : Palette.textTertiary)
        .frame(maxWidth: .infinity, minHeight: Space.xxl * 2)
        .background(RoundedRectangle(cornerRadius: Radius.medium).fill(isTarget ? Palette.accentTint : .clear))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium)
            .strokeBorder(isTarget ? Palette.accent : Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .dropDestination(for: String.self) { items, _ in drop(items, at: workflow.steps.count) } isTargeted: { (on: Bool) in
            if on { dropTarget = workflow.steps.count } else if dropTarget == workflow.steps.count { dropTarget = nil }
        }
    }

    private func binding(for id: UUID) -> Binding<WorkflowStep> {
        Binding(
            get: { () -> WorkflowStep in
                workflow.steps.first { $0.id == id } ?? WorkflowStep(title: "", kind: .agent(AgentStep(prompt: "")))
            },
            set: { (new: WorkflowStep) in
                if let i = workflow.steps.firstIndex(where: { $0.id == id }) { workflow.steps[i] = new }
            }
        )
    }

    private func drop(_ items: [String], at index: Int) -> Bool {
        dropTarget = nil
        guard let item = items.first else { return false }
        return workflow.drop(item, at: index)
    }

    private func add(_ kind: Workflow.PaletteKind) {
        workflow.drop(Workflow.dragItem(for: kind), at: workflow.steps.count)
    }
}

/// Another step a branch can go to.
private struct StepTargetItem: Identifiable {
    let id: UUID
    let title: String
}

// MARK: - A step

private struct WorkflowStepCard: View {
    let workspace: Workspace
    let number: Int
    @Binding var step: WorkflowStep
    let targets: [StepTargetItem]
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "line.3.horizontal").foregroundStyle(Palette.textTertiary).padding(.top, Space.s)
                .help(String(localized: "Drag to reorder"))
            Image(systemName: symbol).font(Typography.title).foregroundStyle(tint)
                .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                .background(RoundedRectangle(cornerRadius: Radius.small).fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    Text(verbatim: "\(number).").emphasisText().foregroundStyle(Palette.textSecondary)
                    TextField(String(localized: "Title"), text: $step.title)
                        .textFieldStyle(.plain).font(Typography.emphasis).foregroundStyle(Palette.textPrimary)
                }
                if case .agent = step.kind { agentBody } else { jevBody }
            }
            Spacer(minLength: 0)
            IconButton("xmark", help: String(localized: "Remove step"), action: remove).opacity(hovering ? 1 : 0)
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.medium).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(Palette.hairline))
        .onHover { hovering = $0 }
    }

    private var symbol: String {
        switch step.kind {
        case .agent: "person.crop.square"
        case .jev(let jev):
            switch jev.decision {
            case .gate: "checkmark.diamond"
            case .route: "arrow.triangle.branch"
            case .score: "gauge.with.dots.needle.50percent"
            }
        }
    }

    private var tint: Color {
        if case .agent = step.kind { return Palette.running }
        return Palette.accent
    }

    // MARK: Agent

    private var agent: AgentStep {
        if case .agent(let agent) = step.kind { return agent }
        return AgentStep(prompt: "")
    }

    private func setAgent(_ change: (inout AgentStep) -> Void) {
        var copy = agent
        change(&copy)
        step.kind = .agent(copy)
    }

    @ViewBuilder private var agentBody: some View {
        TextField(String(localized: "What the agent should do, in plain words"),
                  text: Binding(get: { () -> String in agent.prompt },
                                set: { (text: String) in setAgent { $0.prompt = text } }),
                  axis: .vertical)
            .textFieldStyle(.plain).font(Typography.body).foregroundStyle(Palette.textPrimary).lineLimit(1...8)
        HStack(spacing: Space.xxs) {
            brainMenu
            if case .fixed(let choice) = agent.brain { effortMenu(choice) }
            permissionMenu
        }
    }

    private var brainLabel: Chip {
        switch agent.brain {
        case .jevPicks:
            Chip(String(localized: "Jev picks"), systemImage: "sparkles", showsChevron: true)
        case .fixed(let choice):
            Chip(choice.harness.displayName,
                 detail: choice.model.map { id in "· " + (workspace.models(for: choice.harness).first { $0.id == id }?.name ?? id) },
                 dot: Palette.agent(choice.harness), showsChevron: true)
        }
    }

    private var brainMenu: some View {
        Menu {
            Button(String(localized: "Jev picks")) { setAgent { $0.brain = .jevPicks } }
            Divider()
            ForEach(workspace.availableHarnesses, id: \.self) { harness in
                Menu(harness.displayName) {
                    Button(String(localized: "Default model")) { setAgent { $0.brain = .fixed(BrainChoice(harness: harness)) } }
                    ForEach(workspace.models(for: harness)) { option in
                        Button(option.name) { setAgent { $0.brain = .fixed(BrainChoice(harness: harness, model: option.id)) } }
                    }
                }
            }
        } label: {
            brainLabel
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(String(localized: "Jev picks: just before the step runs, Jev chooses the cheapest agent, model and effort that can do it."))
    }

    private func effortMenu(_ choice: BrainChoice) -> some View {
        Menu {
            Button(String(localized: "The agent's default")) {
                setAgent { $0.brain = .fixed(BrainChoice(harness: choice.harness, model: choice.model)) }
            }
            ForEach(Effort.allCases, id: \.self) { effort in
                Button(effort.title) {
                    setAgent { $0.brain = .fixed(BrainChoice(harness: choice.harness, model: choice.model, effort: effort)) }
                }
            }
        } label: {
            Chip(choice.effort?.title ?? String(localized: "Default effort"), systemImage: "brain", showsChevron: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(PermissionMode.allCases, id: \.self) { mode in
                Button { setAgent { $0.mode = mode } } label: { Label(mode.title, systemImage: mode.symbol) }
            }
        } label: {
            Chip(agent.mode.title, systemImage: agent.mode.symbol, showsChevron: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Jev

    private var jev: JevStep {
        if case .jev(let jev) = step.kind { return jev }
        return JevStep(question: "", decision: .gate(JevGate()))
    }

    private func setJev(_ change: (inout JevStep) -> Void) {
        var copy = jev
        change(&copy)
        step.kind = .jev(copy)
    }

    @ViewBuilder private var jevBody: some View {
        TextField(placeholder,
                  text: Binding(get: { () -> String in jev.question },
                                set: { (text: String) in setJev { $0.question = text } }),
                  axis: .vertical)
            .textFieldStyle(.plain).font(Typography.body).foregroundStyle(Palette.textPrimary).lineLimit(1...4)
        switch jev.decision {
        case .gate(let gate): gateBranches(gate)
        case .route(let options): routeBranches(options)
        case .score(let levels): scoreBranches(levels)
        }
    }

    private var placeholder: String {
        switch jev.decision {
        case .gate: String(localized: "A yes/no question about the run so far, e.g. Is the build failing?")
        case .route: String(localized: "What Jev should choose between, e.g. What kind of change is this?")
        case .score: String(localized: "What Jev should rate, e.g. How good is the draft?")
        }
    }

    private func setGate(_ gate: JevGate) { setJev { $0.decision = .gate(gate) } }

    private func gateBranches(_ gate: JevGate) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Text(String(localized: "Yes at")).captionText().foregroundStyle(Palette.textSecondary)
                Slider(value: Binding(get: { () -> Double in gate.threshold },
                                      set: { (value: Double) in
                                          var g = gate
                                          g.threshold = (value * 20).rounded() / 20
                                          setGate(g)
                                      }),
                       in: 0.05...0.95)
                    .frame(width: Metrics.effortCardWidth / 2)
                Text(verbatim: String(format: "%.2f", gate.threshold)).font(Typography.mono).foregroundStyle(Palette.textSecondary)
            }
            branch(String(localized: "Yes →"), gate.yes) { (target: StepTarget) in
                var g = gate
                g.yes = target
                setGate(g)
            }
            branch(String(localized: "No →"), gate.no) { (target: StepTarget) in
                var g = gate
                g.no = target
                setGate(g)
            }
        }
    }

    private func routeBranches(_ options: [RouteOption]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(options) { option in
                HStack(spacing: Space.s) {
                    TextField(String(localized: "Option"), text: Binding(
                        get: { () -> String in option.label },
                        set: { (text: String) in updateRoute(option.id) { $0.label = text } }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: Metrics.effortCardWidth * 0.6)
                    branch("→", option.target) { (target: StepTarget) in updateRoute(option.id) { $0.target = target } }
                    if options.count > 2 {
                        IconButton("minus.circle", help: String(localized: "Remove option")) {
                            setJev { $0.decision = .route(options.filter { $0.id != option.id }) }
                        }
                    }
                }
            }
            Button(String(localized: "Add option")) {
                setJev { $0.decision = .route(options + [RouteOption(label: String(localized: "Another option"))]) }
            }
            .buttonStyle(.link).disabled(options.count >= 255)
        }
    }

    private func updateRoute(_ id: UUID, _ change: (inout RouteOption) -> Void) {
        guard case .route(var options) = jev.decision, let i = options.firstIndex(where: { $0.id == id }) else { return }
        change(&options[i])
        setJev { $0.decision = .route(options) }
    }

    private func scoreBranches(_ levels: [ScoreLevel]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(String(localized: "Levels, lowest first")).captionText().foregroundStyle(Palette.textTertiary)
            ForEach(levels) { level in
                HStack(spacing: Space.s) {
                    TextField(String(localized: "Level"), text: Binding(
                        get: { () -> String in level.label },
                        set: { (text: String) in updateScore(level.id) { $0.label = text } }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: Metrics.effortCardWidth * 0.6)
                    branch("→", level.target) { (target: StepTarget) in updateScore(level.id) { $0.target = target } }
                    if levels.count > 2 {
                        IconButton("minus.circle", help: String(localized: "Remove level")) {
                            setJev { $0.decision = .score(levels.filter { $0.id != level.id }) }
                        }
                    }
                }
            }
            Button(String(localized: "Add level")) {
                setJev { $0.decision = .score(levels + [ScoreLevel(label: String(localized: "Higher"))]) }
            }
            .buttonStyle(.link).disabled(levels.count >= 10)
        }
    }

    private func updateScore(_ id: UUID, _ change: (inout ScoreLevel) -> Void) {
        guard case .score(var levels) = jev.decision, let i = levels.firstIndex(where: { $0.id == id }) else { return }
        change(&levels[i])
        setJev { $0.decision = .score(levels) }
    }

    /// A branch as a picker: continue, stop, or go to another step.
    private func branch(_ label: String, _ target: StepTarget, set: @escaping (StepTarget) -> Void) -> some View {
        HStack(spacing: Space.xs) {
            Text(label).captionText().foregroundStyle(Palette.textSecondary)
            Picker("", selection: Binding(get: { () -> StepTarget in target }, set: { (new: StepTarget) in set(new) })) {
                Text(String(localized: "Continue")).tag(StepTarget.next)
                Text(String(localized: "Stop")).tag(StepTarget.stop)
                ForEach(targets) { item in
                    Text(String(localized: "Go to “\(item.title)”")).tag(StepTarget.step(item.id))
                }
            }
            .labelsHidden().fixedSize()
        }
    }
}

// MARK: - Palette

/// The kinds of step to drag in (or click to add at the end).
private struct StepPalette: View {
    let add: (Workflow.PaletteKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s) {
                MonoLabel(String(localized: "AGENT"))
                tile(.agent, "person.crop.square", String(localized: "Agent step"),
                     String(localized: "A prompt for Claude Code, Codex and the others, or Jev picks the cheapest that can do it."))
                MonoLabel(String(localized: "JEV")).padding(.top, Space.s)
                tile(.gate, "checkmark.diamond", String(localized: "Yes/no gate"),
                     String(localized: "Go on, go to a step, or stop, on a yes/no question."))
                tile(.route, "arrow.triangle.branch", String(localized: "Route"),
                     String(localized: "Each option goes to a step."))
                tile(.score, "gauge.with.dots.needle.50percent", String(localized: "Score"),
                     String(localized: "Rate on 2–10 levels; each level goes to a step."))
            }
            .padding(Space.m)
            .padding(.top, Metrics.titleBar)
        }
        .scrollIndicators(.never)
        .background(Palette.sidebar.opacity(0.5))
    }

    private func tile(_ kind: Workflow.PaletteKind, _ symbol: String, _ title: String, _ detail: String) -> some View {
        Button { add(kind) } label: {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: symbol).font(Typography.title)
                    .foregroundStyle(kind == .agent ? Palette.running : Palette.accent)
                    .frame(width: Metrics.iconButton)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).emphasisText().foregroundStyle(Palette.textPrimary)
                    Text(detail).captionText().foregroundStyle(Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.small).fill(Palette.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(Workflow.dragItem(for: kind))
        .help(String(localized: "Drag into the steps, or click to add"))
    }
}

// MARK: - Runs

private struct WorkflowRuns: View {
    let workspace: Workspace
    let workflowID: UUID

    var body: some View {
        let runs = workspace.runs(ofWorkflow: workflowID)
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                MonoLabel(String(localized: "RUNS"))
                ForEach(runs.prefix(20)) { run in
                    let failed = !workspace.isRunning(run.id) && workspace.runFailed(run.id)
                    Button { workspace.open(run.id) } label: {
                        SidebarRow(run.createdAt.formatted(date: .abbreviated, time: .shortened),
                                   systemImage: workspace.isRunning(run.id) ? "circle.dotted"
                                       : failed ? "exclamationmark.triangle" : "checkmark.circle") {
                            if workspace.isRunning(run.id) {
                                ProgressView().controlSize(.mini)
                            } else if failed {
                                Text(String(localized: "Stopped")).captionText().foregroundStyle(Palette.failure)
                            } else {
                                Text(String(localized: "Open")).captionText().foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Space.s)
        }
    }
}
