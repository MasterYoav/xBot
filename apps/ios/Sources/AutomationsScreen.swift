import SwiftUI
import XBotRemote

/// Automations, like the Mac's page: a trigger, steps in plain words, an agent that does them.
struct AutomationsScreen: View {
    let client: RemoteClient
    @State private var automations: [RemoteAutomation]?
    @State private var apps: [RemoteApp] = []
    @State private var runsWhileClosed = false
    @State private var path: [Route] = []

    enum Route: Hashable {
        case edit(UUID)
        case new
        case run(UUID, String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Toggle(isOn: Binding(get: { runsWhileClosed }, set: { on in Task { await setHelper(on) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Run while xBot is closed"))
                            Text(String(localized: "A small helper on the Mac starts them on time even when the app isn't open."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ForEach(automations ?? []) { automation in
                        NavigationLink(value: Route.edit(automation.id)) { AutomationRow(automation: automation, apps: apps) }
                            .swipeActions(edge: .leading) {
                                Button { Task { await run(automation) } } label: { Label(String(localized: "Run now"), systemImage: "play.fill") }
                                    .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await delete(automation) } } label: { Label(String(localized: "Delete"), systemImage: "trash") }
                            }
                            .contextMenu {
                                Button { Task { await run(automation) } } label: { Label(String(localized: "Run now"), systemImage: "play") }
                                Button { Task { await toggle(automation) } } label: {
                                    Label(automation.isEnabled ? String(localized: "Turn off") : String(localized: "Turn on"),
                                          systemImage: automation.isEnabled ? "pause.circle" : "checkmark.circle")
                                }
                                Button(role: .destructive) { Task { await delete(automation) } } label: { Label(String(localized: "Delete"), systemImage: "trash") }
                            }
                    }
                }
            }
            .overlay {
                if automations == nil { ProgressView() }
                else if automations?.isEmpty == true {
                    ContentUnavailableView {
                        Label(String(localized: "No automations yet"), systemImage: "bolt.horizontal")
                    } description: {
                        Text(String(localized: "Pick when, then say what to do in Mail, Calendar, Notes, your connectors and more. An agent on your Mac does it."))
                    } actions: {
                        Button(String(localized: "New automation")) { path.append(.new) }.buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 120)
                }
            }
            .refreshable { await load() }
            .closable()
            .navigationTitle(String(localized: "Automations"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(.new) } label: { Image(systemName: "plus") }
                        .accessibilityLabel(String(localized: "New automation"))
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .new:
                    AutomationEditor(client: client, apps: apps, original: nil) { list in apply(list) } ran: { id, title in path.append(.run(id, title)) }
                case .edit(let id):
                    if let automation = automations?.first(where: { $0.id == id }) {
                        AutomationEditor(client: client, apps: apps, original: automation) { list in apply(list) } ran: { id, title in path.append(.run(id, title)) }
                    }
                case .run(let chatID, let title):
                    ChatScreen(client: client, chatID: chatID, fallbackTitle: title)
                }
            }
        }
        .task { await load() }
        .task {
            // Runs finish on the Mac; keep the list fresh while it's on screen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if automations?.contains(where: { $0.runs.contains(where: \.isRunning) }) == true { await load(quiet: true) }
            }
        }
    }

    private func apply(_ answer: HostMessage?) {
        guard case .automations(_, let list, let palette, let helper) = answer else { return }
        automations = list
        apps = palette
        runsWhileClosed = helper
    }

    private func load(quiet: Bool = false) async {
        let answer = await client.call(quiet: quiet) { .listAutomations(requestID: $0) }
        if answer == nil, automations == nil { automations = [] }
        apply(answer)
    }

    private func run(_ automation: RemoteAutomation) async {
        let answer = await client.request { .runAutomation(requestID: $0, automationID: automation.id) }
        if answer.ok, let chat = answer.chatID {
            await load(quiet: true)
            path.append(.run(chat, automation.name))
        } else {
            client.notice = answer.reason
        }
    }

    private func toggle(_ automation: RemoteAutomation) async {
        var changed = automation
        changed.isEnabled.toggle()
        apply(await client.call { .saveAutomation(requestID: $0, automation: changed) })
    }

    private func delete(_ automation: RemoteAutomation) async {
        apply(await client.call { .deleteAutomation(requestID: $0, automationID: automation.id) })
    }

    private func setHelper(_ on: Bool) async {
        apply(await client.call { .setAutomationHelper(requestID: $0, on: on) })
    }
}

private struct AutomationRow: View {
    let automation: RemoteAutomation
    let apps: [RemoteApp]

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(automation.isEnabled ? 0.15 : 0.06)).frame(width: 36, height: 36)
                if automation.runs.first?.isRunning == true {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: automation.steps.first.map { StepApp.symbol($0.app) } ?? "bolt")
                        .foregroundStyle(automation.isEnabled ? Theme.accent : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(automation.name).font(.body.weight(.medium)).lineLimit(1)
                    .foregroundStyle(automation.isEnabled ? .primary : .secondary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if automation.runs.first?.failed == true {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel(String(localized: "Last run failed"))
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if !automation.isEnabled { return String(localized: "Off") }
        if automation.runs.first?.isRunning == true { return String(localized: "Running now…") }
        let when = ScheduleText.describe(automation.schedule)
        guard let next = automation.nextRun else { return when }
        return when + " · " + String(localized: "next \(next.formatted(.relative(presentation: .named)))")
    }
}

enum ScheduleText {
    static func describe(_ schedule: RemoteSchedule?) -> String {
        guard let schedule else { return String(localized: "When you run it") }
        switch schedule {
        case .hourly(let m): return String(localized: "Every hour at :\(String(format: "%02d", m))")
        case .daily(let h, let m): return String(localized: "Every day at \(time(h, m))")
        case .weekdays(let h, let m): return String(localized: "Weekdays at \(time(h, m))")
        case .weekly(let d, let h, let m):
            let day = Calendar.current.weekdaySymbols[max(0, min(6, d - 1))]
            return String(localized: "\(day)s at \(time(h, m))")
        }
    }

    static func time(_ hour: Int, _ minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

enum StepApp {
    static func symbol(_ key: String) -> String {
        if key.hasPrefix("connector:") { return "puzzlepiece.extension" }
        switch key {
        case "mail": return "envelope"
        case "calendar": return "calendar"
        case "reminders": return "checklist"
        case "notes": return "note.text"
        case "messages": return "message"
        case "contacts": return "person.crop.circle"
        case "finder": return "folder"
        case "safari": return "safari"
        case "music": return "music.note"
        case "photos": return "photo.on.rectangle"
        case "maps": return "map"
        case "shortcuts": return "square.stack.3d.up"
        case "terminal": return "terminal"
        case "web": return "globe"
        default: return "sparkles"
        }
    }

    static func prompt(_ app: RemoteApp?) -> String {
        guard let app else { return String(localized: "What to do") }
        if app.key == "anything" { return String(localized: "What to do") }
        return String(localized: "What to do in \(app.title)")
    }
}

/// Make or change one automation.
struct AutomationEditor: View {
    let client: RemoteClient
    let apps: [RemoteApp]
    let original: RemoteAutomation?
    let saved: (HostMessage?) -> Void
    let ran: (UUID, String) -> Void
    @State private var draft: RemoteAutomation
    @State private var saving = false
    @State private var deleting = false
    @State private var pickingStep = false
    @Environment(\.dismiss) private var dismiss

    enum When: String, CaseIterable, Identifiable {
        case manual, hourly, daily, weekdays, weekly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .manual: String(localized: "When I run it")
            case .hourly: String(localized: "Every hour")
            case .daily: String(localized: "Every day")
            case .weekdays: String(localized: "Weekdays")
            case .weekly: String(localized: "Once a week")
            }
        }
    }

    init(client: RemoteClient, apps: [RemoteApp], original: RemoteAutomation?, saved: @escaping (HostMessage?) -> Void,
         ran: @escaping (UUID, String) -> Void) {
        self.client = client
        self.apps = apps
        self.original = original
        self.saved = saved
        self.ran = ran
        _draft = State(initialValue: original ?? RemoteAutomation(
            name: String(localized: "New automation"), agent: client.agents.first?.id ?? "claude"))
    }

    private var when: When {
        switch draft.schedule {
        case nil: .manual
        case .hourly: .hourly
        case .daily: .daily
        case .weekdays: .weekdays
        case .weekly: .weekly
        }
    }

    private var hourMinute: (Int, Int) {
        switch draft.schedule {
        case .daily(let h, let m), .weekdays(let h, let m), .weekly(_, let h, let m): (h, m)
        case .hourly(let m): (9, m)
        case nil: (9, 0)
        }
    }

    private var changed: Bool { original.map { strip($0) != strip(draft) } ?? true }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Name"), text: $draft.name)
                    .font(.headline)
                Toggle(String(localized: "On"), isOn: $draft.isEnabled)
            }
            Section(String(localized: "When")) {
                Picker(String(localized: "Runs"), selection: Binding(get: { when }, set: { setWhen($0) })) {
                    ForEach(When.allCases) { Text($0.title).tag($0) }
                }
                if case .weekly(let day, _, _) = draft.schedule {
                    Picker(String(localized: "Day"), selection: Binding(get: { day }, set: { d in
                        let (h, m) = hourMinute
                        draft.schedule = .weekly(weekday: d, hour: h, minute: m)
                    })) {
                        ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                    }
                }
                if case .hourly(let minute) = draft.schedule {
                    Stepper(String(localized: "At :\(String(format: "%02d", minute)) past"), value: Binding(get: { minute }, set: { draft.schedule = .hourly(minute: $0) }), in: 0...59, step: 5)
                } else if draft.schedule != nil {
                    DatePicker(String(localized: "Time"), selection: Binding(get: { timeDate }, set: { setTime($0) }), displayedComponents: .hourAndMinute)
                }
            }
            Section {
                ForEach($draft.steps) { $step in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(app(step.app)?.title ?? step.app, systemImage: StepApp.symbol(step.app))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        TextField(StepApp.prompt(app(step.app)), text: $step.text, axis: .vertical)
                            .lineLimit(1...6)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { draft.steps.remove(atOffsets: $0) }
                .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                Button { pickingStep = true } label: {
                    Label(String(localized: "Add a step"), systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text(String(localized: "Steps"))
                    Spacer()
                    if draft.steps.count > 1 { EditButton().font(.footnote) }
                }
            } footer: {
                Text(String(localized: "Steps run in order, by an agent with full access on your Mac."))
            }
            Section(String(localized: "Agent")) {
                Picker(String(localized: "Agent"), selection: $draft.agent) {
                    ForEach(client.agents) { Text($0.name).tag($0.id) }
                }
                .onChange(of: draft.agent) { draft.model = nil; draft.effort = nil }
                if let agent = client.agent(draft.agent), !agent.models.isEmpty {
                    Picker(String(localized: "Model"), selection: $draft.model) {
                        Text(String(localized: "Default")).tag(String?.none)
                        ForEach(agent.models) { Text($0.name).tag(String?.some($0.id)) }
                    }
                }
                Picker(String(localized: "Reasoning"), selection: $draft.effort) {
                    Text(String(localized: "Default")).tag(String?.none)
                    ForEach(["low", "medium", "high"], id: \.self) { Text($0.capitalized).tag(String?.some($0)) }
                }
                Picker(String(localized: "Works in"), selection: $draft.projectID) {
                    Text(String(localized: "No project")).tag(UUID?.none)
                    ForEach(client.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            if let original, !original.runs.isEmpty {
                Section(String(localized: "Runs")) {
                    ForEach(original.runs) { run in
                        Button { ran(run.id, original.name) } label: {
                            HStack {
                                Image(systemName: run.isRunning ? "circle.dotted" : run.failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(run.isRunning ? Color.secondary : run.failed ? .red : .green)
                                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.primary)
                                Spacer()
                                Text(run.isRunning ? String(localized: "Running") : run.failed ? String(localized: "Failed") : String(localized: "Done"))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if original != nil {
                Section {
                    Button(String(localized: "Delete automation"), role: .destructive) { deleting = true }
                }
            }
        }
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button(String(localized: "Done")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) { Task { await save() } }
                    .disabled(saving || !changed)
            }
            ToolbarItem(placement: .bottomBar) {
                Button { Task { await saveAndRun() } } label: { Label(String(localized: "Run now"), systemImage: "play.fill") }
                    .disabled(saving || !draft.steps.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }
        .sheet(isPresented: $pickingStep) {
            StepPicker(apps: apps) { app in
                pickingStep = false
                addStep(app)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(String(localized: "Delete “\(draft.name)”?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(String(localized: "Delete"), role: .destructive) {
                Task {
                    saved(await client.call { .deleteAutomation(requestID: $0, automationID: draft.id) })
                    dismiss()
                }
            }
        } message: { Text(String(localized: "Its past runs stay in your chats.")) }
    }

    private func app(_ key: String) -> RemoteApp? { apps.first { $0.key == key } }

    private func addStep(_ app: RemoteApp) {
        draft.steps.append(RemoteStep(app: app.key, text: ""))
    }

    private var timeDate: Date {
        let (h, m) = hourMinute
        return Calendar.current.date(from: DateComponents(hour: h, minute: m)) ?? .now
    }

    private func setTime(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 9, m = c.minute ?? 0
        switch draft.schedule {
        case .daily: draft.schedule = .daily(hour: h, minute: m)
        case .weekdays: draft.schedule = .weekdays(hour: h, minute: m)
        case .weekly(let d, _, _): draft.schedule = .weekly(weekday: d, hour: h, minute: m)
        default: break
        }
    }

    private func setWhen(_ when: When) {
        let (h, m) = hourMinute
        switch when {
        case .manual: draft.schedule = nil
        case .hourly: draft.schedule = .hourly(minute: 0)
        case .daily: draft.schedule = .daily(hour: h, minute: m)
        case .weekdays: draft.schedule = .weekdays(hour: h, minute: m)
        case .weekly: draft.schedule = .weekly(weekday: Calendar.current.component(.weekday, from: .now), hour: h, minute: m)
        }
    }

    /// The parts the person edits (not what the Mac fills in).
    private func strip(_ a: RemoteAutomation) -> RemoteAutomation {
        var copy = a
        copy.nextRun = nil
        copy.lastRunAt = nil
        copy.runs = []
        return copy
    }

    @discardableResult
    private func save() async -> Bool {
        saving = true
        defer { saving = false }
        let answer = await client.call { .saveAutomation(requestID: $0, automation: draft) }
        guard case .automations(_, let list, _, _) = answer else { return false }
        saved(answer)
        if original == nil, list.contains(where: { $0.id == draft.id }) { dismiss() }
        return true
    }

    private func saveAndRun() async {
        if changed { guard await save() else { return } }
        let answer = await client.request { .runAutomation(requestID: $0, automationID: draft.id) }
        if answer.ok, let chat = answer.chatID {
            saved(await client.call(quiet: true) { .listAutomations(requestID: $0) })
            ran(chat, draft.name)
        } else {
            client.notice = answer.reason
        }
    }
}

/// The step palette: the Mac's apps, then its connectors, as tiles.
private struct StepPicker: View {
    let apps: [RemoteApp]
    let picked: (RemoteApp) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    grid(apps.filter { !$0.isConnector })
                    let connectors = apps.filter(\.isConnector)
                    if !connectors.isEmpty {
                        Text(String(localized: "Connectors")).font(.headline).padding(.horizontal, 4)
                        grid(connectors)
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "Add a step"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } } }
        }
    }

    private func grid(_ items: [RemoteApp]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { app in
                Button { picked(app) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: StepApp.symbol(app.key))
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(0.12)))
                        Text(app.title).font(.caption).foregroundStyle(.primary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.title)
            }
        }
    }
}
