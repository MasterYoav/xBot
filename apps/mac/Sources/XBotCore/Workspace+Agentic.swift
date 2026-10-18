import Foundation
import XBotBrain

/// Agentic Mode in the workspace: approval cards in the conversation, and xBot's tools on a turn.
extension Workspace {
    static let toolsEverywhereKey = "agentic.toolsEverywhere"

    /// Settings › Agents › "xBot tools in every chat": off, they're on thread turns only.
    public var toolsInEveryChat: Bool {
        get { defaults.bool(forKey: Self.toolsEverywhereKey) }
        set { defaults.set(newValue, forKey: Self.toolsEverywhereKey) }
    }

    /// An approval is a card in its chat, from the agent; answered, the same card shows the answer.
    func wireApprovals() {
        approvals.post = { [weak self] approval, chatID in self?.post([.approval(approval)], in: chatID) }
        approvals.update = { [weak self] approval, chatID in self?.rewrite(approval, in: chatID) }
    }

    /// A message from the agent outside its reply: a card, a screenshot, a lesson, a question. Saved
    /// at once (the reply being written is saved when its turn ends).
    @discardableResult
    func post(_ parts: [Part], in chatID: UUID) -> ChatMessage? {
        guard chat(chatID) != nil else { return nil }
        // Loaded first: a chat whose messages were never read would otherwise show only this one.
        if transcripts[chatID] == nil { transcripts[chatID] = attempt { try store.messages(in: chatID) } ?? [] }
        let message = ChatMessage(chatID: chatID, role: .assistant, parts: parts)
        save(message)
        return message
    }

    /// The approval card, rewritten with its answer, in memory and in the library.
    func rewrite(_ approval: ApprovalPart, in chatID: UUID) {
        if transcripts[chatID] == nil { transcripts[chatID] = attempt { try store.messages(in: chatID) } ?? [] }
        guard var messages = transcripts[chatID] else { return }
        for index in messages.indices.reversed() {
            guard let part = messages[index].parts.firstIndex(where: {
                if case .approval(let card) = $0 { card.id == approval.id } else { false }
            }) else { continue }
            messages[index].parts[part] = .approval(approval)
            attempt { try store.replace(messages[index]) }
            transcripts[chatID] = messages
            return
        }
    }

    /// The person's answer to an approval card on the Mac.
    public func answerApproval(_ id: UUID, allow: Bool) {
        approvals.answer(id, allow: allow, by: String(localized: "Mac"))
    }

    /// Whether an agent in this chat is waiting on the person's reply (`xbot_ask`): the composer
    /// sends even while its turn runs.
    public func isAsking(in chatID: UUID) -> Bool { questions.isWaiting(in: chatID) }

    /// Gives a thread's turn (or any turn, with "xBot tools in every chat") xBot's tools: the
    /// server and a token, full access for a thread, and the tools' guidance after who the agent
    /// is. Returns the work to do before an Antigravity turn starts (its server is added once).
    func attachTools(to request: inout TurnRequest, for chat: Chat) -> (@MainActor () async -> Void)? {
        guard let host = toolHost, chat.isThread || toolsInEveryChat else { return nil }
        let tools = host.open(chatID: chat.id, agentID: chat.agentID)
        toolTokens[chat.id] = tools.token
        request.tools = tools
        if chat.isThread { request.mode = .fullAccess }
        request.instructions = (request.instructions.map { $0 + "\n\n" } ?? "") + Self.toolGuidance
        guard chat.harness == .antigravity, let agy = brains[.antigravity] as? HarnessBrain else { return nil }
        return { await host.antigravity.ensureInstalled(agy: agy.executable, xbot: host.executable, environment: agy.environment) }
    }

    #if DEBUG
    /// Debug builds' end-to-end check (`XBOT_DEBUG_AGENTIC_PROMPT`) makes a chat a thread without
    /// the thread machinery.
    public func debugMakeThread(_ id: UUID) { update(id) { $0.isThread = true } }
    #endif

    /// Tool guidance for a turn with xBot's tools (Harness2's term): what there is, how to use it
    /// well, and the guardrails the agent's own shell isn't held to by xBot.
    static let toolGuidance = """
        xBot tools: you have xBot's own MCP server, "xbot". Its xbot_* tools run xBot itself (projects, \
        chats, the crew and hand-offs, automations, notes, settings, your lessons, and xbot_ask to ask \
        the person something and wait for the answer). Its mac_* tools see and use this Mac: \
        mac_screenshot, mac_ui (the screen's elements through Accessibility), mac_click, mac_type, \
        mac_keys, mac_scroll, mac_open, mac_apps and mac_quit.
        - To act in an app, read it with mac_ui and click elements by their id; use coordinates only \
        when there's no element. After an action that matters, take a mac_screenshot to check it worked.
        - Deleting, sending, pushing, buying, quitting apps and changing system settings ask the person \
        first. If they don't allow something, don't look for another way to do it.
        - Before anything destructive or outward with your own shell or tools (deleting files, sending, \
        publishing, pushing, purchases), call xbot_ask and wait for a yes.
        - When you finish a task, if you learnt something general that would help next time (not \
        task-specific facts), call xbot_remember once with the cue, the lesson, your confidence and \
        the evidence.
        """
}
