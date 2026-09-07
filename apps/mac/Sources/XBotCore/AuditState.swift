import Foundation
import Observation
import XBotEngine

/// Settings → Audit: the append-only record, natively.
///
/// ADR-0004 makes this the single exception to the admin-webview rule and says why: it is the
/// product's central trust claim, and the screen somebody opens when they are worried. A different
/// -feeling interface at exactly that moment is the worst possible place for a seam.
@MainActor
@Observable
public final class AuditState {
    public private(set) var events: [AuditEvent] = []
    public private(set) var isLoading = false
    public private(set) var problem: String?
    private(set) var nextCursor: String?

    /// The filter in force. Empty means everything.
    public var eventTypeFilter = ""

    public init() {}

    public func load(fetch: (AuditQuery) async throws -> AuditPage) async {
        isLoading = true
        problem = nil
        defer { isLoading = false }
        do {
            let page = try await fetch(
                AuditQuery(eventType: eventTypeFilter.isEmpty ? nil : eventTypeFilter)
            )
            events = page.events
            nextCursor = page.nextCursor
        } catch {
            // Never an empty list on failure. "Nothing has happened" and "I could not ask" are
            // opposite answers, and this is the screen where confusing them matters most.
            events = []
            nextCursor = nil
            problem = String(
                localized: "The audit trail couldn't be read. It needs the engine to be running."
            )
        }
    }

    /// Fetch the next page and append it. The trail is long and read newest first.
    public func loadMore(fetch: (AuditQuery) async throws -> AuditPage) async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await fetch(
            AuditQuery(eventType: eventTypeFilter.isEmpty ? nil : eventTypeFilter, cursor: cursor)
        ) else { return }
        events += page.events
        nextCursor = page.nextCursor
    }

    public var canLoadMore: Bool { nextCursor != nil }
}
