import Foundation
import Observation

/// Settings → Models, the CopilotKit section: the one key that is not a model's.
///
/// It had no home. The key is collected once during onboarding and was then unreachable — nowhere
/// to see it, replace it when it expires, or take it back. The only route left was Keychain Access,
/// which is the terminal-shaped hole invariant 1 exists to close.
///
/// It also made an existing button a dead end: without a key the composer says "Connect a
/// CopilotKit key so xBot can keep your conversations" and offers **Open Settings**, and Settings
/// had no field to connect one in. A person following that instruction arrived nowhere.
@MainActor
@Observable
public final class ConversationStoreSettings {
    public private(set) var state: ConversationStore = .notConnected
    public private(set) var problem: String?

    /// Injected so a test is not deciding against this machine's own Keychain — the same reason
    /// `ProviderConnectionStore` is injected.
    private let read: @Sendable () -> ConversationStore
    private let write: @Sendable (String) throws -> Void
    private let clear: @Sendable () throws -> Void

    public init(
        read: @escaping @Sendable () -> ConversationStore = { EngineBootstrap.conversationStore },
        write: @escaping @Sendable (String) throws -> Void = {
            try IntelligenceCredentialStore.save(apiKey: $0)
        },
        clear: @escaping @Sendable () throws -> Void = {
            try IntelligenceCredentialStore.removeAPIKey()
        }
    ) {
        self.read = read
        self.write = write
        self.clear = clear
    }

    public func load() {
        state = read()
        // An unreadable key is a Keychain problem, and the section says so rather than offering to
        // connect a key that is already there.
        problem = state == .unreadable
            ? String(localized: "The Keychain wouldn't hand over your key. It may be locked.")
            : nil
    }

    public func connect(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try write(trimmed)
            problem = nil
        } catch {
            // Never silently. A key the person pasted and that did not save is the worst outcome:
            // they believe it is connected and the engine keeps booting without it.
            problem = String(localized: "That key couldn't be saved to your Keychain.")
        }
        state = read()
    }

    public func disconnect() {
        do {
            try clear()
            problem = nil
        } catch {
            problem = String(localized: "That key couldn't be removed from your Keychain.")
        }
        state = read()
    }

    /// What the section says about itself. The engine has to be restarted for a change to land,
    /// because the four variables are read at container start — so say that rather than letting
    /// somebody paste a key and wonder why the next message still fails.
    public var needsEngineRestart: Bool { state == .ready }
}
