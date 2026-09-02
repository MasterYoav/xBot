import Foundation
import XBotEngine

/// What the whole app reads from, and sends intents to.
///
/// ponytail: one object, not the five stores docs/05-mac-app.md lists. Agents, channels and
/// settings are separate stores in the spec because they will have separate logic — but they do not
/// yet, and four empty classes forwarding to one array is more places to look, not fewer. Split
/// when a store earns its own behaviour (settings persistence and provider probing will earn it
/// first); the split is mechanical because views already go through intents rather than reaching
/// into the arrays.
///
/// `@MainActor` on the whole thing, without exceptions. Everything here is read during layout.
@Observable
@MainActor
public final class AppState {
    private let engine: any EngineClient

    public private(set) var agents: [Agent] = []
    public private(set) var channels: [Channel] = []
    public private(set) var messages: [Message] = []

    /// Nil until the first load resolves, so the rail does not paint a selection that then moves.
    public var selectedAgentID: Agent.ID?

    /// Why the composer is disabled, or nil if it is not.
    public private(set) var composerBlock: ComposerBlock?

    /// What the floating pill says, or nil.
    ///
    /// Nil when everything is fine. The spec is explicit: do not confirm good news. A pill that is
    /// always present stops carrying information.
    public private(set) var status: Status?

    public enum Status: Hashable, Sendable {
        case startingUp
        case reconnecting
        case updating

        public var sentence: String {
            switch self {
            case .startingUp: String(localized: "Starting up")
            case .reconnecting: String(localized: "Reconnecting")
            case .updating: String(localized: "Updating")
            }
        }
    }

    /// The turn currently streaming, if any. One per channel would be right for multi-agent; one
    /// here is right for a window that shows a single conversation at a time.
    private var turn: Task<Void, Never>?

    public init(engine: any EngineClient) {
        self.engine = engine
    }

    public var selectedAgent: Agent? {
        agents.first { $0.id == selectedAgentID }
    }

    private var selectedChannelID: Channel.ID? {
        guard let selectedAgentID else { return nil }
        return channels.first { $0.agentIds.contains(selectedAgentID) }?.id
    }

    public func load() async {
        status = .startingUp
        do {
            agents = try await engine.agents()
            channels = try await engine.channels()
            if selectedAgentID == nil { selectedAgentID = agents.first?.id }
            await loadMessages()
            status = nil
        } catch {
            // Honest degradation: the rail is empty because the engine is down, and the composer
            // says so. Never an empty state that implies there is simply nothing here.
            status = .reconnecting
            composerBlock = .engineNotRunning
        }
    }

    public func select(_ id: Agent.ID) {
        guard id != selectedAgentID else { return }
        selectedAgentID = id
        // The selection does not wait for the conversation. It is applied now; messages catch up.
        turn?.cancel()
        turn = nil
        messages = []
        Task { await loadMessages() }
    }

    private func loadMessages() async {
        guard let channel = selectedChannelID else {
            messages = []
            return
        }
        messages = (try? await engine.messages(in: channel)) ?? []
    }

    /// Send, optimistically.
    ///
    /// The bubble exists before the request does. A send that fails becomes a retryable bubble
    /// holding the same text — the one thing that must never happen is losing what somebody typed.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, composerBlock == nil, let channel = selectedChannelID else { return }

        let sent = Message(id: "local-\(UUID().uuidString)", author: .user, text: trimmed, state: .sending)
        messages.append(sent)

        let agentID = selectedAgentID ?? ""
        turn?.cancel()
        turn = Task { [engine] in
            var replyID: String?
            do {
                for try await event in engine.send(trimmed, to: channel) {
                    switch event {
                    case .started(let id):
                        replyID = id
                        mark(sent.id, as: .complete)
                        messages.append(
                            Message(id: id, author: .agent(agentID), text: "", state: .streaming)
                        )
                    case .textDelta(let id, let text):
                        append(text, to: id)
                    case .toolCall(let id, let name, let target):
                        append("\n[\(name) → \(target)]\n", to: id)
                    case .finished(let id):
                        mark(id, as: .complete)
                    case .failed(let id, let reason):
                        mark(id, as: .failed(reason: reason))
                    }
                }
            } catch {
                mark(replyID ?? sent.id, as: .failed(reason: error.localizedDescription))
            }
        }
    }

    private func append(_ text: String, to id: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += text
    }

    private func mark(_ id: Message.ID, as state: Message.State) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].state = state
    }
}
