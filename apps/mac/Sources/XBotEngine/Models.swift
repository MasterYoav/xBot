import Foundation

/// One agent, as the app knows it.
///
/// `avatarSeed` rather than an image: the rail draws an avatar from a shape and a colour derived
/// from this, so an agent has a stable identity before it has a picture and the rail never waits on
/// a download to paint. Upstream sends the same field.
public struct Agent: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    /// The one-line role under the name. Upstream calls it `title`.
    public var label: String
    public var avatarSeed: String
    public var model: ModelSelection?

    public init(
        id: String,
        name: String,
        label: String,
        avatarSeed: String,
        model: ModelSelection? = nil
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.avatarSeed = avatarSeed
        self.model = model
    }
}

/// Which model answers for one agent. The xBot addition; see docs/04-model-providers.md.
public struct ModelSelection: Hashable, Sendable {
    /// What the person reads: "Anthropic", "xAI", "Ollama".
    public let provider: String
    /// What the engine routes on: `openai`, `anthropic`, `google`, `openai-compatible`.
    ///
    /// Separate from `provider` because they genuinely differ. xAI and Ollama are both
    /// `openai-compatible` to the router — one adapter, different base URLs — while a person
    /// picking a model is choosing "Grok", not an adapter. Sending the display name is what the
    /// client used to do, and the engine has no provider called "Anthropic".
    public let providerID: String
    public let model: String
    /// Required by `openai-compatible`, which has no endpoint of its own.
    public let baseURL: String?
    /// Shown under the picker: "Anthropic · vision · tools".
    public let capabilities: [String]

    public init(
        provider: String,
        providerID: String,
        model: String,
        baseURL: String? = nil,
        capabilities: [String] = []
    ) {
        self.provider = provider
        self.providerID = providerID
        self.model = model
        self.baseURL = baseURL
        self.capabilities = capabilities
    }

    /// The vendor's name for a stored selection, worked back out of what the engine holds.
    ///
    /// Here rather than in `ModelProviderCatalog` because `XBotEngine` is Foundation-only and does
    /// not import `XBotCore` — see the target graph in Package.swift. The base URL is what tells
    /// two `openai-compatible` selections apart: the router sees one adapter, the person picked
    /// either Grok or a model running on their own Mac, and showing them the adapter's name would
    /// be showing them our plumbing.
    public static func displayName(providerID: String, baseURL: String?) -> String {
        switch providerID {
        case "anthropic": "Anthropic"
        case "openai": "OpenAI"
        case "google": "Google"
        case "openai-compatible":
            switch baseURL {
            case let url? where url.contains("x.ai"): "xAI"
            case let url? where url.contains("11434"): "Ollama"
            // A gateway somebody added by hand. Naming the host beats naming the adapter.
            default: URL(string: baseURL ?? "")?.host ?? "Custom"
            }
        default: providerID
        }
    }

    /// What the engine stores, and nothing else. See `shared/model-selection.ts`.
    public var wireFormat: [String: Any] {
        var wire: [String: Any] = ["providerId": providerID, "model": model]
        if let baseURL { wire["baseURL"] = baseURL }
        return wire
    }
}

/// A conversation. One agent in v1; the engine already models several.
public struct Channel: Identifiable, Hashable, Sendable {
    public let id: String
    public var agentIds: [String]

    public init(id: String, agentIds: [String]) {
        self.id = id
        self.agentIds = agentIds
    }
}

public struct Message: Identifiable, Hashable, Sendable {
    public enum Author: Hashable, Sendable {
        case user
        case agent(String)
    }

    /// Where a message is in its life, which the bubble renders differently.
    ///
    /// `sending` and `failed` exist because sending is optimistic: the bubble appears the instant
    /// ⏎ is pressed and the text is never lost if the request fails. See docs/09-ui-spec.md.
    public enum State: Hashable, Sendable {
        case sending
        case streaming
        case complete
        case failed(reason: String)
    }

    public let id: String
    public let author: Author
    public var text: String
    /// Compact rows, not text. Tool calls are a different content type from the sentence
    /// around them — stuffing `[name → target]` into `text` made them look like the model talking.
    public var toolCalls: [ToolCall]
    public var state: State
    public let sentAt: Date

    public struct ToolCall: Identifiable, Hashable, Sendable {
        public let id: String
        public var name: String
        public var target: String

        public init(id: String, name: String, target: String) {
            self.id = id
            self.name = name
            self.target = target
        }
    }

    public init(
        id: String,
        author: Author,
        text: String,
        toolCalls: [ToolCall] = [],
        state: State = .complete,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.toolCalls = toolCalls
        self.state = state
        self.sentAt = sentAt
    }

    public var isFromUser: Bool {
        if case .user = author { return true }
        return false
    }
}

/// One event from the AG-UI turn stream.
///
/// Deliberately smaller than AG-UI's own event set. This is what the conversation can currently
/// render; an event the app cannot draw is not worth a case that every switch has to ignore. It
/// grows as the conversation grows.
public enum TurnEvent: Sendable {
    case started(messageId: String)
    case textDelta(messageId: String, text: String)
    case toolCall(messageId: String, callId: String, name: String, target: String)
    /// The arguments for a call already announced, which arrive as their own event.
    ///
    /// Separate because AG-UI sends them separately, keyed by `toolCallId` rather than by message:
    /// only the reader that has seen the start can say which call these belong to.
    case toolArguments(callId: String, json: String)
    case finished(messageId: String)
    case runFinished
    case failed(messageId: String, reason: String)
    /// What the turn cost, reported once by the engine before the run closes.
    ///
    /// Tokens only. The cost is estimated where it is displayed, from a local price table — see
    /// `ModelPrices` — because only the app knows which model answered and what it charges.
    case usage(inputTokens: Int, outputTokens: Int)
}

/// Why the composer is disabled, if it is.
///
/// A reason rather than a bool, because docs/09-ui-spec.md requires the composer to say why it
/// cannot be used, inline, where the user is looking. A bool cannot carry a sentence, and a
/// disabled control with no explanation is the thing this type exists to make impossible.
public enum ComposerBlock: Hashable, Sendable {
    case engineNotRunning
    /// Docker (or equivalent) is not on this Mac. Install is M6 — until then we say so, and we
    /// do not offer a Start that would fail for the same reason.
    case runtimeUnavailable
    /// Start ran and did not reach `.running`. The sentence is already written for a person.
    case engineFailed(reason: String)
    case noModelConnected
    /**
     Stopped by the app after a quiet spell, per docs/07 — not broken, and not the person's doing.

     Different from `engineNotRunning` in the one way that matters: sending a message is the way to
     wake it. docs/07 says the engine "starts on demand when the user sends a message", so this is the
     one block that leaves the field open (`sendStartsEngine`) rather than making somebody press Start
     first for an engine they never stopped.
     */
    case enginePausedWhenIdle
    /// No CopilotKit Intelligence key, so the engine is in local mode and cannot hold a
    /// conversation. ADR-0007 keeps Intelligence for v1; without it `LocalIntelligence` throws past
    /// wiring, and the engine still starts and answers `/health` — so nothing else would say this.
    case noConversationStore
    /**
     A key is stored and the Keychain would not hand it over.

     Separate from `noConversationStore`, which means nobody has connected one. Collapsing the two
     tells somebody who already connected a key to go and connect it — they open Settings, see their
     key sitting there, and have nowhere left to look. It is the same mistake the engine status made
     about a container runtime that was installed and merely asleep.

     The usual cause is a locked login Keychain or a denied prompt, and both are recoverable, so the
     action is to try again rather than to go anywhere.
     */
    case conversationStoreUnreadable
    case humanHoldsControl

    public var sentence: String {
        switch self {
        case .engineNotRunning: String(localized: "The engine isn't running")
        case .runtimeUnavailable:
            String(localized: "xBot needs Docker Desktop, OrbStack, or Colima to run the engine")
        case .engineFailed(let reason): reason
        case .noModelConnected: String(localized: "Connect a model to start")
        case .enginePausedWhenIdle:
            String(localized: "Paused while idle to save memory — sending a message starts it again")
        case .noConversationStore:
            String(localized: "Connect a CopilotKit key so xBot can keep your conversations")
        case .conversationStoreUnreadable:
            String(localized: "xBot couldn't read your CopilotKit key from the Keychain")
        case .humanHoldsControl: String(localized: "You're controlling the browser")
        }
    }

    /// Empty means no button. The composer hides it rather than drawing a no-op.
    public var actionTitle: String {
        switch self {
        case .engineNotRunning: String(localized: "Start")
        case .runtimeUnavailable: ""
        case .engineFailed: String(localized: "Try again")
        case .noModelConnected: String(localized: "Open Settings")
        case .enginePausedWhenIdle: String(localized: "Start now")
        case .noConversationStore: String(localized: "Open Settings")
        case .conversationStoreUnreadable: String(localized: "Try again")
        case .humanHoldsControl: String(localized: "Give it back")
        }
    }

    /// Whether the field stays open and a send is how the block clears. True only for an engine the
    /// app paused itself: every other block needs the person to do something first.
    public var sendStartsEngine: Bool { self == .enginePausedWhenIdle }
}
