import SwiftUI
import XBotCore
import XBotEngine

/// Which agents this one may hand work to — directional, not reciprocal.
public struct AgentHandoffSection: View {
    @Environment(AppState.self) private var state

    @State private var isExpanded = false

    public init() {}

    public var body: some View {
        CollapsibleSettingsSection(
            title: String(localized: "Handoff grants"),
            isExpanded: $isExpanded
        ) {
            content
        }
        .task(id: state.selectedAgentID) {
            await state.refreshHandoffGrants()
        }
    }

    @ViewBuilder
    private var content: some View {
        Text(
            String(
                localized:
                    "Who this agent may ask, not who may ask it. What the other agent says comes back into this conversation."
            )
        )
        .captionText()
        .foregroundStyle(Palette.textSecondary)
        .padding(.bottom, Space.xs)

        if state.handoffGrantsLoading, state.handoffGrants == nil {
            ProgressView().controlSize(.small)
        } else if let handoff = state.handoffGrants {
            if !handoff.enabled {
                notice(String(localized: "Handoff is switched off for this deployment. Grants are kept but none take effect."))
            }
            if !handoff.grantable {
                notice(
                    String(
                        localized:
                            "This agent runs outside the deployment loop and cannot hand work on. It can still be asked by agents that can."
                    )
                )
            }
            candidateList(handoff)
        } else {
            Text(String(localized: "Could not load handoff grants."))
                .captionText()
                .foregroundStyle(Palette.textSecondary)
        }
    }

    @ViewBuilder
    private func candidateList(_ handoff: HandoffGrants) -> some View {
        let selected = state.selectedAgentID
        let others = state.agents.filter { $0.id != selected }
        let candidates = handoff.grantable
            ? others
            : others.filter { handoff.reachable.contains($0.id) }

        if handoff.grantable, others.isEmpty {
            Text(String(localized: "No other agents yet. When you add more, this is where you choose who this one may ask."))
                .captionText()
                .foregroundStyle(Palette.textTertiary)
        } else if candidates.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(candidates) { agent in
                    Toggle(isOn: handoffBinding(agent.id, handoff: handoff)) {
                        HStack(spacing: Space.s) {
                            AgentAvatar(agent: agent, size: .small)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(agent.name).bodyText()
                                if !agent.label.isEmpty {
                                    Text(agent.label)
                                        .captionText()
                                        .foregroundStyle(Palette.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!handoff.canGrant)
                }
            }
        }

        if !handoff.canGrant {
            Text(String(localized: "An administrator decides which agents may be asked."))
                .captionText()
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, Space.xxs)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .captionText()
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, Space.xxs)
            .padding(.horizontal, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.elevatedSurface,
                in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            )
            .padding(.bottom, Space.xs)
    }

    private func handoffBinding(_ target: Agent.ID, handoff: HandoffGrants) -> Binding<Bool> {
        Binding(
            get: { handoff.reachable.contains(target) },
            set: { enabled in
                Task { await state.setHandoffGrant(to: target, enabled: enabled) }
            }
        )
    }
}
