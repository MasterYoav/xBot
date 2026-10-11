import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XBotBrain
import XBotCore

/// Automations: a trigger, then steps dragged in from the apps and connectors on the right, each
/// in plain words. An agent carries them out with full access. Replaces the Inbox.
struct AutomationsView: View {
    let workspace: Workspace
    @State private var selectedID: UUID?
    @State private var helperOn = AutomationHelper.isInstalled
    @State private var helperProblem: String?

    private var selected: Automation? { selectedID.flatMap(workspace.automation) ?? workspace.automations.first }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: Metrics.notesListWidth)
                .background(Palette.sidebar.opacity(0.5))
            Divider()
            if let automation = selected {
                AutomationEditor(workspace: workspace, automation: automation).id(automation.id)
            } else {
                empty
            }
        }
        .task { if workspace.abilities.items.isEmpty { await workspace.abilities.refresh() } }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(String(localized: "Automations")).titleText().foregroundStyle(Palette.textPrimary)
                Spacer()
                IconButton("plus", help: String(localized: "New automation")) { create() }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.l)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(workspace.automations) { automation in
                        Button { selectedID = automation.id } label: {
                            SidebarRow(automation.name, systemImage: icon(for: automation),
                                       isSelected: automation.id == selected?.id) {
                                if workspace.isRunning(automation: automation.id) {
                                    ProgressView().controlSize(.mini)
                                } else if !automation.isEnabled {
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
            helperToggle
                .padding(Space.m)
        }
    }

    private func icon(for automation: Automation) -> String {
        if case .schedule = automation.trigger { return "clock" }
        return "play.circle"
    }

    /// Off by default; turning it on installs the background helper, off removes it.
    private var helperToggle: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Toggle(isOn: Binding(get: { helperOn }, set: setHelper)) {
                Text(String(localized: "Run when xBot is closed")).bodyText().foregroundStyle(Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Text(helperOn
                 ? String(localized: "A small background helper checks every minute and runs what's due.")
                 : String(localized: "Scheduled automations run while xBot is open."))
                .captionText().foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let helperProblem {
                Text(helperProblem).captionText().foregroundStyle(Palette.failure)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setHelper(_ on: Bool) {
        do {
            if on { try AutomationHelper.install() } else { try AutomationHelper.uninstall() }
            helperProblem = nil
        } catch {
            helperProblem = error.localizedDescription
        }
        helperOn = AutomationHelper.isInstalled
    }

    private var empty: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "wand.and.stars").font(.system(size: 34)).foregroundStyle(Palette.accent)
            Text(String(localized: "Automate anything you do on your Mac")).titleText().foregroundStyle(Palette.textPrimary)
            Text(String(localized: "Drag in Mail, Calendar, Notes, your connectors and more, say what to do in each step, and let an agent do it."))
                .bodyText().foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(String(localized: "New automation")) { create() }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func create() {
        let automation = workspace.newAutomation()
        workspace.saveAutomation(automation)
        selectedID = automation.id
    }
}

// MARK: - Editor

private struct AutomationEditor: View {
    let workspace: Workspace
    @State var automation: Automation
    @State private var dropTarget: Int?
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    TriggerCard(trigger: $automation.trigger)
                    steps
                    RunHistory(workspace: workspace, automationID: automation.id)
                }
                .padding(Space.xl)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            Divider()
            AppPalette(workspace: workspace) { add($0, at: automation.steps.count) }
                .frame(width: 252)
        }
        .onChange(of: automation) { _, new in workspace.saveAutomation(new) }
        .confirmationDialog(String(localized: "Delete \(automation.name)?"), isPresented: $confirmingDelete) {
            Button(String(localized: "Delete"), role: .destructive) { workspace.deleteAutomation(automation.id) }
        } message: {
            Text(String(localized: "Its past runs stay as chats."))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                TextField(String(localized: "Name"), text: $automation.name)
                    .textFieldStyle(.plain)
                    .font(Typography.hero)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Toggle("", isOn: $automation.isEnabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .help(String(localized: "On: runs on its schedule. Run now always works."))
                Menu {
                    Button(String(localized: "Delete…"), role: .destructive) { confirmingDelete = true }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                runButton
            }
            HStack(spacing: Space.s) {
                agentMenu
                projectMenu
                Label(String(localized: "Full access"), systemImage: "bolt")
                    .captionText().foregroundStyle(Palette.warning)
                    .help(String(localized: "Automations run with full access: they can do anything you can on this Mac."))
                if let next = automation.isEnabled ? workspace.automation(automation.id)?.nextRun() : nil {
                    Text(String(localized: "Next: \(next.formatted(date: .abbreviated, time: .shortened))"))
                        .captionText().foregroundStyle(Palette.textTertiary)
                        .lineLimit(1).fixedSize()
                }
            }
        }
    }

    private var runButton: some View {
        let running = workspace.isRunning(automation: automation.id)
        let hasSteps = automation.hasWork
        return Button {
            workspace.runAutomation(automation.id)
        } label: {
            Label(running ? String(localized: "Running…") : String(localized: "Run now"), systemImage: "play.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(running || !hasSteps || !workspace.availableHarnesses.contains(automation.harness))
    }

    private var agentMenu: some View {
        Menu {
            ForEach(workspace.availableHarnesses, id: \.self) { harness in
                Menu(harness.displayName) {
                    Button(String(localized: "Default model")) { automation.harness = harness; automation.model = nil }
                    ForEach(workspace.modelOptions[harness] ?? []) { option in
                        Button(option.name) { automation.harness = harness; automation.model = option.id }
                    }
                }
            }
        } label: {
            Chip(automation.harness.displayName, detail: automation.model.map { id in
                workspace.modelOptions[automation.harness]?.first { $0.id == id }?.name ?? id
            }, dot: Palette.agent(automation.harness), showsChevron: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private var projectMenu: some View {
        let project = workspace.projects.first { $0.id == automation.projectID }
        return Menu {
            Button(String(localized: "No project")) { automation.projectID = nil }
            Divider()
            ForEach(workspace.projects) { p in Button(p.name) { automation.projectID = p.id } }
        } label: {
            Chip(project?.name ?? String(localized: "No project"), systemImage: "folder", showsChevron: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MonoLabel(String(localized: "STEPS"))
            ForEach(Array(automation.steps.enumerated()), id: \.element.id) { index, step in
                insertionLine(index)
                StepCard(
                    number: index + 1, step: binding(for: step.id),
                    remove: { automation.steps.removeAll { $0.id == step.id } }
                )
                .draggable(Automation.dragItem(for: step))
                .dropDestination(for: String.self) { items, _ in drop(items, at: index) } isTargeted: {
                    if $0 { dropTarget = index } else if dropTarget == index { dropTarget = nil }
                }
            }
            insertionLine(automation.steps.count)
            dropZone
        }
    }

    private func insertionLine(_ index: Int) -> some View {
        Capsule().fill(Palette.accent).frame(height: 2).opacity(dropTarget == index ? 1 : 0)
    }

    private var dropZone: some View {
        let isTarget = dropTarget == automation.steps.count
        return VStack(spacing: Space.xs) {
            Image(systemName: "square.and.arrow.down").font(.system(size: 18))
            Text(automation.steps.isEmpty
                 ? String(localized: "Drag an app or connector here for the first step")
                 : String(localized: "Drag here to add a step"))
                .bodyText()
        }
        .foregroundStyle(isTarget ? Palette.accent : Palette.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(RoundedRectangle(cornerRadius: Radius.medium).fill(isTarget ? Palette.accentTint : .clear))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium)
            .strokeBorder(isTarget ? Palette.accent : Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .dropDestination(for: String.self) { items, _ in drop(items, at: automation.steps.count) } isTargeted: {
            if $0 { dropTarget = automation.steps.count } else if dropTarget == automation.steps.count { dropTarget = nil }
        }
    }

    private func binding(for id: UUID) -> Binding<AutomationStep> {
        Binding(
            get: { automation.steps.first { $0.id == id } ?? AutomationStep(app: .anything, text: "") },
            set: { new in if let i = automation.steps.firstIndex(where: { $0.id == id }) { automation.steps[i] = new } }
        )
    }

    private func drop(_ items: [String], at index: Int) -> Bool {
        dropTarget = nil
        guard let item = items.first else { return false }
        return automation.drop(item, at: index)
    }

    private func add(_ app: AutomationApp, at index: Int) {
        automation.drop(Automation.dragItem(for: app), at: index)
    }
}

private struct StepCard: View {
    let number: Int
    @Binding var step: AutomationStep
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "line.3.horizontal").foregroundStyle(Palette.textTertiary).padding(.top, 10)
                .help(String(localized: "Drag to reorder"))
            AppIcon(app: step.app, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(step.app.title)").emphasisText().foregroundStyle(Palette.textPrimary)
                TextField(placeholder, text: $step.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1...6)
            }
            Spacer(minLength: 0)
            IconButton("xmark", help: String(localized: "Remove step"), action: remove).opacity(hovering ? 1 : 0)
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.medium).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(Palette.hairline))
        .onHover { hovering = $0 }
    }

    private var placeholder: String {
        switch step.app {
        case .mail: String(localized: "e.g. Find unread mail from today and summarise it")
        case .calendar: String(localized: "e.g. List today's meetings")
        case .reminders: String(localized: "e.g. Add a reminder to call Dana at 5pm")
        case .notes: String(localized: "e.g. Write everything above into a note called Daily brief")
        case .messages: String(localized: "e.g. Text Mom that I'm on my way")
        case .finder: String(localized: "e.g. Move screenshots on the Desktop into ~/Pictures/Screenshots")
        case .shortcuts: String(localized: "e.g. Run my \"Focus\" shortcut")
        case .terminal: String(localized: "e.g. Run brew upgrade")
        case .web: String(localized: "e.g. Find today's top tech news")
        case .connector(let name): String(localized: "What to do in \(name)")
        default: String(localized: "What to do, in plain words")
        }
    }
}

// MARK: - Trigger

private struct TriggerCard: View {
    @Binding var trigger: Automation.Trigger

    private enum Kind: String, CaseIterable { case manual, hourly, daily, weekdays, weekly }

    private var kind: Kind {
        switch trigger {
        case .manual: .manual
        case .schedule(.hourly): .hourly
        case .schedule(.daily): .daily
        case .schedule(.weekdays): .weekdays
        case .schedule(.weekly): .weekly
        }
    }

    private var hour: Int {
        switch trigger {
        case .schedule(.daily(let h, _)), .schedule(.weekdays(let h, _)), .schedule(.weekly(_, let h, _)): h
        default: 9
        }
    }

    private var minute: Int {
        switch trigger {
        case .schedule(.hourly(let m)), .schedule(.daily(_, let m)), .schedule(.weekdays(_, let m)),
             .schedule(.weekly(_, _, let m)): m
        default: 0
        }
    }

    private var weekday: Int { if case .schedule(.weekly(let d, _, _)) = trigger { d } else { 2 } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            MonoLabel(String(localized: "WHEN"))
            HStack(spacing: Space.m) {
                Image(systemName: kind == .manual ? "play.circle" : "clock")
                    .font(.system(size: 20)).foregroundStyle(Palette.accent)
                Picker("", selection: Binding(get: { kind }, set: { set($0, hour: hour, minute: minute, weekday: weekday) })) {
                    Text(String(localized: "When I press Run now")).tag(Kind.manual)
                    Text(String(localized: "Every hour")).tag(Kind.hourly)
                    Text(String(localized: "Every day")).tag(Kind.daily)
                    Text(String(localized: "Every weekday")).tag(Kind.weekdays)
                    Text(String(localized: "Every week")).tag(Kind.weekly)
                }
                .labelsHidden().fixedSize()
                if kind == .weekly {
                    Picker("", selection: Binding(get: { weekday }, set: { set(kind, hour: hour, minute: minute, weekday: $0) })) {
                        ForEach(1...7, id: \.self) { d in Text(Calendar.current.weekdaySymbols[d - 1]).tag(d) }
                    }
                    .labelsHidden().fixedSize()
                }
                if kind == .hourly {
                    Text(String(localized: "at minute")).bodyText().foregroundStyle(Palette.textSecondary)
                    Picker("", selection: Binding(get: { minute }, set: { set(kind, hour: hour, minute: $0, weekday: weekday) })) {
                        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: ":%02d", $0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                } else if kind != .manual {
                    Text(String(localized: "at")).bodyText().foregroundStyle(Palette.textSecondary)
                    DatePicker("", selection: Binding(get: { time }, set: { setTime($0) }), displayedComponents: .hourAndMinute)
                        .labelsHidden().fixedSize()
                }
                Spacer()
            }
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: Radius.medium).fill(Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(Palette.hairline))
        }
    }

    private var time: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    private func setTime(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        set(kind, hour: c.hour ?? 9, minute: c.minute ?? 0, weekday: weekday)
    }

    private func set(_ kind: Kind, hour: Int, minute: Int, weekday: Int) {
        trigger = switch kind {
        case .manual: .manual
        case .hourly: .schedule(.hourly(minute: minute))
        case .daily: .schedule(.daily(hour: hour, minute: minute))
        case .weekdays: .schedule(.weekdays(hour: hour, minute: minute))
        case .weekly: .schedule(.weekly(weekday: weekday, hour: hour, minute: minute))
        }
    }
}

// MARK: - Palette

/// The apps and connectors to drag in (or click to add at the end).
private struct AppPalette: View {
    let workspace: Workspace
    let add: (AutomationApp) -> Void

    private var connectors: [AutomationApp] {
        let items = (workspace.abilities.items[.connectors] ?? []) + (workspace.abilities.items[.mcps] ?? [])
        var seen = Set<String>()
        return items.filter { $0.enabled != false }.compactMap { item in
            seen.insert(item.title.lowercased()).inserted ? .connector(item.title) : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s) {
                MonoLabel(String(localized: "APPS"))
                grid(AutomationApp.builtIn)
                MonoLabel(String(localized: "CONNECTORS")).padding(.top, Space.s)
                if connectors.isEmpty {
                    Text(workspace.abilities.loading.isEmpty
                         ? String(localized: "None yet. Add them in Abilities.")
                         : String(localized: "Looking…"))
                        .captionText().foregroundStyle(Palette.textTertiary)
                } else {
                    grid(connectors)
                }
            }
            .padding(Space.m)
        }
        .scrollIndicators(.never)
        .background(Palette.sidebar.opacity(0.5))
    }

    private func grid(_ apps: [AutomationApp]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(apps, id: \.self) { app in
                PaletteTile(app: app) { add(app) }
                    .draggable(Automation.dragItem(for: app)) {
                        HStack { AppIcon(app: app, size: 22); Text(app.title).bodyText() }
                            .padding(Space.s)
                            .background(RoundedRectangle(cornerRadius: Radius.small).fill(Palette.raised))
                    }
            }
        }
    }
}

private struct PaletteTile: View {
    let app: AutomationApp
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xxs) {
                AppIcon(app: app, size: 32)
                Text(app.title).captionText().foregroundStyle(Palette.textSecondary).lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.small).fill(hovering ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(localized: "Drag into the steps, or click to add"))
    }
}

/// The app's own icon from disk; a symbol for connectors, Web and Anything.
struct AppIcon: View {
    let app: AutomationApp
    let size: CGFloat

    var body: some View {
        if let path = app.bundlePath, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().frame(width: size, height: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(Palette.textInverse)
                .frame(width: size * 0.84, height: size * 0.84)
                .background(RoundedRectangle(cornerRadius: size * 0.22).fill(tint))
                .frame(width: size, height: size)
        }
    }

    private var symbol: String {
        switch app {
        case .web: "globe"
        case .anything: "sparkles"
        default: "point.3.connected.trianglepath.dotted"
        }
    }

    private var tint: Color {
        switch app {
        case .web: Palette.running
        case .anything: Palette.accent
        default: Palette.success
        }
    }
}

// MARK: - History

private struct RunHistory: View {
    let workspace: Workspace
    let automationID: UUID

    var body: some View {
        let runs = workspace.runs(of: automationID)
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
                                Text(String(localized: "Failed")).captionText().foregroundStyle(Palette.failure)
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
