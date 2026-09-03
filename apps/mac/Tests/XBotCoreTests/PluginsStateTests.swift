import Testing
import XBotCore
import XBotEngine

@Suite @MainActor struct PluginsStateTests {
    @Test func togglingAGrantUpdatesPluginState() async {
        let state = AppState(engine: StubEngineClient())
        await state.load()
        state.select("orchestrator")
        await state.refreshPluginsData()

        let before = state.grantedPlugins?.tools.count ?? 0
        #expect(before == 1)

        await state.setPluginGrant(kind: .mcp, ref: "google-drive/read_file", enabled: true)
        #expect(state.grantedPlugins?.tools.count == 2)

        await state.setPluginGrant(kind: .mcp, ref: "google-drive/search_files", enabled: false)
        #expect(state.grantedPlugins?.tools.count == 1)
        #expect(state.grantedPlugins?.tools.first?.ref == "google-drive/read_file")
    }
}
