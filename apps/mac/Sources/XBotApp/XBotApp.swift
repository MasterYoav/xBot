import SwiftUI
import XBotCore
import XBotEngine
import XBotUI

@main
struct XBotApp: App {
    /// The stub, for now.
    ///
    /// docs/12-roadmap.md M4 is explicit that the app is finished against `StubEngineClient` before
    /// it is pointed at a real engine, and the reason is not convenience: it is that a UI built
    /// against a live server quietly grows dependencies on that server's timing, and those only
    /// show up on somebody else's slower machine. M5 swaps this line.
    @State private var state = AppState(engine: StubEngineClient())

    var body: some Scene {
        Window("xBot", id: "main") {
            MainWindow()
                .environment(state)
        }
        .defaultSize(Metrics.minimumWindow)
        .windowToolbarStyle(.unified)
    }
}
