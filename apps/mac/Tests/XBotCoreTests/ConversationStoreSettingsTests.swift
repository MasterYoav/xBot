import Foundation
import Testing
@testable import XBotCore

/// Settings → Models, the CopilotKit section — the one key that had no home.
@MainActor
@Suite
struct ConversationStoreSettingsTests {
    /// A store whose Keychain is a variable, so a test is not deciding against this machine's own.
    private final class Fake: @unchecked Sendable {
        var stored: String?
        var writeFails = false
        var clearFails = false
        var state: ConversationStore = .notConnected
    }

    private struct Refused: Error {}

    private func make(_ fake: Fake) -> ConversationStoreSettings {
        ConversationStoreSettings(
            read: { fake.state },
            write: { key in
                if fake.writeFails { throw Refused() }
                fake.stored = key
                fake.state = .ready
            },
            clear: {
                if fake.clearFails { throw Refused() }
                fake.stored = nil
                fake.state = .notConnected
            }
        )
    }

    @Test func connectingStoresTheKeyAndReportsConnected() {
        let fake = Fake()
        let settings = make(fake)
        settings.connect("ck-live-abc")
        #expect(fake.stored == "ck-live-abc")
        #expect(settings.state == .ready)
        #expect(settings.problem == nil)
    }

    @Test func whitespaceIsTrimmedAndAnEmptyKeyIsNotStored() {
        let fake = Fake()
        let settings = make(fake)
        settings.connect("   ck-live-abc  ")
        #expect(fake.stored == "ck-live-abc")

        let untouched = Fake()
        let second = make(untouched)
        second.connect("   ")
        #expect(untouched.stored == nil)
    }

    /**
     Never silently.

     A key somebody pasted that did not save is the worst available outcome: they believe it is
     connected, the section says connected, and the engine goes on booting into local mode where the
     history client throws on everything.
     */
    @Test func aKeyThatCouldNotBeSavedSaysSo() {
        let fake = Fake()
        fake.writeFails = true
        let settings = make(fake)
        settings.connect("ck-live-abc")
        #expect(settings.problem != nil)
        #expect(settings.state != .ready)
    }

    @Test func disconnectingRemovesTheKey() {
        let fake = Fake()
        fake.stored = "ck-live-abc"
        fake.state = .ready
        let settings = make(fake)
        settings.disconnect()
        #expect(fake.stored == nil)
        #expect(settings.state == .notConnected)
    }

    @Test func aRemovalThatFailedDoesNotClaimToHaveWorked() {
        let fake = Fake()
        fake.stored = "ck-live-abc"
        fake.state = .ready
        fake.clearFails = true
        let settings = make(fake)
        settings.disconnect()
        #expect(fake.stored == "ck-live-abc")
        #expect(settings.problem != nil)
    }

    /// An unreadable key is a Keychain problem, not a missing key — the section must not offer to
    /// connect one that is already there.
    @Test func anUnreadableKeyIsReportedAsAKeychainProblem() {
        let fake = Fake()
        fake.state = .unreadable
        let settings = make(fake)
        settings.load()
        #expect(settings.state == .unreadable)
        #expect(settings.problem != nil)
        #expect(settings.problem?.contains("Keychain") == true)
    }
}
