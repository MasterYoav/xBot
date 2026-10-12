import Foundation
import Observation
import XBotBrain
import XBotRemote

/// How a phone is reached: directly on the local network, or through iCloud. Through iCloud, sends
/// are spaced further apart (each is a record write).
public enum RemoteLane: Sendable { case local, cloud }

/// One attached phone, as a transport presents it.
@MainActor public protocol RemoteLink: AnyObject {
    var id: UUID { get }
    var lane: RemoteLane { get }
    func send(_ messages: [HostMessage])
    var onReceive: ((ClientMessage) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
}

/**
 The Mac's side of xBot on the iPhone and iPad.

 Watches the workspace only while a phone is attached (none: no tracking, no work), and sends each
 phone what changed: the chat list as diffs, and for the chats it has open their messages and the
 reply being written, coalesced to a few sends a second. The phone's commands run through the
 same `Workspace` methods the Mac's own buttons call, so the two can't drift apart.
 */
@MainActor
public final class RemoteHost {
    public let macName: String
    public let macID: UUID
    /// Called with true while a phone is attached or a turn runs, false otherwise.
    public var keepAwake: ((Bool) -> Void)? { didSet { refreshAwake() } }
    /// Flushes so far (for the budget test).
    public private(set) var flushes = 0
    public var isWatching: Bool { watching }
    public var attachedCount: Int { clients.count }
    /// Bumped when a phone attaches or leaves, for Settings › Devices.
    public var onClientsChanged: (() -> Void)?

    let workspace: Workspace
    private let localInterval: Duration
    private let cloudInterval: Duration
    private var clients: [UUID: Client] = [:]
    private var watching = false
    private var flushTask: Task<Void, Never>?
    private var awake: Bool?
    /// Draws a crew member's sprite as PNG for phones; set by the app (the sprite lives in XBotUI).
    public var drawAvatar: (@MainActor (AgentAvatar) -> Data?)?
    var abilityCatalogOverride: AbilityCatalog?
    /// Brings back the last crew member a phone let go.
    var undoCrewDelete: (@MainActor () -> Void)?
    /// The last note a phone deleted: where it was, and where the Trash put it.
    var deletedNote: (projectID: UUID, from: URL, to: URL)?
    /// Chats deleted from a phone, so the phone can undo (the newest few).
    private var deleted: [DeletedChat] = []

    private final class Client {
        let link: any RemoteLink
        var opened: Set<UUID> = []
        var chats: [UUID: RemoteChat] = [:]
        var projects: [RemoteProject] = []
        var agents: [RemoteAgent] = []
        var messages: [UUID: [UUID: RemoteMessage]] = [:]
        var live: [UUID: [RemotePart]] = [:]
        var dirty = false
        var lastFlush = ContinuousClock.now - .seconds(60)
        init(_ link: any RemoteLink) { self.link = link }
    }

    public init(workspace: Workspace, macName: String, macID: UUID,
                localInterval: Duration = .milliseconds(100), cloudInterval: Duration = .seconds(1)) {
        self.workspace = workspace
        self.macName = macName
        self.macID = macID
        self.localInterval = localInterval
        self.cloudInterval = cloudInterval
    }

    // MARK: Phones

    public func attach(_ link: any RemoteLink) {
        let client = Client(link)
        clients[link.id] = client
        link.onReceive = { [weak self] in self?.handle($0, from: link.id) }
        link.onClose = { [weak self] in self?.detach(link.id) }
        let projects = remoteProjects(), chats = remoteChats(), agents = remoteAgents()
        client.projects = projects
        client.agents = agents
        for chat in chats { client.chats[chat.id] = chat }
        link.send([.hello(version: Wire.version, macName: macName, macID: macID),
                   .workspace(projects: projects, chats: chats, agents: agents)])
        client.lastFlush = .now
        startWatching()
        refreshAwake()
        onClientsChanged?()
    }

    public func detach(_ id: UUID) {
        guard clients.removeValue(forKey: id) != nil else { return }
        if clients.isEmpty {
            watching = false
            flushTask?.cancel()
            flushTask = nil
        }
        refreshAwake()
        onClientsChanged?()
    }

    /// Re-checks whether the Mac should stay awake (a turn may have ended since).
    public func refreshAwake() {
        let want = !clients.isEmpty || !workspace.turns.isEmpty
        guard want != awake else { return }
        awake = want
        keepAwake?(want)
    }

    // MARK: Watching

    /// One observation of everything a phone shows; re-armed after each change, dropped when the
    /// last phone leaves.
    private func startWatching() {
        guard !watching else { return }
        watching = true
        arm()
    }

    private func arm() {
        guard watching else { return }
        withObservationTracking {
            _ = workspace.chats
            _ = workspace.projects
            _ = workspace.live
            _ = workspace.turns.count
            _ = workspace.transcripts
            _ = workspace.modelOptions
            _ = workspace.availableHarnesses
            _ = workspace.agents
            _ = workspace.isDiscovering
        } onChange: { [weak self] in
            Task { @MainActor in self?.changed() }
        }
    }

    private func changed() {
        guard watching else { return }
        for client in clients.values { client.dirty = true }
        refreshAwake()
        scheduleFlush()
        arm()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let now = ContinuousClock.now
        let due = clients.values.filter(\.dirty).map { $0.lastFlush + interval($0) }.min()
        guard let due else { return }
        flushTask = Task { [weak self] in
            if due > now { try? await Task.sleep(until: due, clock: .continuous) }
            guard !Task.isCancelled else { return }
            self?.flushTask = nil
            self?.flushDue()
        }
    }

    private func interval(_ client: Client) -> Duration { client.link.lane == .cloud ? cloudInterval : localInterval }

    private func flushDue() {
        let now = ContinuousClock.now
        for client in clients.values where client.dirty && client.lastFlush + interval(client) <= now {
            flush(client)
        }
        if clients.values.contains(where: \.dirty) { scheduleFlush() }
    }

    private func flush(_ client: Client) {
        client.dirty = false
        client.lastFlush = .now
        flushes += 1
        var out: [HostMessage] = []

        let projects = remoteProjects(), agents = remoteAgents()
        let chats = remoteChats()
        if projects != client.projects {
            client.projects = projects
            client.chats = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
            out.append(.workspace(projects: projects, chats: chats, agents: agents))
        } else {
            let ids = Set(chats.map(\.id))
            for gone in client.chats.keys where !ids.contains(gone) {
                client.chats[gone] = nil
                out.append(.chatRemoved(gone))
            }
            for chat in chats where client.chats[chat.id] != chat {
                client.chats[chat.id] = chat
                out.append(.chat(chat))
            }
        }
        if agents != client.agents {
            client.agents = agents
            out.append(.agents(agents))
        }

        for chatID in client.opened {
            let messages = workspace.messages(in: chatID).map(Self.remote)
            var sent = client.messages[chatID] ?? [:]
            let ids = Set(messages.map(\.id))
            for gone in sent.keys where !ids.contains(gone) {
                sent[gone] = nil
                out.append(.messageRemoved(chatID: chatID, messageID: gone))
            }
            for message in messages where sent[message.id] != message {
                sent[message.id] = message
                out.append(.message(chatID: chatID, message: message))
            }
            client.messages[chatID] = sent
            let live = (workspace.live[chatID] ?? []).map(Self.remote)
            if live != client.live[chatID] ?? [] {
                client.live[chatID] = live
                out.append(.live(chatID: chatID, parts: live))
            }
        }
        if !out.isEmpty { client.link.send(out) }
    }

    // MARK: Commands

    private func handle(_ message: ClientMessage, from id: UUID) {
        guard let client = clients[id] else { return }
        switch message {
        case .hello, .away:
            break
        case .open(let chatID):
            guard workspace.chat(chatID) != nil else { return }
            workspace.loadTranscript(chatID)
            client.opened.insert(chatID)
            let messages = workspace.messages(in: chatID).map(Self.remote)
            client.messages[chatID] = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
            let live = (workspace.live[chatID] ?? []).map(Self.remote)
            client.live[chatID] = live
            var out: [HostMessage] = [.transcript(chatID: chatID, messages: messages)]
            if !live.isEmpty { out.append(.live(chatID: chatID, parts: live)) }
            client.link.send(out)
        case .close(let chatID):
            client.opened.remove(chatID)
            client.messages[chatID] = nil
            client.live[chatID] = nil
        case .send(let request, let chatID, let text):
            guard let chat = workspace.chat(chatID) else { return answer(client, request, refused: notFound) }
            if workspace.isRunning(chatID) { return answer(client, request, refused: String(localized: "It's still answering.")) }
            if let reason = workspace.sendBlockedReason(chatID) { return answer(client, request, refused: reason) }
            answer(client, request, workspace.send(text, in: chat.id), chatID: chatID)
        case .newChat(let request, let projectID, let text, let settings):
            if let projectID, !workspace.projects.contains(where: { $0.id == projectID }) {
                return answer(client, request, refused: String(localized: "That project isn't on the Mac any more."))
            }
            guard let chat = workspace.newBackgroundChat(in: projectID) else {
                return answer(client, request, refused: String(localized: "No agent is installed on the Mac."))
            }
            if let reason = apply(settings, to: chat.id) {
                _ = workspace.deleteChat(chat.id)
                return answer(client, request, refused: reason)
            }
            answer(client, request, workspace.send(text, in: chat.id), chatID: chat.id)
        case .stop(let request, let chatID):
            guard workspace.chat(chatID) != nil else { return answer(client, request, refused: notFound) }
            workspace.stop(chatID)
            answer(client, request, true, chatID: chatID)
        case .edit(let request, let chatID, let messageID, let text):
            guard workspace.chat(chatID) != nil else { return answer(client, request, refused: notFound) }
            answer(client, request, workspace.resend(messageID, as: text, in: chatID), chatID: chatID)
        case .runPlan(let request, let chatID, let messageID):
            guard let latest = workspace.latestPlan(in: chatID), latest.messageID == messageID else {
                return answer(client, request, refused: String(localized: "That plan has changed on the Mac."))
            }
            answer(client, request, workspace.runPlan(messageID, in: chatID, steps: latest.plan.steps), chatID: chatID)
        case .cancelPlan(let request, let chatID, let messageID):
            workspace.cancelPlan(messageID, in: chatID)
            answer(client, request, true, chatID: chatID)
        case .rename(let request, let chatID, let title):
            guard workspace.chat(chatID) != nil else { return answer(client, request, refused: notFound) }
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return answer(client, request, refused: String(localized: "A chat needs a name."))
            }
            workspace.rename(chatID, to: title)
            answer(client, request, true, chatID: chatID)
        case .retry(let request, let chatID):
            guard workspace.chat(chatID) != nil else { return answer(client, request, refused: notFound) }
            if workspace.isRunning(chatID) { return answer(client, request, refused: String(localized: "It's still answering.")) }
            if let reason = workspace.sendBlockedReason(chatID) { return answer(client, request, refused: reason) }
            workspace.loadTranscript(chatID)
            answer(client, request, workspace.retryLast(in: chatID), chatID: chatID)
        case .delete(let request, let chatID):
            workspace.loadTranscript(chatID)
            guard let gone = workspace.deleteChat(chatID) else { return answer(client, request, refused: notFound) }
            deleted.append(gone)
            if deleted.count > 5 { deleted.removeFirst() }
            answer(client, request, true, chatID: chatID)
        case .undoDelete(let request, let chatID):
            guard let index = deleted.lastIndex(where: { $0.chat.id == chatID }) else {
                return answer(client, request, refused: String(localized: "That chat can't be brought back any more."))
            }
            workspace.restoreChat(deleted.remove(at: index))
            answer(client, request, workspace.chat(chatID) != nil, chatID: chatID)
        case .listFolder, .readFile, .gitStatus, .gitDiff, .gitAction, .fileAction, .browseMac, .addProject, .removeProject,
             .listNotes, .saveNote, .deleteNote, .undoDeleteNote,
             .listAutomations, .saveAutomation, .deleteAutomation, .runAutomation, .setAutomationHelper,
             .listCrew, .saveCrew, .deleteCrew, .undoDeleteCrew, .talkTo, .drawAvatar,
             .listAbilities, .setAbility, .removeAbility, .listPlugins, .installPlugin, .addMCP:
            handleProject(message, link: client.link)
        case .setChat(let request, let chatID, let settings):
            guard workspace.chat(chatID) != nil else { return answer(client, request, refused: notFound) }
            if let reason = apply(settings, to: chatID) { return answer(client, request, refused: reason) }
            answer(client, request, true, chatID: chatID)
        }
    }

    private var notFound: String { String(localized: "That chat isn't on the Mac any more.") }

    /// Applies a phone's settings; the reason it can't, or nil.
    private func apply(_ settings: RemoteChatSettings, to chatID: UUID) -> String? {
        if let raw = settings.agent {
            guard let kind = HarnessKind(rawValue: raw) else { return String(localized: "Unknown agent.") }
            guard workspace.availableHarnesses.contains(kind) else {
                return String(localized: "\(kind.displayName) isn't installed on the Mac.")
            }
            workspace.setHarness(kind, for: chatID)
        }
        if let model = settings.model { workspace.setModel(model.value, for: chatID) }
        if let raw = settings.mode {
            guard let mode = PermissionMode(rawValue: raw) else { return String(localized: "Unknown permission.") }
            workspace.setMode(mode, for: chatID)
        }
        if let effort = settings.effort {
            if let raw = effort.value, Effort(rawValue: raw) == nil { return String(localized: "Unknown effort.") }
            workspace.setEffort(effort.value.flatMap(Effort.init(rawValue:)), for: chatID)
        }
        if let plan = settings.planMode { workspace.setPlanMode(plan, for: chatID) }
        return nil
    }

    private func answer(_ client: Client, _ request: UUID, _ ok: Bool, chatID: UUID? = nil) {
        client.link.send([.reply(requestID: request, ok: ok,
                                 reason: ok ? nil : String(localized: "The Mac couldn't do that right now."), chatID: chatID)])
    }

    private func answer(_ client: Client, _ request: UUID, refused reason: String) {
        client.link.send([.reply(requestID: request, ok: false, reason: reason, chatID: nil)])
    }

    // MARK: Mapping

    private func remoteProjects() -> [RemoteProject] { workspace.projects.map { RemoteProject(id: $0.id, name: $0.name, path: $0.path) } }

    private func remoteChats() -> [RemoteChat] {
        workspace.chats.filter { $0.automationID == nil }.map { chat in
            RemoteChat(id: chat.id, title: chat.title, projectID: chat.projectID, agent: chat.harness.rawValue,
                       agentName: chat.harness.displayName, model: chat.model, mode: chat.mode.rawValue,
                       effort: chat.effort?.rawValue, planMode: chat.planMode, crewName: workspace.agent(chat.agentID)?.name,
                       updatedAt: chat.updatedAt, isRunning: workspace.isRunning(chat.id),
                       blocked: workspace.isDiscovering ? nil : workspace.sendBlockedReason(chat.id))
        }
    }

    private func remoteAgents() -> [RemoteAgent] {
        workspace.availableHarnesses.map { kind in
            RemoteAgent(id: kind.rawValue, name: kind.displayName,
                        models: workspace.models(for: kind).map { .init(id: $0.id, name: $0.name, efforts: $0.efforts.map(\.rawValue)) },
                        makesPlans: kind.givesStructuredAnswers, editingNeedsFullAccess: kind.editingNeedsFullAccess)
        }
    }

    static func remote(_ message: ChatMessage) -> RemoteMessage {
        RemoteMessage(id: message.id, role: message.role.rawValue, parts: message.parts.map(remote), createdAt: message.createdAt)
    }

    static func remote(_ part: Part) -> RemotePart {
        switch part {
        case .text(let text): .text(text)
        case .notice(let text): .notice(text)
        case .failure(let text): .failure(text)
        case .tool(let tool): .tool(remote(tool))
        case .plan(let plan):
            .plan(RemotePlan(status: plan.status.rawValue, summary: plan.summary, note: plan.note,
                             steps: plan.steps.map { RemotePlanStep(id: $0.id, title: $0.title, status: $0.status.rawValue) },
                             problem: plan.problem, closing: plan.closing))
        }
    }

    static func remote(_ tool: ToolPart) -> RemoteTool {
        RemoteTool(id: tool.id, label: ToolLabel.verb(tool.name, running: tool.output == nil), summary: tool.summary,
                   isDone: tool.output != nil, isError: tool.isError, size: tool.size)
    }
}

extension Workspace {
    /// Reads a chat's saved messages without opening it on the Mac (a phone opened it).
    func loadTranscript(_ id: UUID) {
        if transcripts[id] == nil { transcripts[id] = attempt { try store.messages(in: id) } ?? [] }
    }

    /// A chat a phone started: like `newChat`, but the Mac's window stays where it is.
    func newBackgroundChat(in projectID: UUID?) -> Chat? {
        let recent = chats.first.map(\.harness).flatMap { brains[$0] == nil ? nil : $0 }
        guard let harness = recent ?? availableHarnesses.first else { return nil }
        let chat = Chat(projectID: projectID, title: String(localized: "New chat"), harness: harness, mode: .editFiles)
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        return chat
    }
}
