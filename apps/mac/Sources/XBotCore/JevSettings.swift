import Foundation
import Observation
import XBotBrain

/// Where the Jev key is kept: the Keychain in the app, memory in tests (the login Keychain is one
/// per user, and parallel suites would share it).
public protocol JevKeyStore: Sendable {
    func read() -> String?
    func save(_ key: String) throws
    func remove() throws
}

/// The TypeSafe Jev API key, in the login Keychain and nowhere else (CLAUDE.md, invariant 2).
public struct KeychainJevKeyStore: JevKeyStore {
    public static let service = "dev.xbot.jev"
    static let account = "api-key"
    public init() {}
    public func read() -> String? { (try? KeychainSecretStore.readExisting(service: Self.service, account: Self.account)) ?? nil }
    public func save(_ key: String) throws { try KeychainSecretStore.write(key, service: Self.service, account: Self.account) }
    public func remove() throws { try KeychainSecretStore.remove(service: Self.service, account: Self.account) }
}

/// Settings › AI › TypeSafe Jev: the key (Keychain only: shown as saved, with its length), the
/// model, Check, and the Jev Workflows toggle (user defaults; off by default). Off, nothing in
/// xBot calls Jev.
@MainActor
@Observable
public final class JevSettings {
    public enum CheckResult: Equatable, Sendable {
        case checking
        case answered(milliseconds: Int)
        case failed(String)

        public var sentence: String {
            switch self {
            case .checking: String(localized: "Asking Jev…")
            case .answered(let ms): String(localized: "Jev answered in \(ms) ms.")
            case .failed(let why): why
            }
        }
    }

    static let workflowsKey = "jev.workflows"
    static let modelKey = "jev.model"

    /// Jev Workflows: the Workflows page, Let Jev choose in chats, and every call to Jev.
    public var workflowsEnabled: Bool {
        didSet { defaults.set(workflowsEnabled, forKey: Self.workflowsKey) }
    }

    /// "jev-latest", or a pinned version. Blank goes back to "jev-latest".
    public var model: String {
        didSet {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == JevClient.defaultModel {
                defaults.removeObject(forKey: Self.modelKey)
            } else {
                defaults.set(trimmed, forKey: Self.modelKey)
            }
        }
    }

    public private(set) var checkResult: CheckResult?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keys: any JevKeyStore
    @ObservationIgnored let transport: JevClient.Transport
    /// The key's length, read once when first asked for (not at launch: the headless helper and
    /// most of the app never need it). The double optional: not read yet, or read and absent.
    @ObservationIgnored private var cachedLength: Int??
    private var keyRevision = 0

    public init(defaults: UserDefaults = .standard, keys: any JevKeyStore = KeychainJevKeyStore(),
                transport: @escaping JevClient.Transport = JevClient.urlSession) {
        self.defaults = defaults
        self.keys = keys
        self.transport = transport
        workflowsEnabled = defaults.bool(forKey: Self.workflowsKey)
        model = defaults.string(forKey: Self.modelKey) ?? JevClient.defaultModel
    }

    /// The model a call asks for.
    public var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? JevClient.defaultModel : trimmed
    }

    /// How long the saved key is; nil when none is saved. Never the key itself.
    public var keyLength: Int? {
        _ = keyRevision
        if cachedLength == nil { cachedLength = .some(keys.read()?.count) }
        return cachedLength ?? nil
    }

    public var hasKey: Bool { keyLength != nil }

    /// Saves the key to the store, trimmed. False when it's blank or the store refused it.
    @discardableResult
    public func saveKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (try? keys.save(trimmed)) != nil else { return false }
        cachedLength = .some(trimmed.count)
        keyRevision += 1
        checkResult = nil
        return true
    }

    public func removeKey() {
        try? keys.remove()
        cachedLength = .some(nil)
        keyRevision += 1
        checkResult = nil
    }

    /// A client with the saved key and model; nil without a key.
    public func client(timeout: Duration = .seconds(10)) -> JevClient? {
        guard let key = keys.read(), !key.isEmpty else { return nil }
        return JevClient(key: key, model: effectiveModel, timeout: timeout, transport: transport)
    }

    /// One tiny yes/no question, timed.
    public func check() async {
        guard let client = client() else {
            checkResult = .failed(JevError.noKey.sentence)
            return
        }
        checkResult = .checking
        let clock = ContinuousClock()
        let started = clock.now
        do {
            _ = try await client.ask(state: "xBot is checking that its Jev key works.",
                                     questions: ["ok": .noul("Is this a connection check?")])
            let elapsed = clock.now - started
            let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            checkResult = .answered(milliseconds: ms)
        } catch {
            checkResult = .failed(error.sentence)
        }
    }
}

extension JevSettings: CustomStringConvertible {
    /// Never the key: only whether one is saved.
    public nonisolated var description: String { "JevSettings" }
}
