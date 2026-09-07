import Foundation
import Testing
import XBotEngine
@testable import XBotCore

/// The screen somebody opens when they are worried, so its failure mode matters more than most.
@Suite @MainActor
struct AuditStateTests {
    private func page(_ ids: [String], cursor: String? = nil) -> AuditPage {
        AuditPage(
            events: ids.map {
                AuditEvent(
                    id: $0, actorUserId: nil, eventType: "computer.navigated",
                    targetType: "bot", targetId: "orchestrator",
                    createdAt: Date(), summary: "url: https://x.test"
                )
            },
            nextCursor: cursor
        )
    }

    @Test func loadsAPage() async {
        let audit = AuditState()
        await audit.load { _ in self.page(["a", "b"]) }
        #expect(audit.events.count == 2)
        #expect(audit.problem == nil)
    }

    /// The important one. An empty list says "nothing has happened"; a failure to reach the engine
    /// says "I could not ask". On this screen, showing the first when the second is true would tell
    /// somebody their agents did nothing — which is exactly the reassurance they came for and
    /// exactly what nobody has verified.
    @Test func aFailureIsNotAnEmptyTrail() async {
        let audit = AuditState()
        await audit.load { _ in throw EngineError.notRunning }
        #expect(audit.events.isEmpty)
        #expect(audit.problem != nil)
    }

    @Test func theFilterReachesTheQuery() async {
        let audit = AuditState()
        audit.eventTypeFilter = "computer"
        var seen: String?
        await audit.load { query in
            seen = query.eventType
            return self.page(["a"])
        }
        #expect(seen == "computer")
    }

    @Test func anEmptyFilterAsksForEverything() async {
        let audit = AuditState()
        var seen: String? = "unset"
        await audit.load { query in
            seen = query.eventType
            return self.page([])
        }
        #expect(seen == nil)
    }

    @Test func olderPagesAppendRatherThanReplace() async {
        let audit = AuditState()
        await audit.load { _ in self.page(["a"], cursor: "c1") }
        #expect(audit.canLoadMore)

        await audit.loadMore { query in
            #expect(query.cursor == "c1")
            return self.page(["b"])
        }
        #expect(audit.events.map(\.id) == ["a", "b"])
        #expect(!audit.canLoadMore)
    }

    @Test func thereIsNothingMoreToLoadWithoutACursor() async {
        let audit = AuditState()
        await audit.load { _ in self.page(["a"]) }
        var asked = false
        await audit.loadMore { _ in
            asked = true
            return self.page([])
        }
        #expect(!asked)
    }
}
