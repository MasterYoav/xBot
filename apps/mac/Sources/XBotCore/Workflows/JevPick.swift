import Foundation
import XBotBrain

/// Something Jev can be asked, and answer: the real client in the app, a script in tests.
public protocol JevDecider: Sendable {
    func ask(state: String, questions: [String: JevQuestion]) async throws(JevError) -> JevResponse
}

extension JevClient: JevDecider {}

/// An installed CLI and model, as Jev sees it when picking.
public struct BrainOption: Equatable, Sendable {
    public var key: String
    public var choice: BrainChoice
    /// "Codex · gpt-5-mini".
    public var name: String
    /// "Codex · gpt-5-mini — quick edits, cheapest": its strength and relative cost.
    public var description: String
    /// The efforts the model supports; empty when it doesn't say.
    public var efforts: [Effort]
}

/// What Jev picked, and how sure it was.
public struct JevPickResult: Equatable, Sendable {
    public var choice: BrainChoice
    public var name: String
    public var confidence: Double

    /// "Jev chose Codex · gpt-5-mini, low effort (0.82)".
    public var sentence: String {
        let sure = String(format: "%.2f", confidence)
        guard let effort = choice.effort else { return String(localized: "Jev chose \(name) (\(sure))") }
        return String(localized: "Jev chose \(name), \(effort.title.lowercased()) effort (\(sure))")
    }
}

/// "Jev picks": before a step (or a chat's message) runs, one call to Jev with a choice over every
/// installed CLI and model and a score for the effort the task needs. The cheapest capable brain
/// does the work.
public enum JevPick {
    /// Effort's levels as Jev scores them, lowest first.
    public static let efforts: [Effort] = [.low, .medium, .high, .max]

    public static func options(installed: [HarnessKind], models: (HarnessKind) -> [ModelOption]) -> [BrainOption] {
        var out: [BrainOption] = []
        for harness in installed {
            let list = models(harness)
            if list.isEmpty {
                out.append(option(harness, model: nil, modelName: nil, efforts: []))
            } else {
                for model in list { out.append(option(harness, model: model.id, modelName: model.name, efforts: model.efforts)) }
            }
        }
        // Jev takes up to 255 options.
        return Array(out.prefix(255))
    }

    private static func option(_ harness: HarnessKind, model: String?, modelName: String?, efforts: [Effort]) -> BrainOption {
        let name = modelName.map { "\(harness.displayName) · \($0)" } ?? harness.displayName
        let key = harness.rawValue + "__" + (model.map(JevStep.slug) ?? "default")
        return BrainOption(key: key, choice: BrainChoice(harness: harness, model: model), name: name,
                           description: "\(name) — \(strength(harness, model: model))", efforts: efforts)
    }

    /// The model's strength and relative cost, in a few plain words. Jev reads these to weigh
    /// capability against price; they're not shown to the person except through its choice.
    static func strength(_ harness: HarnessKind, model: String?) -> String {
        let id = model?.lowercased() ?? ""
        switch harness {
        case .claude:
            if id.contains("opus") { return "strongest, most expensive" }
            if id.contains("sonnet") { return "strong all-rounder, mid-priced" }
            if id.contains("haiku") { return "fast and light, cheapest Claude" }
            return "Claude Code's default model, mid-priced"
        case .codex:
            if id.contains("mini") || id.contains("nano") { return "quick edits, cheapest" }
            if id.contains("max") || id.contains("pro") || id.contains("ultra") { return "deep reasoning, expensive" }
            if id.isEmpty { return "Codex's default model, strong coder, mid-priced" }
            return "strong coder, mid-priced"
        case .antigravity:
            if id.contains("flash") || id.contains("lite") { return "fast, cheap" }
            if id.contains("pro") || id.contains("opus") { return "strong, expensive" }
            return "Google's models, mid-priced"
        case .copilot:
            return "the models of a Copilot plan, mid-priced"
        }
    }

    public static func questions(for options: [BrainOption]) -> [String: JevQuestion] {
        [
            "brain": .choice(
                "Pick the cheapest agent and model that can do this task well. Prefer a cheaper one unless the task clearly needs a stronger one.",
                options: options.map { JevQuestion.Option(key: $0.key, description: $0.description) }),
            "effort": .score("How much reasoning effort does this task need?", levels: efforts.map(\.title)),
        ]
    }

    /// Nil when Jev's choice isn't one of the options (fail closed: the caller falls back).
    public static func decide(_ response: JevResponse, options: [BrainOption]) -> JevPickResult? {
        guard case .choice(let key, _, let confidence) = response.answers["brain"],
              let option = options.first(where: { $0.key == key }) else { return nil }
        var choice = option.choice
        if case .score(let score, _, _, _) = response.answers["effort"] {
            let wanted = efforts[min(max(Int(score.rounded()), 0), efforts.count - 1)]
            choice.effort = supported(wanted, by: option.efforts)
        }
        return JevPickResult(choice: choice, name: option.name, confidence: confidence)
    }

    /// The wanted effort, or the highest the model supports below it.
    static func supported(_ wanted: Effort, by efforts: [Effort]) -> Effort {
        guard !efforts.isEmpty, !efforts.contains(wanted) else { return wanted }
        let order = Effort.allCases
        let rank = order.firstIndex(of: wanted) ?? 0
        return efforts.filter { (order.firstIndex(of: $0) ?? 0) <= rank }.max { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            ?? efforts.min { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            ?? wanted
    }
}
