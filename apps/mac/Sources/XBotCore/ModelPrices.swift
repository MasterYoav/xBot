import Foundation
import XBotEngine

/// What a turn cost, estimated locally from published list prices.
///
/// docs/04-model-providers.md draws the line this type exists to hold. We may show token counts,
/// because the APIs return them, and a spend estimated from a price table we maintain. We may not
/// show a percentage of a quota: the limit is the person's, with their vendor, and a meter implies
/// one we neither know nor enforce.
///
/// **An estimate, and labelled as one wherever it is shown.** List prices change, discounts and
/// batch rates exist, and cached input is billed differently. The vendor's own bill is the truth;
/// this is for noticing that an agent is expensive, not for accounting.
public enum ModelPrices: Sendable {
    /// US dollars per million tokens, by model id.
    public struct Rate: Sendable, Equatable {
        public let input: Double
        public let output: Double

        public init(input: Double, output: Double) {
            self.input = input
            self.output = output
        }
    }

    /// Matched on a prefix, so a dated id like `claude-haiku-4-5-20251001` finds its family without
    /// this table needing a row per release.
    private static let table: [(prefix: String, rate: Rate)] = [
        ("claude-opus-4", Rate(input: 15, output: 75)),
        ("claude-sonnet-4", Rate(input: 3, output: 15)),
        ("claude-haiku-4", Rate(input: 1, output: 5)),
        ("gpt-5", Rate(input: 1.25, output: 10)),
        ("gpt-4o", Rate(input: 2.5, output: 10)),
        ("gemini-2.5-pro", Rate(input: 1.25, output: 10)),
        ("gemini-2.5-flash", Rate(input: 0.3, output: 2.5)),
        ("grok-4", Rate(input: 3, output: 15)),
    ]

    /// The rate for a model, or nil when this table has never heard of it.
    ///
    /// Nil is the common case and the important one: a custom endpoint or a local model has no
    /// price we could know. Callers show tokens and no cost rather than inventing a figure.
    public static func rate(for model: String) -> Rate? {
        let id = model.lowercased()
        return table.first { id.hasPrefix($0.prefix) }?.rate
    }

    /// Estimated dollars for a turn, or nil when the model's price is unknown.
    ///
    /// Nil for anything running on the person's own machine too — a local model costs no money, and
    /// "$0.00" alongside a real figure invites the reader to compare them as if they were the same
    /// kind of number.
    public static func estimate(
        model: String,
        baseURL: String?,
        inputTokens: Int,
        outputTokens: Int
    ) -> Double? {
        if let baseURL, isLocal(baseURL) { return nil }
        guard let rate = rate(for: model) else { return nil }
        return (Double(inputTokens) * rate.input + Double(outputTokens) * rate.output) / 1_000_000
    }

    static func isLocal(_ baseURL: String) -> Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "host.docker.internal"].contains(host)
    }
}

/// Tokens an agent has used in this session, and what that is worth.
public struct AgentUsage: Sendable, Equatable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var turns = 0

    public init() {}

    public var totalTokens: Int { inputTokens + outputTokens }

    public mutating func add(inputTokens input: Int, outputTokens output: Int) {
        inputTokens += input
        outputTokens += output
        turns += 1
    }

    /// Estimated spend for what this agent has used, or nil when the model has no known price.
    public func estimate(for model: ModelSelection?) -> Double? {
        guard let model else { return nil }
        return ModelPrices.estimate(
            model: model.model,
            baseURL: model.baseURL,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
