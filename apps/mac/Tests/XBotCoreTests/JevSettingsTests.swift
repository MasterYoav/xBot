import Foundation
import Synchronization
import Testing
@testable import XBotCore

/// A key store in memory: the Keychain is one per login, and parallel suites would share it.
final class MemoryJevKeys: JevKeyStore {
    let stored: Mutex<String?>
    init(_ key: String? = nil) { stored = Mutex(key) }
    func read() -> String? { stored.withLock { $0 } }
    func save(_ key: String) throws { stored.withLock { $0 = key } }
    func remove() throws { stored.withLock { $0 = nil } }
}

func freshDefaults() -> UserDefaults {
    let name = "jev-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

func jevTransport(status: Int = 200, json: String) -> JevClient.Transport {
    { request in
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor @Suite struct JevSettingsTests {
    let secret = "tsk-live-abcdefghijklmnop"

    @Test func workflowsAreOffByDefault() {
        let settings = JevSettings(defaults: freshDefaults(), keys: MemoryJevKeys())
        #expect(settings.workflowsEnabled == false)
    }

    @Test func theToggleIsRemembered() {
        let defaults = freshDefaults()
        JevSettings(defaults: defaults, keys: MemoryJevKeys()).workflowsEnabled = true
        #expect(JevSettings(defaults: defaults, keys: MemoryJevKeys()).workflowsEnabled)
    }

    @Test func theKeyReachesOnlyTheKeyStore() {
        let defaults = freshDefaults()
        let keys = MemoryJevKeys()
        let settings = JevSettings(defaults: defaults, keys: keys)
        #expect(settings.saveKey("  \(secret)\n"))
        #expect(keys.read() == secret)
        for (_, value) in defaults.dictionaryRepresentation() {
            #expect(!String(describing: value).contains(secret))
        }
        #expect(!String(describing: settings).contains(secret))
    }

    @Test func showsThatAKeyIsSavedAndItsLengthOnly() {
        let settings = JevSettings(defaults: freshDefaults(), keys: MemoryJevKeys())
        #expect(settings.hasKey == false)
        #expect(settings.keyLength == nil)
        settings.saveKey(secret)
        #expect(settings.hasKey)
        #expect(settings.keyLength == secret.count)
    }

    @Test func aBlankKeyIsRefused() {
        let keys = MemoryJevKeys()
        let settings = JevSettings(defaults: freshDefaults(), keys: keys)
        #expect(settings.saveKey("   ") == false)
        #expect(keys.read() == nil)
    }

    @Test func removeDeletesTheKey() {
        let keys = MemoryJevKeys(secret)
        let settings = JevSettings(defaults: freshDefaults(), keys: keys)
        #expect(settings.hasKey)
        settings.removeKey()
        #expect(keys.read() == nil)
        #expect(settings.hasKey == false)
        #expect(settings.client() == nil)
    }

    @Test func theModelDefaultsToJevLatestAndCanBePinned() {
        let defaults = freshDefaults()
        let settings = JevSettings(defaults: defaults, keys: MemoryJevKeys())
        #expect(settings.model == "jev-latest")
        settings.model = "jev-1.13.0"
        #expect(JevSettings(defaults: defaults, keys: MemoryJevKeys()).model == "jev-1.13.0")
        settings.model = "  "
        #expect(JevSettings(defaults: defaults, keys: MemoryJevKeys()).model == "jev-latest")
    }

    @Test func checkSaysHowFastJevAnswered() async {
        let settings = JevSettings(defaults: freshDefaults(), keys: MemoryJevKeys(secret),
                                   transport: jevTransport(json: #"{"model":"jev-1.13.0","answers":{"ok":{"type":"noul","noul":0.99}}}"#))
        await settings.check()
        guard case .answered(let ms) = settings.checkResult else { Issue.record("\(String(describing: settings.checkResult))"); return }
        #expect(ms >= 0)
        #expect(settings.checkResult?.sentence.hasPrefix("Jev answered in ") == true)
        #expect(settings.checkResult?.sentence.hasSuffix(" ms.") == true)
    }

    @Test func checkSaysWhatWentWrongInASentence() async {
        let settings = JevSettings(defaults: freshDefaults(), keys: MemoryJevKeys(secret),
                                   transport: jevTransport(status: 401, json: "{}"))
        await settings.check()
        #expect(settings.checkResult == .failed(JevError.badKey.sentence))
        #expect(settings.checkResult?.sentence.contains(secret) == false)
    }

    @Test func checkWithoutAKeySaysSo() async {
        let settings = JevSettings(defaults: freshDefaults(), keys: MemoryJevKeys())
        await settings.check()
        #expect(settings.checkResult == .failed(JevError.noKey.sentence))
    }

    @Test func theClientUsesThePinnedModel() async throws {
        let sent = Mutex<Data?>(nil)
        let transport: JevClient.Transport = { request in
            sent.withLock { $0 = request.httpBody }
            return (Data(#"{"model":"m","answers":{}}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let settings = JevSettings(defaults: freshDefaults(), keys: MemoryJevKeys(secret), transport: transport)
        settings.model = "jev-1.13.0"
        let client = try #require(settings.client())
        _ = try await client.ask(state: "s", questions: ["q": .noul("?")])
        let body = try #require(sent.withLock { $0 })
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "jev-1.13.0")
    }

    @Test func theKeychainItemIsXBotsJevService() {
        #expect(KeychainJevKeyStore.service == "dev.xbot.jev")
    }
}
