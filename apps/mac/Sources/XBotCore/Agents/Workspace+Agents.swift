import Foundation
import XBotBrain

/// The crew: hiring, editing, talking to them, what each is doing, and HeadMaster's hand-offs.
extension Workspace {
    /// The Agents page; with `hiring`, the editor opens on a new member.
    public func showAgents(hiring: Bool = false) {
        page = .agents
        if hiring { wantsToHire = true }
    }

    public var headMaster: Agent? { agents.first(where: \.isHeadMaster) }

    public func agent(_ id: UUID?) -> Agent? { id.flatMap { id in agents.first { $0.id == id } } }

    /// A new member with a random look, not saved until `saveAgent`.
    public func hire() -> Agent {
        Agent(
            name: "", role: "", instructions: "", avatar: .random(),
            harness: availableHarnesses.first ?? .claude, projectID: contextProject?.id,
            sortIndex: (agents.map(\.sortIndex).max() ?? 0) + 1
        )
    }

    public func saveAgent(_ agent: Agent) {
        var agent = agent
        agent.name = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if agent.isHeadMaster == false, agents.first(where: { $0.id == agent.id })?.isHeadMaster == true {
            agent.isHeadMaster = true
        }
        attempt { try store.save(agent) }
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
    }

    /// Removes a member and returns how to bring it back, or nil for HeadMaster, who founded the
    /// place. Its chats stay, as plain chats; undo makes them its own again.
    @discardableResult
    public func deleteAgent(_ id: UUID) -> (@MainActor () -> Void)? {
        guard let agent = agent(id), !agent.isHeadMaster else { return nil }
        let theirs = chats.filter { $0.agentID == id }.map(\.id)
        attempt { try store.deleteAgent(id) }
        agents.removeAll { $0.id == id }
        for chatID in theirs { update(chatID) { $0.agentID = nil } }
        return { [weak self] in
            guard let self else { return }
            self.saveAgent(agent)
            self.agents.sort { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            for chatID in theirs { self.update(chatID) { $0.agentID = id } }
        }
    }

    /// Opens a new chat with `id`, in its home project (else the one in context), on its brain.
    @discardableResult
    public func talk(to id: UUID) -> Chat? {
        guard let agent = agent(id) else { return nil }
        markSeen(id)
        return startChat(with: agent, in: agent.projectID ?? contextProject?.id, select: true)
    }

    /// The chat most recently with `id`, opened; a new one if there is none.
    public func openLatestChat(with id: UUID) {
        if let chat = chats.filter({ $0.agentID == id }).max(by: { $0.updatedAt < $1.updatedAt }) {
            markSeen(id)
            open(chat.id)
        } else {
            talk(to: id)
        }
    }

    func startChat(with agent: Agent, in projectID: UUID?, select: Bool) -> Chat? {
        let harness = brains[agent.harness] == nil ? availableHarnesses.first : agent.harness
        guard let harness else { return nil }
        let projectID = projectID.flatMap { id in projects.contains { $0.id == id } ? id : nil }
        let chat = Chat(
            projectID: projectID, title: String(localized: "New chat"), harness: harness,
            model: harness == agent.harness ? agent.model : nil, mode: .editFiles, agentID: agent.id
        )
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        if select { open(chat.id) }
        return chat
    }

    // MARK: Who they are, every turn

    /// Who the chat's agent is, the crew it works with, and its role instructions. Nil for a
    /// chat that isn't with an agent.
    func instructions(for chat: Chat) -> String? {
        guard let agent = agent(chat.agentID) else { return nil }
        var text = "You are \(agent.name)"
        if !agent.role.isEmpty { text += ", \(agent.role.prefix(1).lowercased() + agent.role.dropFirst())" }
        text += ". You are one of the crew in xBot, a workplace of AI agents on this Mac.\n\n"
        let others = agents.filter { $0.id != agent.id }
        if !others.isEmpty {
            text += "The crew:\n"
            for other in others {
                text += "- \(other.name)\(other.isHeadMaster ? " (the founder, who orchestrates)" : ""): \(other.role)\n"
            }
            text += "\n"
        }
        if agent.isHeadMaster, !others.isEmpty {
            text += """
                To hand a task to a crew member, end your reply with one block per task, exactly like this:

                ```handoff
                to: <their name>
                task: <a clear, self-contained task: what to do, where, and what done looks like>
                ```

                xBot starts that member on it in their own chat, in this project. Only hand off work \
                that fits their role, and tell the person what you handed to whom. You are not called \
                again when they finish: xBot puts a note in this chat, and the person can open theirs.


                """
        }
        if !agent.instructions.isEmpty { text += "How you work:\n" + agent.instructions }
        return text
    }

    /// Acts on HeadMaster's hand-offs once its turn ends; returns a notice per hand-off for its reply.
    func handOff(from chatID: UUID, reply parts: [Part]) -> [Part] {
        guard let chat = chat(chatID), let head = agent(chat.agentID), head.isHeadMaster else { return [] }
        let text = parts.compactMap { part -> String? in if case .text(let t) = part { t } else { nil } }.joined()
        return Handoff.all(in: text).map { handoff in
            guard let member = agents.first(where: {
                !$0.isHeadMaster && $0.name.compare(handoff.to, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else {
                return .notice(String(localized: "There's no \(handoff.to) in the crew, so that task wasn't handed off."))
            }
            guard let started = startChat(with: member, in: chat.projectID, select: false),
                  send(String(localized: "From \(head.name): \(handoff.task)"), in: started.id) else {
                return .notice(String(localized: "Couldn't hand that to \(member.name)."))
            }
            handoffOrigins[started.id] = chatID
            return .notice(Handoff.handedPrefix(member.name) + Self.title(from: handoff.task))
        }
    }

    /// A member finished what HeadMaster handed them: say so in HeadMaster's chat.
    func reportBack(from chatID: UUID, reply parts: [Part]) {
        guard let origin = handoffOrigins.removeValue(forKey: chatID), chat(origin) != nil,
              let member = agent(chat(chatID)?.agentID) else { return }
        let text = parts.compactMap { part -> String? in if case .text(let t) = part { t } else { nil } }.joined()
        let gist = Self.title(from: Handoff.stripping(text))
        save(ChatMessage(chatID: origin, role: .assistant, parts: [
            .notice(Handoff.finishedPrefix(member.name) + (gist.isEmpty ? String(localized: "done") : gist)),
        ]))
    }

    /// Moves a chat to another project, or the Inbox, while nothing has been said in it yet.
    @discardableResult
    public func setProject(_ projectID: UUID?, for id: UUID) -> Bool {
        guard messages(in: id).isEmpty, !isRunning(id), chat(id)?.sessionID == nil,
              projectID == nil || projects.contains(where: { $0.id == projectID }) else { return false }
        update(id) { $0.projectID = projectID }
        return true
    }

    // MARK: What they're doing

    public func status(of id: UUID) -> AgentStatus {
        let theirs = chats.filter { $0.agentID == id }
        if let running = theirs.first(where: { isRunning($0.id) }) {
            return .working(activity: activity(in: running.id), since: running.updatedAt)
        }
        if let finished = agentFinishedAt[id], finished > (agentSeenAt[id] ?? .distantPast),
           Date.now.timeIntervalSince(finished) < 600 {
            return .done
        }
        return .idle
    }

    /// The person has looked: Done goes back to Idle.
    public func markSeen(_ id: UUID) { agentSeenAt[id] = .now }

    /// What a running chat is doing, in a few words, for a speech bubble.
    public func activity(in chatID: UUID) -> String? {
        guard let parts = live[chatID] else { return nil }
        for part in parts.reversed() {
            switch part {
            case .tool(let tool) where tool.output == nil:
                let summary = tool.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let verb = ToolLabel.verb(tool.name, running: true)
                return summary.isEmpty ? verb : "\(verb) \(summary.prefix(40))"
            case .text(let text):
                let line = text.split(whereSeparator: \.isNewline).last.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if !line.isEmpty { return line.count > 60 ? "…" + line.suffix(59) : line }
            default: continue
            }
        }
        return String(localized: "Thinking…")
    }

    /// Agent chats' turns per day, oldest first, `days` long, for the Activity card.
    public func agentActivity(days: Int, now: Date = .now) -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var counts = Array(repeating: 0, count: days)
        let theirs = Set(chats.filter { $0.agentID != nil }.map(\.id))
        for chatID in theirs {
            let messages = transcripts[chatID] ?? attempt { try store.messages(in: chatID) } ?? []
            for message in messages where message.role == .assistant {
                let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: message.createdAt), to: today).day ?? days
                if (0..<days).contains(day) { counts[days - 1 - day] += 1 }
            }
        }
        return counts
    }
}
