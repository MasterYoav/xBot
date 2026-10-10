import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@MainActor @Suite struct TabOrderTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "tabs-\(UUID().uuidString)")

    func threeTabs() async throws -> (Workspace, [UUID]) {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: SequenceBrain([], fallback: [.done])] })
        await w.refreshHarnesses()
        let ids = try (0..<3).map { _ in try #require(w.newChat(in: nil)).id }
        return (w, ids)
    }

    @Test func aTabMovesToWhereItWasDropped() async throws {
        let (w, ids) = try await threeTabs()
        w.moveTab(ids[0], to: 2)
        #expect(w.openChatIDs == [ids[1], ids[2], ids[0]])
        w.moveTab(ids[0], to: 0)
        #expect(w.openChatIDs == ids)
        w.moveTab(ids[2], to: 1)
        #expect(w.openChatIDs == [ids[0], ids[2], ids[1]])
    }

    /// ⌘1…⌘9 follow the new order: they are positions, not chats.
    @Test func numberShortcutsFollowTheNewOrder() async throws {
        let (w, ids) = try await threeTabs()
        w.moveTab(ids[2], to: 0)
        w.openTab(at: 0)
        #expect(w.selectedChatID == ids[2])
    }

    @Test func movingKeepsTheSelectionAndIgnoresNonsense() async throws {
        let (w, ids) = try await threeTabs()
        w.open(ids[1])
        w.moveTab(ids[1], to: 99)
        #expect(w.openChatIDs == [ids[0], ids[2], ids[1]])
        #expect(w.selectedChatID == ids[1])
        w.moveTab(UUID(), to: 0)
        w.moveTab(ids[0], to: -3)
        #expect(w.openChatIDs == [ids[0], ids[2], ids[1]])
    }
}
