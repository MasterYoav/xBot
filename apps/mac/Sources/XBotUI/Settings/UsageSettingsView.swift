import SwiftUI
import XBotCore
import XBotEngine

/// Settings → Usage. Tokens the providers actually reported, and an estimate of what they cost.
///
/// **No percentage meter, deliberately.** The reference product shows "Weekly usage 31%" because it
/// owns the model and therefore owns the quota. We do not — the limit is the person's, with their
/// vendor — and a meter would imply one we neither know nor can enforce. See docs/04.
public struct UsageSettingsView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        Form {
            Section {
                if state.usageByAgent.isEmpty {
                    // Not a zero row per agent. Nothing has been measured yet, and a table of
                    // zeroes reads as "these agents are free" rather than "nothing has run".
                    Text(String(localized: "Nothing yet. Token counts appear here after an agent answers."))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(state.agents) { agent in
                        if let usage = state.usageByAgent[agent.id] {
                            row(agent: agent, usage: usage)
                        }
                    }
                }
            } header: {
                Text(String(localized: "This session"))
            } footer: {
                Text(
                    String(
                        localized:
                            "Counted from what each provider reported. Costs are estimated from list prices — your provider's bill is the real number. Models running on this Mac cost nothing and show no price."
                    )
                )
            }
        }
        .formStyle(.grouped)
    }

    private func row(agent: Agent, usage: AgentUsage) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack {
                Text(agent.name).bodyEmphasis()
                Spacer()
                Text(estimateText(usage: usage, model: agent.model))
                    .bodyText()
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(detail(usage: usage, model: agent.model))
                .captionText()
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, Space.xxs)
    }

    /// The estimate, or an honest dash when this model has no price we could know.
    private func estimateText(usage: AgentUsage, model: ModelSelection?) -> String {
        guard let estimate = usage.estimate(for: model) else { return "—" }
        return "≈ " + (estimate.formatted(.currency(code: "USD").precision(.fractionLength(2...4))))
    }

    private func detail(usage: AgentUsage, model: ModelSelection?) -> String {
        let turns = String(localized: "\(usage.turns) turns")
        let tokens = String(
            localized: "\(usage.inputTokens.formatted()) in · \(usage.outputTokens.formatted()) out"
        )
        guard let model else { return "\(turns) · \(tokens)" }
        return "\(model.model) · \(turns) · \(tokens)"
    }
}
