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
    public static func environmentFactory() -> @Sendable (UInt16, String) -> [String: String] {
        let keyEncryptionKey = loadKeyEncryptionKey()
        let engineToken = loadEngineToken()
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        /*
         * Read at start rather than captured once, so connecting a key and restarting the engine is
         * enough — no relaunch.
         *
         * Nil until somebody connects one, and nil means the engine boots into local mode, whose
         * client throws on everything past wiring. That is why `hasIntelligence` exists: the app has
         * to be able to say so rather than let a conversation fail with nothing to read.
         */
        let intelligence = IntelligenceCredentialStore.settings()

        return { port, hostGateway in
            EngineEnvironment.compose(
                EngineEnvironment.Inputs(
                    port: port,
                    keyEncryptionKey: keyEncryptionKey,
                    hostGateway: hostGateway,
                    appOrigin: "xbot://app",
                    intelligence: intelligence,
                    maxBrowsers: EngineEnvironment.browserLimit(forPhysicalMemory: physicalMemory),
                    engineToken: engineToken
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

    /// Whether conversations can work at all.
    ///
    /// ADR-0007 keeps CopilotKit Intelligence for v1, so without its key `runtimeCapabilities()`
    /// picks local mode and `LocalIntelligence` — a spike that throws past wiring. An engine in that
    /// state starts and answers `/health` and looks entirely well, which is exactly why the app has
    /// to check rather than wait for a turn to fail.
    public static var hasIntelligence: Bool { IntelligenceCredentialStore.settings() != nil }

    private static func loadKeyEncryptionKey() -> String {
        (try? KeyEncryptionKeyStore.key()) ?? ""
    }

    private static func loadEngineToken() -> String {
        (try? EngineTokenStore.token()) ?? ""
    }
}
