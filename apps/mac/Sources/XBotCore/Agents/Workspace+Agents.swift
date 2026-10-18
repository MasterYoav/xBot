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
        let before = agents.first { $0.id == agent.id }
        if agent.isHeadMaster == false, before?.isHeadMaster == true {
            agent.isHeadMaster = true
        }
        if agent.isHeadMaster { agent.managerID = nil }
        // Nobody can end up their own manager: keep what they had.
        let others = agents.filter { $0.id != agent.id }.map(\.orgMember) + [agent.orgMember]
        if OrgChart.wouldLoop(agent.id, under: agent.managerID, in: others) || agent.managerID == agent.id {
            agent.managerID = before?.managerID
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
        // Their team now reports to their manager.
        let team = agents.filter { $0.managerID == id }
        for var member in team {
            member.managerID = agent.managerID
            saveAgent(member)
        }
        attempt { try store.deleteAgent(id) }
        agents.removeAll { $0.id == id }
        for chatID in theirs { update(chatID) { $0.agentID = nil } }
        return { [weak self] in
            guard let self else { return }
            self.saveAgent(agent)
            for member in team {
                if var now = self.agent(member.id) { now.managerID = id; self.saveAgent(now) }
            }
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

    /// `handedFrom`: the permission of the manager's chat when this one is a hand-off, which caps
    /// this chat's (see `Handoff.mode`).
    func startChat(with agent: Agent, in projectID: UUID?, select: Bool, handedFrom: PermissionMode? = nil) -> Chat? {
        let harness = brains[agent.harness] == nil ? availableHarnesses.first : agent.harness
        guard let harness else { return nil }
        let projectID = projectID.flatMap { id in projects.contains { $0.id == id } ? id : nil }
        let mode = handedFrom.map { Handoff.mode(handedFrom: $0, to: harness) } ?? .editFiles
        let chat = Chat(
            projectID: projectID, title: String(localized: "New chat"), harness: harness,
            model: harness == agent.harness ? agent.model : nil, mode: mode, agentID: agent.id
        )
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        if select { open(chat.id) }
        return chat
    }

    // MARK: Who they are, every turn

    // MARK: The org chart

    /// The crew as an org chart (HeadMaster at the top).
    public var orgChart: OrgChart.Tree { OrgChart.tree(agents.map(\.orgMember)) }

    /// Who they report to: their manager on the crew, or nil for the person (HeadMaster).
    public func manager(of id: UUID) -> Agent? { agent(orgChart.manager(of: id)) }

    /// Everyone below them, at any depth: who they can hand work to.
    public func team(of id: UUID) -> [Agent] { orgChart.below(id).compactMap { agent($0) } }

    /// Where most companies would put someone with this role on this crew.
    public func suggestedManager(role: String, for id: UUID?) -> UUID? {
        OrgChart.suggestedManager(role: role, id: id, among: agents.map(\.orgMember))
    }

    /// Everyone reports where their role suggests: executives to HeadMaster, teams to theirs.
    public func organiseLikeACompany() {
        // Executives and leads first, so their teams find them.
        let ordered = agents.sorted { OrgChart.position(of: $0.role).rank < OrgChart.position(of: $1.role).rank }
        for var member in ordered where !member.isHeadMaster {
            member.managerID = suggestedManager(role: member.role, for: member.id)
            saveAgent(member)
        }
    }

    /// Who the chat's agent is, the crew it works with, its role instructions and what it has
    /// learnt. Nil for a chat that isn't with an agent. `toolsAttached`: the turn has xBot's own
    /// tools, so the agent is asked to write down what it learnt (`xbot_remember`).
    func instructions(for chat: Chat, toolsAttached: Bool = false) -> String? {
        guard let agent = agent(chat.agentID) else { return nil }
        var text = "You are \(agent.name)"
        if !agent.role.isEmpty { text += ", \(agent.role.prefix(1).lowercased() + agent.role.dropFirst())" }
        text += ". You are one of the crew in xBot, a workplace of AI agents on this Mac.\n\n"
        if agent.isHeadMaster {
            text += "You report to the person using xBot: you run the company for them.\n\n"
        } else if let boss = manager(of: agent.id) {
            text += "You report to \(boss.name)\(boss.role.isEmpty ? "" : " (\(boss.role))"). When you finish work they gave you, xBot tells them.\n\n"
        }
        let others = agents.filter { $0.id != agent.id }
        if !others.isEmpty {
            text += "The crew:\n"
            for other in others {
                let boss = manager(of: other.id).map { ", reports to \($0.name)" } ?? ""
                text += "- \(other.name)\(other.isHeadMaster ? " (the founder and CEO, who orchestrates)" : ""): \(other.role)\(boss)\n"
            }
            text += "\n"
        }
        let team = team(of: agent.id)
        if !team.isEmpty {
            text += "Your team (you can hand work to them): \(team.map(\.name).joined(separator: ", ")).\n\n"
            text += """
                To hand a task to someone on your team, end your reply with one block per task, exactly like this:

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
        var sections: [String] = []
        if let learnt = experienceSection(for: agent.id) { sections.append(learnt) }
        if toolsAttached { sections.append(Self.reflection) }
        if !sections.isEmpty {
            text = text.trimmingCharacters(in: .newlines) + "\n\n" + sections.joined(separator: "\n\n")
        }
        return text
    }

    /// Acts on HeadMaster's hand-offs once its turn ends; returns a notice per hand-off for its reply.
    func handOff(from chatID: UUID, reply parts: [Part]) -> [Part] {
        guard let chat = chat(chatID), let head = agent(chat.agentID) else { return [] }
        let team = team(of: head.id)
        guard !team.isEmpty else { return [] }
        let text = parts.compactMap { part -> String? in if case .text(let t) = part { t } else { nil } }.joined()
        return Handoff.all(in: text).flatMap { handoff -> [Part] in
            func named(_ agent: Agent) -> Bool {
                agent.name.compare(handoff.to, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            guard let member = team.first(where: named) else {
                if agents.contains(where: named) {
                    return [.notice(String(localized: "\(handoff.to) isn't on \(head.name)'s team, so that task wasn't handed off."))]
                }
                return [.notice(String(localized: "There's no \(handoff.to) in the crew, so that task wasn't handed off."))]
            }
            guard let started = startChat(with: member, in: chat.projectID, select: false, handedFrom: chat.mode),
                  send(String(localized: "From \(head.name): \(handoff.task)"), in: started.id) else {
                return [.notice(String(localized: "Couldn't hand that to \(member.name)."))]
            }
            handoffOrigins[started.id] = chatID
            var notices: [Part] = [.notice(Handoff.handedPrefix(member.name) + Self.title(from: handoff.task))]
            // Said, not silent: the person may expect the member to edit, as others on the crew do.
            if chat.mode == .editFiles, started.harness.editingNeedsFullAccess {
                notices.append(.notice(String(localized: "\(started.harness.displayName) can only edit with full access, so \(member.name) works read-only on this. Give this chat full access to let them edit.")))
            }
            return notices
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
