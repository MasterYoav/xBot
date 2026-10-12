import SwiftUI
import XBotRemote

/// The Mac's Jev workflows: listed, with Run now. They're built on the Mac (Workflows); a run is
/// a chat there, opened here as it goes.
struct WorkflowsScreen: View {
    let client: RemoteClient
    @State private var workflows: [RemoteWorkflow]?
    @State private var available = true
    @State private var path: [Route] = []

    enum Route: Hashable {
        case run(UUID, String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(workflows ?? []) { workflow in
                    Section {
                        WorkflowRow(workflow: workflow)
                        if let blocked = workflow.blocked {
                            Text(blocked).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button { Task { await run(workflow) } } label: {
                            Label(String(localized: "Run now"), systemImage: "play.fill")
                        }
                        .disabled(workflow.blocked != nil || workflow.runs.first?.isRunning == true)
                        ForEach(workflow.runs.prefix(3)) { run in
                            NavigationLink(value: Route.run(run.id, workflow.name)) {
                                Label(run.startedAt.formatted(date: .abbreviated, time: .shortened),
                                      systemImage: run.isRunning ? "circle.dotted" : run.failed ? "exclamationmark.triangle" : "checkmark.circle")
                                    .foregroundStyle(run.failed ? .orange : .primary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if workflows == nil { ProgressView() }
                else if !available {
                    ContentUnavailableView {
                        Label(String(localized: "Workflows are off"), systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text(String(localized: "Turn on Jev Workflows in xBot's Settings › AI on your Mac."))
                    }
                    .padding(.top, 120)
                } else if workflows?.isEmpty == true {
                    ContentUnavailableView {
                        Label(String(localized: "No workflows yet"), systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text(String(localized: "Build one on your Mac, under Workflows: agent steps, and Jev steps that decide between them."))
                    }
                    .padding(.top, 120)
                }
            }
            .refreshable { await load() }
            .closable()
            .navigationTitle(String(localized: "Workflows"))
            .navigationDestination(for: Route.self) { route in
                switch route {
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
                if workflows?.contains(where: { $0.runs.contains(where: \.isRunning) }) == true { await load(quiet: true) }
            }
        }
    }

    private func load(quiet: Bool = false) async {
        let answer = await client.call(quiet: quiet) { .listWorkflows(requestID: $0) }
        guard case .workflows(_, let list, let on) = answer else {
            if workflows == nil { workflows = [] }
            return
        }
        workflows = list
        available = on
    }

    private func run(_ workflow: RemoteWorkflow) async {
        let answer = await client.request { .runWorkflow(requestID: $0, workflowID: workflow.id, input: nil) }
        if answer.ok, let chat = answer.chatID {
            await load(quiet: true)
            path.append(.run(chat, workflow.name))
        } else {
            client.notice = answer.reason
        }
    }
}

private struct WorkflowRow: View {
    let workflow: RemoteWorkflow

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color.purple.opacity(workflow.isEnabled ? 0.15 : 0.06)).frame(width: 36, height: 36)
                if workflow.runs.first?.isRunning == true {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(workflow.isEnabled ? Color.purple : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name).font(.body.weight(.medium)).lineLimit(1)
                    .foregroundStyle(workflow.isEnabled ? .primary : .secondary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let steps = workflow.stepTitles.joined(separator: " → ")
        if workflow.runs.first?.isRunning == true { return String(localized: "Running now…") }
        let when = ScheduleText.describe(workflow.schedule)
        let next = workflow.isEnabled ? workflow.nextRun.map { " · " + String(localized: "next \($0.formatted(.relative(presentation: .named)))") } ?? "" : ""
        return steps.isEmpty ? when + next : when + next + "\n" + steps
    }
}
