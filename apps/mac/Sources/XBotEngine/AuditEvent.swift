import Foundation

/// One row of the append-only record of what agents did.
///
/// ADR-0004 makes this the one admin surface that is native rather than a webview: "It is the
/// product's central trust claim. A user who wants to know what their agent did with their browser
/// should not meet a different-feeling interface at exactly that moment. It is also the screen a
/// worried user opens, which makes it the worst possible place for a seam."
public struct AuditEvent: Identifiable, Hashable, Sendable {
    public let id: String
    /// Null for anything the deployment did rather than a person.
    public let actorUserId: String?
    public let eventType: String
    public let targetType: String
    public let targetId: String?
    public let createdAt: Date

    /// The event's own details, flattened to text for display.
    ///
    /// Values only, never rendered as raw JSON: upstream records that a secret was supplied and its
    /// length, and a payload printed verbatim beside a person's screen is the wrong place to find
    /// out that something else was recorded too.
    public let summary: String

    public init(
        id: String,
        actorUserId: String?,
        eventType: String,
        targetType: String,
        targetId: String?,
        createdAt: Date,
        summary: String
    ) {
        self.id = id
        self.actorUserId = actorUserId
        self.eventType = eventType
        self.targetType = targetType
        self.targetId = targetId
        self.createdAt = createdAt
        self.summary = summary
    }
}

/// A page of the trail, and where the next one starts.
public struct AuditPage: Sendable, Equatable {
    public let events: [AuditEvent]
    public let nextCursor: String?

    public init(events: [AuditEvent], nextCursor: String? = nil) {
        self.events = events
        self.nextCursor = nextCursor
    }
}

/// What the viewer is asking for. Mirrors `auditQueryFromUrl` in the engine.
public struct AuditQuery: Sendable, Equatable {
    public var eventType: String?
    public var targetId: String?
    public var cursor: String?
    /// The engine clamps to 1...100 and defaults to 50; asking for more is silently reduced.
    public var limit: Int

    public init(eventType: String? = nil, targetId: String? = nil, cursor: String? = nil, limit: Int = 50) {
        self.eventType = eventType
        self.targetId = targetId
        self.cursor = cursor
        self.limit = limit
    }
}
