import Foundation
import Testing
import XBotEngine
@testable import XBotCore

/// The row that covers everything not on the vendor list.
@Suite @MainActor
struct CustomProviderStoreTests {
    private func store() -> CustomProviderStore {
        CustomProviderStore(defaults: MemoryDefaults())
    }

    @Test func providersRoundTripThroughStorage() {
        let store = store()
        let gateway = CustomProvider(
            name: "Work gateway",
            baseURL: "https://ai.corp.example/v1",
            model: "gpt-4o"
        )
        store.add(gateway)

        #expect(store.all.count == 1)
        #expect(store.all.first?.name == "Work gateway")
        #expect(store.all.first?.baseURL == "https://ai.corp.example/v1")
        #expect(store.all.first?.model == "gpt-4o")
    }

    @Test func addingTheSameIdReplacesRatherThanDuplicates() {
        let store = store()
        var provider = CustomProvider(name: "Gateway", baseURL: "https://a.example/v1", model: "m")
        store.add(provider)
        provider.name = "Renamed"
        store.add(provider)

        #expect(store.all.count == 1)
        #expect(store.all.first?.name == "Renamed")
    }

    @Test func removingTakesOnlyTheOneNamed() {
        let store = store()
        let a = CustomProvider(name: "A", baseURL: "https://a.example/v1", model: "m")
        let b = CustomProvider(name: "B", baseURL: "https://b.example/v1", model: "m")
        store.add(a)
        store.add(b)

        store.remove(id: a.id)

        #expect(store.all.map(\.name) == ["B"])
    }

    @Test func aStoredRecordThatCannotBeReadIsSkippedRatherThanFatal() {
        // A record written by a future build, or edited by hand. One unreadable row must not take
        // the whole settings screen down with it.
        let defaults = MemoryDefaults()
        defaults.set(["not json", #"{"id":"custom:1","name":"O","baseURL":"https://o.example","model":"m"}"#],
                     forKey: "xbot.customProviders")
        #expect(CustomProviderStore(defaults: defaults).all.map(\.name) == ["O"])
    }
}

@Suite
struct CustomProviderValidationTests {
    @Test func aNameAndAUrlAreBothRequired() {
        #expect(CustomProviderStore.problem(name: "  ", baseURL: "https://a.example", hasKey: false) == .nameMissing)
        #expect(CustomProviderStore.problem(name: "A", baseURL: "  ", hasKey: false) == .urlMissing)
    }

    @Test func theUrlHasToBeOne() {
        for bad in ["not a url", "ftp://a.example", "example.com", "https://"] {
            #expect(
                CustomProviderStore.problem(name: "A", baseURL: bad, hasKey: false) == .urlMalformed,
                "\(bad) should not be accepted"
            )
        }
    }

    @Test func aGoodHttpsEndpointIsAccepted() {
        #expect(
            CustomProviderStore.problem(
                name: "Work gateway",
                baseURL: "https://ai.corp.example/v1",
                hasKey: true
            ) == nil
        )
    }

    /// A key sent to a plain-http address crosses the network in clear text. The Keychain exists so
    /// the key is not readable by anything that has not been asked, and this is the same promise.
    @Test func aKeyIsRefusedOverPlainHttpToAnotherMachine() {
        #expect(
            CustomProviderStore.problem(
                name: "Gateway",
                baseURL: "http://ai.corp.example/v1",
                hasKey: true
            ) == .insecureKeyOverPlainHTTP
        )
    }

    /// Loopback never leaves the machine, and it is exactly where a local Ollama or LM Studio sits.
    /// Refusing here would block the case a privacy-minded person is most likely to have.
    @Test func plainHttpIsFineOnLoopback() {
        for host in ["localhost", "127.0.0.1", "host.docker.internal"] {
            #expect(
                CustomProviderStore.problem(
                    name: "Local",
                    baseURL: "http://\(host):11434/v1",
                    hasKey: true
                ) == nil,
                "\(host) is this machine"
            )
        }
    }

    @Test func plainHttpWithNoKeyIsNotASecurityProblem() {
        // Nothing secret crosses the wire, so there is nothing to refuse.
        #expect(
            CustomProviderStore.problem(
                name: "Gateway",
                baseURL: "http://ai.corp.example/v1",
                hasKey: false
            ) == nil
        )
    }
}

/// A credential hidden in the endpoint address.
@Suite
struct CustomProviderURLCredentialTests {
    /**
     Refused, not stored and redacted later.

     A custom provider's address lives in the preference domain — a plist the person, and anything
     running as them, can open. CLAUDE.md's second invariant is that keys live in the Keychain and
     "never in `UserDefaults`, never in a plist, never in a file the user could open", and
     `CustomProviderStore`'s own note says names and endpoints live in preferences while keys never
     do. `https://user:secret@host` is the hole in exactly that sentence, and pasting one is an easy
     thing to do — it is how several gateways document themselves.
     */
    @Test func anAddressCarryingACredentialIsRefused() {
        for url in [
            "https://user:secret@gateway.example.com/v1",
            "https://token@gateway.example.com/v1",
            "http://user:secret@localhost:1234/v1",
        ] {
            #expect(
                CustomProviderStore.problem(name: "Gateway", baseURL: url, hasKey: false)
                    == .urlCarriesCredentials,
                "\(url) should be refused"
            )
        }
    }

    /// Checked before the transport rule: a credential in the address is wrong over https too, so
    /// answering "use https" first would send somebody to fix the wrong half.
    @Test func theCredentialIsReportedBeforeTheInsecureTransport() {
        #expect(
            CustomProviderStore.problem(
                name: "Gateway",
                baseURL: "http://user:secret@gateway.example.com/v1",
                hasKey: true
            ) == .urlCarriesCredentials
        )
    }

    @Test func anOrdinaryAddressIsStillAccepted() {
        #expect(
            CustomProviderStore.problem(
                name: "Gateway",
                baseURL: "https://openrouter.ai/api/v1",
                hasKey: true
            ) == nil
        )
        // The loopback case this validator exists to keep working.
        #expect(
            CustomProviderStore.problem(
                name: "Ollama",
                baseURL: "http://localhost:11434/v1",
                hasKey: true
            ) == nil
        )
    }
}
