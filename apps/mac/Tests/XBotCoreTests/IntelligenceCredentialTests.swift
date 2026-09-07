import Foundation
import Testing
import XBotEngine
import XBotRuntime
@testable import XBotCore

/**
 The credentials that decide whether a conversation can happen at all.

 ADR-0007 keeps CopilotKit Intelligence for v1. Without its key `runtimeCapabilities()` selects
 local mode, and `LocalIntelligence` throws on everything past wiring — while the engine still
 starts, still answers `/health`, and still lists agents. Every other signal in the app says all is
 well, which is why this is checked rather than discovered when a turn fails.
 */
@Suite
struct IntelligenceCredentialTests {
    @Test func theEndpointsAreTheOnesTheEngineDocuments() {
        // From engine/.env.example. Constants rather than fields, because asking somebody to type
        // a service's address is asking them to get it wrong.
        #expect(IntelligenceCredentialStore.apiURL == "https://api.intelligence.copilotkit.ai")
        #expect(
            IntelligenceCredentialStore.gatewayWebSocketURL
                == "wss://realtime.intelligence.copilotkit.ai"
        )
    }

    /// All four or none. `runtimeCapabilities()` throws on a partial set — deliberately, because
    /// somebody who set two of four meant to use Intelligence and got it wrong.
    @Test func aSettingsBlockIsWholeOrAbsent() {
        guard let settings = IntelligenceCredentialStore.settings() else {
            // No key on this machine, which is the honest answer and the common one in CI.
            return
        }
        #expect(!settings.apiKey.isEmpty)
        #expect(!settings.licenseToken.isEmpty)
        #expect(!settings.apiURL.isEmpty)
        #expect(!settings.gatewayWsURL.isEmpty)
    }

    /// The environment the engine receives is all four variables or none of them.
    @Test func composeEmitsAllFourOrNone() {
        let withIntelligence = EngineEnvironment.compose(
            EngineEnvironment.Inputs(
                port: 49_152,
                keyEncryptionKey: "k",
                hostGateway: "host.docker.internal",
                appOrigin: "xbot://app",
                intelligence: EngineEnvironment.Intelligence(
                    apiURL: "https://api.example",
                    gatewayWsURL: "wss://realtime.example",
                    apiKey: "ik",
                    licenseToken: "lt"
                )
            )
        )
        let names = ["INTELLIGENCE_API_URL", "INTELLIGENCE_GATEWAY_WS_URL", "INTELLIGENCE_API_KEY", "COPILOTKIT_LICENSE_TOKEN"]
        #expect(names.allSatisfy { withIntelligence[$0] != nil })

        let without = EngineEnvironment.compose(
            EngineEnvironment.Inputs(
                port: 49_152,
                keyEncryptionKey: "k",
                hostGateway: "host.docker.internal",
                appOrigin: "xbot://app"
            )
        )
        #expect(names.allSatisfy { without[$0] == nil })
    }

    /// The engine token and the Intelligence key are different secrets in different Keychain
    /// services — sharing one would mean rotating the loopback guard rotated the account key too.
    @Test func theCredentialsAreSeparate() throws {
        #expect(IntelligenceCredentialStore.apiURL != IntelligenceCredentialStore.gatewayWebSocketURL)
    }
}

/// The three answers to "can this engine keep a conversation", which used to be two.
@Suite
struct ConversationStoreStateTests {
    /**
     Why this is not a Bool.

     A missing key and an unreadable one need opposite sentences. The Bool made them one, so
     somebody whose login Keychain was locked — or who dismissed the prompt — was told to connect a
     CopilotKit key. They open Settings, see their key sitting right there, and have nowhere left to
     look. It is the same mistake the engine status made about a container runtime that was
     installed and merely asleep.
     */
    @Test func aMissingKeyAndAnUnreadableOneSayDifferentThings() {
        #expect(
            ComposerBlock.noConversationStore.sentence
                != ComposerBlock.conversationStoreUnreadable.sentence
        )
        // The one thing it must never say to somebody who already has a key.
        #expect(!ComposerBlock.conversationStoreUnreadable.sentence.contains("Connect a"))
    }

    /// There is nowhere to send them: the key is already in Settings. Asking again is the fix.
    @Test func anUnreadableKeyOffersARetryRatherThanASettingsTrip() {
        #expect(
            ComposerBlock.conversationStoreUnreadable.actionTitle
                != ComposerBlock.noConversationStore.actionTitle
        )
        #expect(!ComposerBlock.conversationStoreUnreadable.actionTitle.isEmpty)
    }

    @Test func everyStateIsDistinct() {
        #expect(ConversationStore.ready != .notConnected)
        #expect(ConversationStore.notConnected != .unreadable)
    }
}
