import Foundation
import Observation
import XBotBrain

/// Projects, chats, and the turns running in them. The one object the window talks to.
@MainActor
@Observable
public final class Workspace {
    public private(set) var projects: [Project] = []
    public internal(set) var chats: [Chat] = []
    public private(set) var openChatIDs: [UUID] = []
    public var selectedChatID: UUID?
    /// The reply being written right now, per chat. Saved as a message when the turn ends.
    public private(set) var live: [UUID: [Part]] = [:]
    /// True until the installed CLIs have been looked for. Nothing claims one is missing before then.
    public private(set) var isDiscovering = true
    /// Set when xBot cannot save, so the window can say so instead of pretending.
    public var problem: String?

    /// Small messages at the bottom of the window.
    public let toasts = ToastCenter()
    /// What Home's composer holds before a chat exists.
    public var draft = ChatDraft()
    /// Bumped to ask the sidebar's search field for focus (⌘K).
    public internal(set) var searchFocusRequest = 0
    /// Bumped to ask the composer for focus (a suggestion was chosen).
    public internal(set) var composerFocusRequest = 0

    var brains: [HarnessKind: any Brain] = [:]
    var transcripts: [UUID: [ChatMessage]] = [:]
    /// The running turn per chat. The token is how a turn's own task recognises it: a stopped
    /// turn's task unwinds after the next one may have started, and must leave that one alone.
    var turns: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    let store: Store
    /// Chat → the message holding its plan, while a plan turn runs.
    var planTurns: [UUID: UUID] = [:]
    private let inbox: URL
    private let discover: @Sendable () async -> [HarnessKind: any Brain]

    public init(
        store: Store,
        inbox: URL,
        discover: @escaping @Sendable () async -> [HarnessKind: any Brain]
    ) {
        self.store = store
        self.inbox = inbox
        self.discover = discover
        projects = attempt { try store.projects() } ?? []
        chats = attempt { try store.chats() } ?? []
    }

    public var availableHarnesses: [HarnessKind] { HarnessKind.allCases.filter { brains[$0] != nil } }

    public func refreshHarnesses() async {
        isDiscovering = true
        brains = await discover()
        isDiscovering = false
    }

    public func chat(_ id: UUID) -> Chat? { chats.first { $0.id == id } }

    public func messages(in id: UUID) -> [ChatMessage] { transcripts[id] ?? [] }

    public func isRunning(_ id: UUID) -> Bool { turns[id] != nil }

    /// Why the composer cannot send, in a sentence, or nil when it can. A running turn is not a
    /// reason: the composer shows Stop instead.
    public func sendBlockedReason(_ id: UUID) -> String? {
        guard let chat = chat(id) else { return nil }
        if brains[chat.harness] == nil, isDiscovering {
            return String(localized: "Looking for \(chat.harness.displayName)…")
        }
        if brains[chat.harness] == nil {
            return String(localized: "\(chat.harness.displayName) isn't installed on this Mac any more.")
        }
        return nil
    }

    // MARK: Projects

    @discardableResult
    public func addProject(at url: URL) -> Project {
        let path = url.standardizedFileURL.path(percentEncoded: false)
            .trimmingSuffix("/")
        if let existing = projects.first(where: { $0.path == path }) { return existing }
        let project = Project(name: URL(filePath: path).lastPathComponent, path: path)
        attempt { try store.save(project) }
        projects = attempt { try store.projects() } ?? projects + [project]
        return project
    }

    /// Forgets the project and its chats. The folder itself is not touched.
    public func removeProject(_ id: UUID) {
        for chat in chats where chat.projectID == id { stop(chat.id); forget(chat.id) }
        attempt { try store.deleteProject(id) }
        projects.removeAll { $0.id == id }
        chats.removeAll { $0.projectID == id }
    }

    // MARK: Chats

    /// A new chat with the harness used most recently, or nil when no harness is installed.
    @discardableResult
    public func newChat(in projectID: UUID?) -> Chat? {
        let recent = chats.first.map(\.harness).flatMap { brains[$0] == nil ? nil : $0 }
        guard let harness = recent ?? availableHarnesses.first else { return nil }
        let chat = Chat(projectID: projectID, title: String(localized: "New chat"), harness: harness, mode: .editFiles)
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        open(chat.id)
        return chat
    }

    public func open(_ id: UUID) {
        if transcripts[id] == nil { transcripts[id] = attempt { try store.messages(in: id) } ?? [] }
        if !openChatIDs.contains(id) { openChatIDs.append(id) }
        selectedChatID = id
    }

    /// Closes the tab. A running turn keeps going; the chat is still in the sidebar.
    public func close(_ id: UUID) {
        guard let index = openChatIDs.firstIndex(of: id) else { return }
        openChatIDs.remove(at: index)
        if selectedChatID == id {
            selectedChatID = openChatIDs.indices.contains(index) ? openChatIDs[index] : openChatIDs.last
        }
    }

    public func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed }
    }

    /// Removes the chat and its messages, and returns them so the removal can be undone.
    @discardableResult
    public func deleteChat(_ id: UUID) -> DeletedChat? {
        guard let chat = chat(id) else { return nil }
        stop(id)
        let messages = transcripts[id] ?? attempt { try store.messages(in: id) } ?? []
        let wasOpen = openChatIDs.contains(id)
        attempt { try store.deleteChat(id) }
        chats.removeAll { $0.id == id }
        forget(id)
        return DeletedChat(chat: chat, messages: messages, wasOpen: wasOpen)
    }

    public func setHarness(_ kind: HarnessKind, for id: UUID) {
        // A session id means nothing to a different CLI, and neither does its model name.
        update(id) { $0.harness = kind; $0.sessionID = nil; $0.model = nil }
    }

    public func setModel(_ model: String?, for id: UUID) { update(id) { $0.model = model } }

    public func setMode(_ mode: PermissionMode, for id: UUID) { update(id) { $0.mode = mode } }

    // MARK: Turns

    /// Starts a turn. False, with nothing changed, when the chat is busy or cannot send — so the
    /// composer keeps what was typed.
    @discardableResult
    public func send(_ text: String, in id: UUID) -> Bool {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning(id), var chat = chat(id), let brain = brains[chat.harness] else {
            return false
        }

        save(ChatMessage(chatID: id, role: .user, parts: [.text(prompt)]))
        if chat.title == String(localized: "New chat") { chat.title = Self.title(from: prompt) }
        chat.updatedAt = .now
        replace(chat)

        if chat.planMode {
            startPlanning(prompt, chat: chat, brain: brain)
            return true
        }

        let request = TurnRequest(
            prompt: prompt, directory: directory(for: chat), model: chat.model,
            mode: chat.mode, resumeID: chat.sessionID
        )
        live[id] = []
        launch(id) { workspace, token in
            for await event in brain.run(request) {
                workspace.receive(event, in: id, turn: token)
            }
        }
        return true
    }

    /// Runs `body` as the chat's turn. The token is how the body's own steps recognise it is still
    /// the current turn after it awaits.
    func launch(_ id: UUID, _ body: @escaping @MainActor (Workspace, UUID) async -> Void) {
        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await body(self, token)
            self.end(id, turn: token, stopped: false)
        }
        turns[id] = (token, task)
    }

    public func stop(_ id: UUID) {
        guard let turn = turns[id] else { return }
        end(id, turn: turn.token, stopped: true)
        turn.task.cancel()
    }

    /// Saves every reply in progress and stops its CLI. Called when the app quits.
    public func stopAll() {
        for id in Array(turns.keys) { stop(id) }
    }

    public static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 48 ? String(trimmed.prefix(48)) + "…" : trimmed
    }

    // MARK: Private

    private func receive(_ event: BrainEvent, in id: UUID, turn token: UUID) {
        guard turns[id]?.token == token else { return }
        if case .session(let session) = event {
            update(id) { $0.sessionID = session }
            return
        }
        live[id, default: []].apply(event)
    }

    /// Ends a turn once: whichever of stop and the stream finishing comes first saves the reply.
    func end(_ id: UUID, turn token: UUID, stopped: Bool) {
        guard turns[id]?.token == token else { return }
        turns[id] = nil
        if let messageID = planTurns.removeValue(forKey: id) {
            if stopped { haltPlan(messageID, in: id) }
            update(id) { $0.updatedAt = .now }
            return
        }
        // A tool with no result when the turn ends never finished; saved as running, it would spin
        // in the transcript forever.
        var parts = (live.removeValue(forKey: id) ?? []).map { part in
            guard case .tool(var tool) = part, tool.output == nil else { return part }
            tool.output = ""
            tool.isError = true
            return .tool(tool)
        }
        if stopped { parts.append(.notice(String(localized: "Stopped."))) }
        if !parts.isEmpty { save(ChatMessage(chatID: id, role: .assistant, parts: parts)) }
        update(id) { $0.updatedAt = .now }
    }

    func directory(for chat: Chat) -> URL {
        if let projectID = chat.projectID, let project = projects.first(where: { $0.id == projectID }) {
            return project.url
        }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    func save(_ message: ChatMessage) {
        attempt { try store.append(message) }
        transcripts[message.chatID, default: []].append(message)
    }

    func update(_ id: UUID, _ change: (inout Chat) -> Void) {
        guard var chat = chat(id) else { return }
        change(&chat)
        replace(chat)
    }

    private func replace(_ chat: Chat) {
        attempt { try store.save(chat) }
        if let index = chats.firstIndex(where: { $0.id == chat.id }) { chats[index] = chat }
        chats.sort { $0.updatedAt > $1.updatedAt }
    }

    private func forget(_ id: UUID) {
        transcripts[id] = nil
        close(id)
    }

    /// Runs a store call; a failure becomes `problem` rather than a crash or a silent loss.
    @discardableResult
    func attempt<T>(_ body: () throws -> T) -> T? {
        do { return try body() } catch {
            problem = String(localized: "xBot couldn't save to its library: \(String(describing: error))")
            return nil
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        count > 1 && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
