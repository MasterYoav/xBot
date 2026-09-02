import Foundation

/// One thing the agent did away from the browser.
///
/// A saved file contributes its path and its size, never its contents. An agent may be saving
/// something it was told in confidence, and the panel is on screen next to whoever walks past.
public struct ActivityEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case command(exitCode: Int)
        case fileRead(path: String)
        case fileWrite(path: String, bytes: Int)
        case navigate(url: String)
    }

    public let id: String
    public let kind: Kind
    public let summary: String
    /// Command output. Truncated by the engine, never the whole buffer.
    public let detail: String?
    public let at: Date

    public init(id: String, kind: Kind, summary: String, detail: String? = nil, at: Date = Date()) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.detail = detail
        self.at = at
    }
}

/// One frame of the agent's browser.
///
/// A polled screenshot, not a video stream — that is what the engine serves, and it is good news
/// for the client: an image request on a timer, fast while a turn runs, slow when idle, and
/// stopped when nobody is looking at it.
public struct ScreenFrame: Sendable, Equatable {
    public let imageData: Data
    public let width: Int
    public let height: Int
    public let capturedAt: Date

    public init(imageData: Data, width: Int, height: Int, capturedAt: Date = Date()) {
        self.imageData = imageData
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
    }
}

/// How often the screen is polled. Adapts, because a fixed cadence is either wasteful or laggy.
public enum ScreenCadence: Sendable {
    /// A turn is running. The picture is changing.
    case active
    /// Nothing is happening, but the panel is open.
    case idle
    /// The panel is not visible. Nothing is requested at all.
    case stopped

    public var interval: Duration? {
        switch self {
        case .active: .milliseconds(600)
        case .idle: .seconds(4)
        case .stopped: nil
        }
    }
}

/// Who is driving the browser.
///
/// While a human holds it, agent actions are refused rather than queued — the engine's behaviour,
/// and the right one: an agent whose clicks are replayed after a human finished a form would
/// submit it twice.
public enum ScreenControl: Hashable, Sendable {
    case agent
    case human
}
