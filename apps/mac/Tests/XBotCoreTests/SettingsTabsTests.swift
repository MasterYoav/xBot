import Foundation
import Testing
import XBotEngine
@testable import XBotCore

@Suite struct ActionPolicyDecodingTests {
    @Test func decodesPolicyEnvelope() throws {
        let json = """
        {"policy":{"mode":"enforce","deny":["true == false"],"allow":["true"]}}
        """
        struct Envelope: Decodable { let policy: ActionPolicy }
        let policy = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).policy
        #expect(policy.mode == .enforce)
        #expect(policy.deny == ["true == false"])
    }
}

@Suite struct AgentDefaultsStoreTests {
    @Test func roundTripsDescriptionAndModel() {
        // In memory, not a `UserDefaults(suiteName:)`. A suite name is a plist in the developer's
        // ~/Library/Preferences, and a test suite should leave nothing behind on the machine that
        // ran it.
        let defaults = MemoryDefaults()

        AgentDefaultsStore.saveRoleDescription("Research the web", defaults: defaults)
        let model = ModelSelection(
            provider: "Anthropic",
            providerID: "anthropic",
            model: "claude-sonnet-4-5",
            capabilities: ["tools"]
        )
        AgentDefaultsStore.saveDefaultModel(model, defaults: defaults)

        #expect(AgentDefaultsStore.roleDescription(defaults: defaults) == "Research the web")
        #expect(AgentDefaultsStore.defaultModel(defaults: defaults) == model)
    }
}

@Suite struct ComputerPolicyPresetTests {
    @Test func presetsHaveDistinctRules() {
        let rules = Set(ComputerPolicyPreset.allCases.map(\.rule))
        #expect(rules.count == ComputerPolicyPreset.allCases.count)
    }
}
