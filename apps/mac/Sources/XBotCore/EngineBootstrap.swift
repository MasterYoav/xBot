import Foundation
import XBotEngine
import XBotRuntime

/// Shared wiring for a production engine — used by the main app and onboarding.
///
/// Keychain reads and environment composition live here so neither call site duplicates the
/// security decisions about generated keys and bearer tokens.
public enum EngineBootstrap {
    public static let devImage = ImageReference(repository: "xbot/engine", tag: "1")

    /// Environment block the container receives. Port and host gateway vary per start.
    public static func environmentFactory(
        keyEncryptionKey: @escaping @Sendable () -> String = { (try? KeyEncryptionKeyStore.key()) ?? "" },
        engineToken: @escaping @Sendable () -> String = { (try? EngineTokenStore.token()) ?? "" }
    ) -> @Sendable (UInt16, String) -> [String: String] {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        // Read at each start, never captured when the closure is built: the app builds this
        // closure before onboarding has collected anything, so capturing the keys here would hand
        // the engine whatever the Keychain held at launch — on a first run, nothing.
        //
        // No `intelligence` is ever passed: since ADR-0008 the engine keeps conversations itself
        // (`LocalThreadRunner`), so the four INTELLIGENCE_* variables stay unset and the engine
        // picks local history on its own. See `EngineEnvironment.Inputs` if that ever changes.
        return { port, hostGateway in
            EngineEnvironment.compose(
                EngineEnvironment.Inputs(
                    port: port,
                    keyEncryptionKey: keyEncryptionKey(),
                    hostGateway: hostGateway,
                    appOrigin: "xbot://app",
                    maxBrowsers: EngineEnvironment.browserLimit(forPhysicalMemory: physicalMemory),
                    engineToken: engineToken()
                )
            )
        }
    }

    public static func runtimeController() -> RuntimeController {
        RuntimeController(
            driver: DockerDriver(executable: RuntimePaths.preferredDockerExecutable()),
            image: devImage,
            imageResolver: EngineImageResolver(),
            health: { endpoint in
                await HTTPEngineClient(baseURL: endpoint.baseURL).health()
            }
        )
    }
}
