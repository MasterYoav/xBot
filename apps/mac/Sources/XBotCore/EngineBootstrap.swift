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

        return { port, hostGateway in
            EngineEnvironment.compose(
                EngineEnvironment.Inputs(
                    port: port,
                    keyEncryptionKey: keyEncryptionKey,
                    hostGateway: hostGateway,
                    appOrigin: "xbot://app",
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
            health: { endpoint in
                await HTTPEngineClient(baseURL: endpoint.baseURL).health()
            }
        )
    }

    private static func loadKeyEncryptionKey() -> String {
        (try? KeyEncryptionKeyStore.key()) ?? ""
    }

    private static func loadEngineToken() -> String {
        (try? EngineTokenStore.token()) ?? ""
    }
}
