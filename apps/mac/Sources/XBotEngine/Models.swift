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
    public let provider: String
    public let model: String
    /// Shown under the picker: "Anthropic · vision · tools".
    public let capabilities: [String]

    public init(provider: String, model: String, capabilities: [String] = []) {
        self.provider = provider
        self.model = model
        self.capabilities = capabilities
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
    public var state: State
    public let sentAt: Date

    public init(
        id: String,
        author: Author,
        text: String,
        state: State = .complete,
        sentAt: Date = Date()
    ) {
        self.id = id
        self.author = author
        self.text = text
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
    case toolCall(messageId: String, name: String, target: String)
    case finished(messageId: String)
    case failed(messageId: String, reason: String)
}

/// Why the composer is disabled, if it is.
///
/// A reason rather than a bool, because docs/09-ui-spec.md requires the composer to say why it
/// cannot be used, inline, where the user is looking. A bool cannot carry a sentence, and a
/// disabled control with no explanation is the thing this type exists to make impossible.
public enum ComposerBlock: Hashable, Sendable {
    case engineNotRunning
    case noModelConnected
    case humanHoldsControl

    public var sentence: String {
        switch self {
        case .engineNotRunning: String(localized: "The engine isn't running")
        case .noModelConnected: String(localized: "Connect a model to start")
        case .humanHoldsControl: String(localized: "You're controlling the browser")
        }
    }

    public var actionTitle: String {
        switch self {
        case .engineNotRunning: String(localized: "Start")
        case .noModelConnected: String(localized: "Open Settings")
        case .humanHoldsControl: String(localized: "Give it back")
        }
    }
}
