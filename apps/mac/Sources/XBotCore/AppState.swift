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

    // MARK: - The right panel

    public enum PanelSection: String, CaseIterable, Identifiable, Sendable {
        case screen, activity, routines, settings
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .screen: String(localized: "Screen")
            case .activity: String(localized: "Activity")
            case .routines: String(localized: "Routines")
            case .settings: String(localized: "Agent settings")
            }
        }

        public var symbol: String {
            switch self {
            case .screen: "display"
            case .activity: "list.bullet.rectangle"
            case .routines: "clock.arrow.circlepath"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    public var isPanelVisible = true {
        didSet { retuneScreen() }
    }
    public var panelSection: PanelSection = .screen {
        didSet { retuneScreen() }
    }

    /// Held in the client for the open conversation, and gone on reload.
    ///
    /// A window, not a record. The record is the audit trail, server-side — the panel says so, and
    /// this property being in-memory is that sentence expressed as a design rather than a caption.
    public private(set) var activity: [ActivityEntry] = []

    public private(set) var screenFrame: ScreenFrame?
    public private(set) var control: ScreenControl = .agent
    public private(set) var models: [ModelSelection] = []

    private var screenTask: Task<Void, Never>?

    /// True while a turn is in flight, which is what makes the screen poll fast.
    private var isTurnRunning = false

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
            await loadPanel()
            models = (try? await engine.availableModels()) ?? []
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
        activity = []
        screenFrame = nil
        Task {
            await loadMessages()
            await loadPanel()
        }
    }

    private func loadPanel() async {
        guard let agent = selectedAgentID else { return }
        activity = (try? await engine.activity(for: agent)) ?? []
        retuneScreen()
    }

    /// Match the polling cadence to what is actually on screen.
    ///
    /// Stopped when the panel is hidden or showing something else — an app that keeps requesting
    /// screenshots nobody is looking at is the reason laptops get warm, and this is the product
    /// whose whole pitch is that it runs on your own machine.
    private func retuneScreen() {
        screenTask?.cancel()
        guard let agent = selectedAgentID else { return }

        let cadence: ScreenCadence =
            (isPanelVisible && panelSection == .screen)
            ? (isTurnRunning ? .active : .idle)
            : .stopped
        guard cadence.interval != nil else {
            screenTask = nil
            return
        }

        screenTask = Task { [engine] in
            for await frame in engine.screen(for: agent, cadence: cadence) {
                if Task.isCancelled { return }
                screenFrame = frame
            }
        }
    }

    /// Take the browser, or hand it back.
    ///
    /// Optimistic, like sending: the overlay flips immediately because the user pressed the button,
    /// and reverts if the engine refuses. Waiting for a round trip to show that a click registered
    /// is exactly the latency the design system opens by forbidding.
    public func setControl(_ next: ScreenControl) {
        let previous = control
        control = next
        Task { [engine, selectedAgentID] in
            guard let agent = selectedAgentID else { return }
            do {
                try await engine.setControl(next, for: agent)
            } catch {
                control = previous
            }
        }
    }

    public func updateSelectedAgent(_ patch: AgentPatch) {
        guard let id = selectedAgentID else { return }
        Task { [engine] in
            guard let updated = try? await engine.updateAgent(id, patch) else { return }
            if let index = agents.firstIndex(where: { $0.id == id }) {
                agents[index] = updated
            }
        }
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
        isTurnRunning = true
        retuneScreen()
        turn = Task { [engine] in
            defer {
                isTurnRunning = false
                retuneScreen()
            }
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
