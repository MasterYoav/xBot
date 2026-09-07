import Foundation
import Testing
@testable import XBotEngine

/// Reading the append-only trail, which ADR-0004 makes the one native admin screen.
@Suite
struct AuditDecodingTests {
    private func page(_ json: String) -> AuditPage {
        HTTPEngineClient.auditPage(from: Data(json.utf8))
    }

    @Test func decodesARowAndItsCursor() {
        let result = page("""
        {"events":[{"id":"a1","eventType":"computer.navigated","targetType":"bot",
          "targetId":"orchestrator","actorUserId":null,"createdAt":"2026-09-06T10:00:00.000Z",
          "payload":{"url":"https://x.test"}}],"nextCursor":"c2"}
        """)
        #expect(result.events.count == 1)
        #expect(result.events[0].eventType == "computer.navigated")
        #expect(result.events[0].summary.contains("https://x.test"))
        #expect(result.nextCursor == "c2")
    }

    /// A trail with one unreadable row is still worth showing. This is the screen somebody opens
    /// when they are worried, and an error where the history should be is the least useful outcome.
    @Test func oneBadRowDoesNotLoseTheRest() {
        let result = page("""
        {"events":[{"nonsense":true},
          {"id":"a2","eventType":"bot.grant_added","targetType":"bot","createdAt":"2026-09-06T10:00:00Z","payload":{}}]}
        """)
        #expect(result.events.count == 1)
        #expect(result.events[0].id == "a2")
    }

    /// Timestamps arrive with and without fractional seconds depending on precision. A row that
    /// failed to parse would fall back to "now" and sort itself to the top of the trail — the one
    /// place an invented time would actively mislead.
    @Test func bothTimestampPrecisionsParse() {
        let withFraction = page("""
        {"events":[{"id":"a","eventType":"e","targetType":"t","createdAt":"2026-09-06T10:00:00.123Z","payload":{}}]}
        """)
        let whole = page("""
        {"events":[{"id":"b","eventType":"e","targetType":"t","createdAt":"2026-09-06T10:00:00Z","payload":{}}]}
        """)
        let expected = Date(timeIntervalSince1970: 1_788_688_800)
        #expect(abs(withFraction.events[0].createdAt.timeIntervalSince(expected)) < 2)
        #expect(abs(whole.events[0].createdAt.timeIntervalSince(expected)) < 2)
    }

    /// The payload is summarised by value, never dumped as JSON. Upstream records that a secret was
    /// supplied and its length rather than the secret, and a payload that gains a field must not put
    /// it on screen because nobody looked again.
    @Test func theSummaryIsValuesNotRawJSON() {
        let result = page("""
        {"events":[{"id":"a","eventType":"bot.updated","targetType":"bot","createdAt":"2026-09-06T10:00:00Z",
          "payload":{"name":"Risk","keyReplaced":true,"nested":{"deep":"value"}}}]}
        """)
        let summary = result.events[0].summary
        #expect(summary.contains("Risk"))
        #expect(summary.contains("keyReplaced"))
        // A nested object is not flattened onto the screen — it has not been reviewed for what it
        // might carry.
        #expect(!summary.contains("deep"))
        #expect(!summary.contains("{"))
    }

    @Test func anEmptyBodyIsAnEmptyPageNotACrash() {
        #expect(page("not json").events.isEmpty)
        #expect(page("{}").events.isEmpty)
    }
}
