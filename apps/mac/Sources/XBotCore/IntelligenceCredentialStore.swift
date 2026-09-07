import Foundation
import XBotRuntime

/// The CopilotKit Intelligence credentials the engine needs to keep history.
///
/// ADR-0007 keeps Intelligence for v1: "The app ships with an Intelligence key configured at
/// onboarding alongside the model key." Without it `runtimeCapabilities()` selects local mode,
/// whose client is a spike that throws on everything past wiring — so a conversation cannot work.
///
/// Four variables are required and only one of them needs a person:
///
/// - the two URLs are CopilotKit's own endpoints and are constants here, because asking somebody to
///   type a service's address is asking them to get it wrong,
/// - `COPILOTKIT_LICENSE_TOKEN` is **not a licence gate**. ADR-0007 measured it: "runtime.mjs stores
///   it and derives a telemetry id from it. Nothing validates it." Upstream's own instructions get
///   one from `npx copilotkit license`, which would put a terminal in the middle of onboarding and
///   break invariant 1 for a value nothing checks. So one is generated per install and kept in the
///   Keychain, which is what it is for.
/// - the API key is the one real credential, and it is pasted like any model key.
public enum IntelligenceCredentialStore: Sendable {
    private static let keyService = "dev.xbot.intelligence-key"
    private static let licenceService = "dev.xbot.copilotkit-license"

    /// CopilotKit's hosted endpoints, from `engine/.env.example`.
    public static let apiURL = "https://api.intelligence.copilotkit.ai"
    public static let gatewayWebSocketURL = "wss://realtime.intelligence.copilotkit.ai"

    /// The pasted key, or nil when nobody has connected one.
    public static func apiKey() throws -> String? {
        try KeychainSecretStore.readExisting(service: keyService, account: "default")
    }

    public static func save(apiKey: String) throws {
        let normalized = ProviderKeyStore.normalize(apiKey)
        guard !normalized.isEmpty else { return }
        try KeychainSecretStore.write(normalized, service: keyService, account: "default")
    }

    public static func removeAPIKey() throws {
        try KeychainSecretStore.remove(service: keyService, account: "default")
    }

    /// Generated once per install and kept. Telemetry, not a gate — see the type's note.
    public static func licenseToken() throws -> String {
        try KeychainSecretStore.string(service: licenceService)
    }

    public static func removeLicenseToken() throws {
        try KeychainSecretStore.remove(service: licenceService, account: "default")
    }

    /// What the engine needs, or nil when no key has been connected.
    ///
    /// Nil rather than a half-filled block on purpose: `runtimeCapabilities()` throws on a partial
    /// set — deliberately, because somebody who set two of four meant to use Intelligence and got
    /// it wrong — so the choice here is all four or none.
    public static func settings() -> EngineEnvironment.Intelligence? {
        guard let key = (try? apiKey()) ?? nil, !key.isEmpty,
              let licence = try? licenseToken(), !licence.isEmpty
        else { return nil }
        return EngineEnvironment.Intelligence(
            apiURL: apiURL,
            gatewayWsURL: gatewayWebSocketURL,
            apiKey: key,
            licenseToken: licence
        )
    }
}
