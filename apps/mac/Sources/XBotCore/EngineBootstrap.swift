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
        engineToken: @escaping @Sendable () -> String = { (try? EngineTokenStore.token()) ?? "" },
        intelligence: @escaping @Sendable () -> EngineEnvironment.Intelligence? = { IntelligenceCredentialStore.settings() }
    ) -> @Sendable (UInt16, String) -> [String: String] {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        /*
         * Read at each start, never captured when the closure is built.
         *
         * The app builds this closure before onboarding has collected anything, so capturing the
         * keys here handed the engine whatever the Keychain held at launch — on a first run, nothing.
         * The CopilotKit key in particular: nil means the engine boots into local mode, whose client
         * throws past wiring, and that is why `conversationStore` exists — so the app can say so
         * rather than let a conversation fail with nothing to read.
         */
        return { port, hostGateway in
            EngineEnvironment.compose(
                EngineEnvironment.Inputs(
                    port: port,
                    keyEncryptionKey: keyEncryptionKey(),
                    hostGateway: hostGateway,
                    appOrigin: "xbot://app",
                    intelligence: intelligence(),
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

    /// Whether conversations can work at all.
    ///
    /// ADR-0007 keeps CopilotKit Intelligence for v1, so without its key `runtimeCapabilities()`
    /// picks local mode and `LocalIntelligence` — a spike that throws past wiring. An engine in that
    /// state starts and answers `/health` and looks entirely well, which is exactly why the app has
    /// to check rather than wait for a turn to fail — and three states rather than a Bool, because a
    /// key nobody connected and a key the Keychain will not hand over need opposite sentences.
    public static var conversationStore: ConversationStore {
        switch IntelligenceCredentialStore.availability() {
        case .connected: .ready
        case .notConnected: .notConnected
        case .unreadable: .unreadable
        }
    }


}

/// Whether the engine can keep a conversation, and if not, why not.
///
/// Its own type rather than a `Bool` because the two ways of not having a key need opposite
/// sentences: nobody connected one, or the Keychain would not hand over the one that is there. A
/// Bool told the second person to go and connect a key they could see in Settings.
public enum ConversationStore: Sendable, Equatable {
    case ready
    case notConnected
    case unreadable
}
