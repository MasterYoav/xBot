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

    /// Whether the engine can be given Intelligence, and if not, why not.
    ///
    /// Three states rather than an optional, because "nobody connected a key" and "the Keychain
    /// refused to hand one over" lead to opposite sentences. Collapsing them — which `settings()`
    /// did, with `try?` — tells somebody who already connected a key to go and connect it.
    public enum Availability: Sendable {
        case connected(EngineEnvironment.Intelligence)
        case notConnected
        /// A read failed. Usually a locked login Keychain or a denied prompt; both recoverable.
        case unreadable
    }

    public static func availability() -> Availability {
        let key: String?
        do {
            key = try apiKey()
        } catch {
            return .unreadable
        }
        guard let key, !key.isEmpty else { return .notConnected }

        // The licence token is generated on first read rather than pasted, so a failure here is
        // never "nobody set one" — it is the Keychain saying no, or refusing to be written to.
        guard let licence = try? licenseToken(), !licence.isEmpty else { return .unreadable }

        return .connected(
            EngineEnvironment.Intelligence(
                apiURL: apiURL,
                gatewayWsURL: gatewayWebSocketURL,
                apiKey: key,
                licenseToken: licence
            )
        )
    }

    /// What the engine needs, or nil when no key has been connected.
    ///
    /// Nil rather than a half-filled block on purpose: `runtimeCapabilities()` throws on a partial
    /// set — deliberately, because somebody who set two of four meant to use Intelligence and got
    /// it wrong — so the choice here is all four or none.
    public static func settings() -> EngineEnvironment.Intelligence? {
        // Nil for both of the other two: the engine takes all four variables or none, and an
        // unreadable key is not four. Which of the two it was is `availability()`'s job to say,
        // and the composer's to put in front of somebody.
        guard case .connected(let intelligence) = availability() else { return nil }
        return intelligence
    }
}
