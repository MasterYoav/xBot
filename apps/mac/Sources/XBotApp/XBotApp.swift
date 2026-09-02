import SwiftUI
import XBotCore
import XBotEngine
import XBotRuntime
import XBotUI

@main
struct XBotApp: App {
    /// M5's swap: the app drives a real `RuntimeController`. M3's published digest manifest is still
    /// open; the dev image (`scripts/build-engine-image.sh`) covers local runtime testing.
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

        let keyEncryptionKey: String
        do {
            keyEncryptionKey = try KeyEncryptionKeyStore.key()
        } catch {
            keyEncryptionKey = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
                .base64EncodedString()
        }

        let engineToken: String
        do {
            engineToken = try EngineTokenStore.token()
        } catch {
            // Keychain unavailable — still run for this launch, but the token will not survive
            // relaunch and nothing else on the machine can guess it mid-session.
            engineToken = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
                .base64EncodedString()
        }

        return AppState(
            runtime: runtime,
            environment: { port, hostGateway in
                EngineEnvironment.compose(
                    EngineEnvironment.Inputs(
                        port: port,
                        keyEncryptionKey: keyEncryptionKey,
                        hostGateway: hostGateway,
                        appOrigin: "xbot://app",
                        engineToken: engineToken
                        // No `intelligence:` — local-history mode, which ADR-0007's M1 seam
                        // already verified boots on its own, with no CopilotKit account.
                    )
                )
            },
            engineFactory: { endpoint in
                HTTPEngineClient(baseURL: endpoint.baseURL, token: engineToken)
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
