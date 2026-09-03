import Testing
@testable import XBotCore

@Suite(.serialized)
struct RuntimeChoiceStoreTests {
    @Test func recordsRuntimePath() {
        defer { RuntimeChoiceStore.reset() }
        RuntimeChoiceStore.reset()
        #expect(RuntimeChoiceStore.choice == nil)
        RuntimeChoiceStore.markColimaInstalled()
        #expect(RuntimeChoiceStore.choice == .colimaInstalled)
        RuntimeChoiceStore.markDockerManual()
        #expect(RuntimeChoiceStore.choice == .dockerManual)
    }
}
