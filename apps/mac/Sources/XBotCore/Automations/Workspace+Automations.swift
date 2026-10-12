import Foundation
import XBotBrain

/// Making, running and scheduling automations. A run is a chat tagged with its automation, kept
/// out of the sidebar and the tabs: the automation's history.
extension Workspace {
    public func showAutomations() { page = .automations }

    public func automation(_ id: UUID) -> Automation? { automations.first { $0.id == id } }

    /// A new one, not saved until `saveAutomation`.
    public func newAutomation() -> Automation {
        Automation(
            name: String(localized: "New automation"), trigger: .manual, steps: [],
            harness: availableHarnesses.contains(.claude) ? .claude : (availableHarnesses.first ?? .claude),
            sortIndex: (automations.map(\.sortIndex).max() ?? 0) + 1
        )
    }

    public func saveAutomation(_ automation: Automation) {
        attempt { try store.save(automation) }
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            // The last run belongs to the store (runs claim it there), not to the editor's copy.
            var saved = automation
            saved.lastRunAt = automations[index].lastRunAt
            automations[index] = saved
        } else {
            automations.append(automation)
        }
    }

    public func deleteAutomation(_ id: UUID) {
        attempt { try store.deleteAutomation(id) }
        automations.removeAll { $0.id == id }
        for chat in chats where chat.automationID == id { update(chat.id) { $0.automationID = nil } }
    }

    /// Newest first.
    public func runs(of id: UUID) -> [Chat] {
        chats.filter { $0.automationID == id }.sorted { $0.createdAt > $1.createdAt }
    }

    /// The run ended on an error (the agent couldn't sign in, a tool broke the turn, …).
    public func runFailed(_ id: UUID) -> Bool {
        let messages = transcripts[id] ?? attempt { try store.messages(in: id) } ?? []
        return messages.last?.parts.contains { if case .failure = $0 { true } else { false } } ?? false
    }

    public func isRunning(automation id: UUID) -> Bool { runs(of: id).contains { isRunning($0.id) } }

    /// Starts a run now: a new chat, full access, the compiled prompt. Nil when it's running
    /// already, its agent isn't installed, it has nothing to do, or another xBot claimed it first.
    @discardableResult
    public func runAutomation(_ id: UUID, at now: Date = .now) -> Chat? {
        reloadAutomations()
        guard let automation = automation(id), !isRunning(automation: id), brains[automation.harness] != nil,
              automation.hasWork,
              attempt({ try store.claim(id, expected: automation.lastRunAt, at: now) }) == true
        else { return nil }
        if let index = automations.firstIndex(where: { $0.id == id }) { automations[index].lastRunAt = now }

        let title = automation.name + " · " + now.formatted(date: .abbreviated, time: .shortened)
        let chat = Chat(
            projectID: automation.projectID, title: title, harness: automation.harness, model: automation.model,
            mode: .fullAccess, effort: automation.effort, automationID: id
        )
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        // The title is the run's, not the prompt's: `send` renames only "New chat".
        guard send(AutomationPrompt.make(automation), in: chat.id) else { return nil }
        return self.chat(chat.id)
    }

    /// Runs whatever is due. Returns the ones started.
    @discardableResult
    public func runDueAutomations(at now: Date = .now) -> [UUID] {
        reloadAutomations()
        return automations.filter { $0.isDue(at: now) }.compactMap { runAutomation($0.id, at: now)?.automationID }
    }

    /// While the app is open: a look every 30 seconds, for automations and Jev workflows.
    public func startAutomationClock() {
        guard automationClock == nil else { return }
        automationClock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !self.isDiscovering else { continue }
                self.runDueAutomations()
                // Workflows run from the same clock (and the same helper while xBot is closed).
                self.runDueWorkflows()
            }
        }
    }

    /// Takes the last runs from the store: the background helper may have run something.
    func reloadAutomations() {
        guard let saved = attempt({ try store.automations() }) else { return }
        automations = saved
    }

    /// The background helper: wait for every run started to finish (at most `limit`).
    public func waitForTurns(limit: Duration = .seconds(1800)) async {
        let clock = ContinuousClock()
        let end = clock.now + limit
        while !turns.isEmpty, clock.now < end { try? await Task.sleep(for: .milliseconds(500)) }
    }
}
