import Foundation
import Observation

/// What one provider row in Settings → Models is currently showing.
public enum ProviderConnectionState: Sendable, Equatable {
    /// No key stored. The row offers Connect.
    case notConnected
    /// A key is stored and was accepted. The count is what the vendor's model list returned.
    case connected(modelCount: Int)
    /// Validating right now — the row is busy and its field is disabled.
    case checking
    /// The vendor refused, or could not be reached. Carries the sentence to show.
    case failed(message: String)
    /// Ollama only: found on this Mac, with the models the person has already pulled.
    case detectedLocally(modelCount: Int)
    /// Ollama only: nothing answered on the local port.
    case notDetected
}

public struct ProviderRow: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let needsKey: Bool
    public var state: ProviderConnectionState

    public var isConnected: Bool {
        switch state {
        case .connected, .detectedLocally: true
        default: false
        }
    }
}

/// Settings → Models: which providers are connected, and connecting or disconnecting one.
///
/// The logic lives here rather than in the view because it is the part with rules — a key is
/// validated before it is stored, a rejected key is never stored at all, and disconnecting has to
/// remove the Keychain entry as well as the connection flag or the next launch shows a provider
/// the person thought they had removed.
///
/// Every dependency is injected. Between them they are the Keychain, the network and the
/// preference domain, and a settings screen whose tests need all three to be real is a settings
/// screen with no tests.
@MainActor
@Observable
public final class ModelSettingsState {
    public private(set) var rows: [ProviderRow] = []

    private let validator: ModelProviderValidator
    private let vault: ProviderKeyVault
    private let connections: ProviderConnectionStore

    public init(
        validator: ModelProviderValidator = ModelProviderValidator(),
        vault: ProviderKeyVault = .keychain,
        connections: ProviderConnectionStore = .shared
    ) {
        self.validator = validator
        self.vault = vault
        self.connections = connections
        rows = ModelProviderCatalog.all.map {
            ProviderRow(
                id: $0.id,
                name: $0.name,
                subtitle: $0.subtitle,
                needsKey: $0.needsKey,
                state: $0.needsKey ? .notConnected : .notDetected
            )
        }
    }

    /// What is connected right now, without asking any vendor.
    ///
    /// Reads the Keychain, not the connection flags: the key is the connection. Somebody who
    /// connected a provider and then quit before onboarding finished still has a working key, and
    /// a screen that showed it as not connected would invite them to paste it a second time.
    public func load() {
        for index in rows.indices where rows[index].needsKey {
            let stored = (try? vault.key(rows[index].id)) ?? nil
            // Zero rather than a remembered count: the number comes from the vendor, and this
            // path deliberately asks nobody. `refreshCounts()` fills it in.
            rows[index].state = stored == nil ? .notConnected : .connected(modelCount: 0)
        }
    }

    /// Ollama, which is detected rather than configured — docs/04-model-providers.md.
    ///
    /// Separate from `load()` because it is the one row that costs a network call to answer, and
    /// because it must never present as something to configure. Not found is a state, not an error.
    public func detectLocalProviders() async {
        guard let index = rows.firstIndex(where: { !$0.needsKey }) else { return }
        let found = await validator.detectOllama()
        guard case .valid(let count)? = found else {
            rows[index].state = .notDetected
            return
        }
        rows[index].state = .detectedLocally(modelCount: count)
        connections.markConnected(rows[index].id)
    }

    /// Validate a key against the vendor, and store it only if the vendor accepted it.
    ///
    /// The order is the point. Storing first and validating after leaves a rejected key in the
    /// Keychain, so the composer unblocks, the agent's first message fails, and the settings screen
    /// says the provider is connected — three lies from one wrong sequence.
    public func connect(providerID: String, key: String) async {
        guard let index = rows.firstIndex(where: { $0.id == providerID }) else { return }
        let normalized = ProviderKeyStore.normalize(key)
        guard !normalized.isEmpty else {
            rows[index].state = .failed(message: String(localized: "Paste a key to connect."))
            return
        }

        rows[index].state = .checking
        let result = await validator.validate(providerID: providerID, key: normalized)

        switch result {
        case .valid(let count):
            do {
                try vault.save(normalized, providerID)
            } catch {
                // Never the underlying error: a Keychain failure's description can carry the item
                // it was operating on. docs/10-security.md — a key never reaches a message.
                rows[index].state = .failed(
                    message: String(localized: "The key couldn't be saved to your Keychain.")
                )
                return
            }
            connections.markConnected(providerID)
            rows[index].state = .connected(modelCount: count)
        case .invalid(let message):
            rows[index].state = .failed(message: message)
        }
    }

    /// Forget a provider: the key first, then the flag.
    ///
    /// If removal throws, the row stays connected and says so rather than showing a provider as
    /// gone while its key is still in the Keychain.
    public func disconnect(providerID: String) {
        guard let index = rows.firstIndex(where: { $0.id == providerID }) else { return }
        do {
            try vault.remove(providerID)
        } catch {
            rows[index].state = .failed(
                message: String(localized: "That key couldn't be removed from your Keychain.")
            )
            return
        }
        rows[index].state = .notConnected
    }
}
