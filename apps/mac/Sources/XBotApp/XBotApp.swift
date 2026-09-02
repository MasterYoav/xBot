import SwiftUI
import XBotCore
import XBotEngine
import XBotRuntime
import XBotUI

@main
struct XBotApp: App {
    /// M5's swap: the app now drives a real `RuntimeController`, not `StubEngineClient`. What is
    /// still missing is M3's — an actual published `xbot/engine` image, so `DockerDriver` has
    /// something to pull, and the Keychain-backed encryption key from docs/10-security.md, so the
    /// one generated below survives a relaunch. Until both land, this walks the real state machine
    /// honestly and stops at a real, sentence-bearing failure rather than a fake success.
    @State private var state: AppState

    init() {
        #if DEBUG
        // Default in debug builds: the stub, so `swift run` shows the designed conversation
        // without Docker. Set XBOT_USE_RUNTIME=1 to exercise the real runtime path instead.
        if ProcessInfo.processInfo.environment["XBOT_USE_RUNTIME"] != "1" {
            _state = State(wrappedValue: AppState(engine: StubEngineClient()))
            return
        }
        #endif
        _state = State(wrappedValue: Self.productionState())
    }

    /// Release always takes this path. Debug takes it when `XBOT_USE_RUNTIME=1`.
    private static func productionState() -> AppState {
        let runtime = RuntimeController(
            driver: DockerDriver(),
            // A placeholder repository and tag. M3's pinned-digest manifest (docs/10-security.md)
            // replaces this; nothing here should be read as the shape that ships.
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { endpoint in await HTTPEngineClient(baseURL: endpoint.baseURL).isHealthy() }
        )

        // Generated per launch, held only in memory. This is a known, called-out gap rather than a
        // silent one: nothing yet encrypts a credential vault with it, because the vault itself
        // (M2, the model router) hasn't landed either. It stops being fine the day M2 does, and the
        // fix is the Keychain-backed key docs/10-security.md already specifies, not a change here.
        let keyEncryptionKey = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
            .base64EncodedString()

        return AppState(
            runtime: runtime,
            environment: { port, hostGateway in
                EngineEnvironment.compose(
                    EngineEnvironment.Inputs(
                        port: port,
                        keyEncryptionKey: keyEncryptionKey,
                        hostGateway: hostGateway,
                        appOrigin: "xbot://app"
                        // No `intelligence:` — local-history mode, which ADR-0007's M1 seam
                        // already verified boots on its own, with no CopilotKit account.
                    )
                )
            }
        )
    }

    var body: some Scene {
        Window("xBot", id: "main") {
            MainWindow()
                .environment(state)
        }
        .defaultSize(Metrics.minimumWindow)
        .windowToolbarStyle(.unified)
    }
}
