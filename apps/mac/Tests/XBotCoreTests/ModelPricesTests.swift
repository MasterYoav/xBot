import Foundation
import Testing
import XBotEngine
@testable import XBotCore

/// What a turn cost, and the two things docs/04-model-providers.md forbids getting wrong.
@Suite
struct ModelPricesTests {
    @Test func datedModelIdsFindTheirFamily() {
        // The picker sends `claude-haiku-4-5-20251001`. A table with a row per release goes stale
        // the week it is written, so the match is on the family prefix.
        #expect(ModelPrices.rate(for: "claude-haiku-4-5-20251001") == ModelPrices.rate(for: "claude-haiku-4"))
        #expect(ModelPrices.rate(for: "claude-sonnet-4-5")?.input == 3)
    }

    /// Nil, not zero. A model this table has never heard of has no price we could know, and a
    /// fabricated "$0.00" beside a real figure invites the reader to compare them.
    @Test func anUnknownModelHasNoPriceRatherThanAFreeOne() {
        #expect(ModelPrices.rate(for: "some-gateway-model-v3") == nil)
        #expect(
            ModelPrices.estimate(
                model: "some-gateway-model-v3", baseURL: nil,
                inputTokens: 1_000_000, outputTokens: 1_000_000
            ) == nil
        )
    }

    /// A model on the person's own machine costs no money. Reporting "$0.00" would put it in the
    /// same column as a real spend, which is the comparison to avoid making for them.
    @Test func aLocalModelIsNotPricedAtZero() {
        for host in ["http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://host.docker.internal:11434/v1"] {
            #expect(
                ModelPrices.estimate(
                    model: "claude-sonnet-4-5", baseURL: host,
                    inputTokens: 1000, outputTokens: 1000
                ) == nil,
                "\(host) runs here and costs nothing"
            )
        }
    }

    @Test func aKnownModelIsPricedPerMillionTokens() {
        // Sonnet: $3 per million in, $15 per million out.
        let estimate = ModelPrices.estimate(
            model: "claude-sonnet-4-5", baseURL: nil,
            inputTokens: 1_000_000, outputTokens: 1_000_000
        )
        #expect(estimate == 18.0)
    }
}

@Suite
struct AgentUsageTests {
    @Test func addsUpAcrossTurns() {
        var usage = AgentUsage()
        usage.add(inputTokens: 864, outputTokens: 10)
        usage.add(inputTokens: 120, outputTokens: 40)
        #expect(usage.inputTokens == 984)
        #expect(usage.outputTokens == 50)
        #expect(usage.totalTokens == 1034)
        #expect(usage.turns == 2)
    }

    @Test func aTurnWithNoModelHasNoEstimate() {
        var usage = AgentUsage()
        usage.add(inputTokens: 100, outputTokens: 100)
        #expect(usage.estimate(for: nil) == nil)
    }
}
