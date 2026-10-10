import Foundation

/// Home's composer before a chat exists: the text and the settings the chat will start with.
public struct ChatDraft: Equatable, Sendable {
    public var text = ""
    public var projectID: UUID?
    /// Nil: the agent used most recently.
    public var harness: HarnessKind?
    public var model: String?
    public var mode: PermissionMode = .editFiles
    public var planMode = false
    public var reviewPlan = true
    /// Nil: the agent's own default.
    public var effort: Effort?

    public init() {}
}

/// A deleted chat, kept so Undo can put it back.
public struct DeletedChat: Sendable {
    public let chat: Chat
    public let messages: [ChatMessage]
    public let wasOpen: Bool
}

extension Workspace {
    public var isHome: Bool { selectedChatID == nil }

    public var runningChatIDs: Set<UUID> { Set(turns.keys) }

    public func goHome() {
        selectedChatID = nil
        page = .main
    }

    /// A new chat, aimed at a project (nil: the Inbox): the composer on its own, in a tab of its own.
    public func startDraft(in projectID: UUID?) {
        draft.projectID = projectID
        goHome()
        composerFocusRequest += 1
    }

    public func requestSearchFocus() { searchFocusRequest += 1 }

    /// ⌘1…⌘9: the open tab at that position; nothing when there is none.
    public func openTab(at index: Int) {
        guard openChatIDs.indices.contains(index) else { return }
        open(openChatIDs[index])
    }

    /// The agent a new chat would use: the draft's choice if installed, else the most recent, else
    /// the first found.
    public var draftHarness: HarnessKind? {
        let installed = { (kind: HarnessKind?) in kind.flatMap { self.brains[$0] == nil ? nil : $0 } }
        return installed(draft.harness) ?? installed(chats.first?.harness) ?? availableHarnesses.first
    }

    /// Turns Home's draft into a chat and sends it. False, with the draft untouched, when there is
    /// nothing to send or no agent to send it to.
    @discardableResult
    public func sendDraft() -> Bool {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let harness = draftHarness else { return false }
        // A project removed since the draft was aimed at it: the Inbox, rather than a failed send.
        let projectID = draft.projectID.flatMap { id in projects.contains { $0.id == id } ? id : nil }
        let chat = Chat(
            projectID: projectID, title: String(localized: "New chat"), harness: harness,
            model: draft.harness == harness ? draft.model : nil, mode: draft.mode,
            planMode: draft.planMode, reviewPlan: draft.reviewPlan, effort: draft.effort
        )
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        open(chat.id)
        guard send(text, in: chat.id) else { return false }
        draft.text = ""
        // The next chat starts from the person's defaults, not from this one's choices.
        applyDraftDefaults()
        return true
    }

    public func branch(for projectID: UUID?) -> String? {
        projectID.flatMap { id in projects.first { $0.id == id } }.flatMap { GitBranch.current(in: $0.url) }
    }

    /// How long the agent worked on a reply: from the question before it to the reply.
    public func workedFor(_ messageID: UUID, in chatID: UUID) -> TimeInterval? {
        let list = messages(in: chatID)
        guard let index = list.firstIndex(where: { $0.id == messageID }), list[index].role == .assistant,
              let asked = list[..<index].last(where: { $0.role == .user }) else { return nil }
        return list[index].createdAt.timeIntervalSince(asked.createdAt)
    }

    /// Asks the chat's last question again.
    @discardableResult
    public func retryLast(in id: UUID) -> Bool {
        guard let question = messages(in: id).last(where: { $0.role == .user }) else { return false }
        let text = question.parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
        return send(text, in: id)
    }

    public func restoreChat(_ deleted: DeletedChat) {
        guard chat(deleted.chat.id) == nil else { return }
        var chat = deleted.chat
        if let projectID = chat.projectID, !projects.contains(where: { $0.id == projectID }) { chat.projectID = nil }
        attempt {
            try store.save(chat)
            for message in deleted.messages { try store.append(message) }
        }
        chats.append(chat)
        chats.sort { $0.updatedAt > $1.updatedAt }
        transcripts[chat.id] = deleted.messages
        if deleted.wasOpen { open(chat.id) }
    }

    /// Deletes at once and offers Undo, instead of asking first.
    public func deleteChatWithUndo(_ id: UUID) {
        guard let deleted = deleteChat(id) else { return }
        toasts.show(
            String(localized: "Chat deleted"), systemImage: "trash",
            action: .init(title: String(localized: "Undo")) { [weak self] in self?.restoreChat(deleted) }
        )
    }
}

extension Workspace {
    /// The project the window is about: the open chat's, or Home's draft's.
    public var contextProject: Project? {
        let id = selectedChatID.flatMap { chat($0)?.projectID } ?? (isHome ? draft.projectID : nil)
        return id.flatMap { id in projects.first { $0.id == id } }
    }
}
