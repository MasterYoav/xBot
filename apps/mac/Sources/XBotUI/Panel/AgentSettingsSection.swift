import SwiftUI
import XBotCore
import XBotEngine

/// Editing in place, saved on blur. No Save button, no dialog.
public struct AgentSettingsSection: View {
    @Environment(AppState.self) private var state

    @State private var name = ""
    @State private var label = ""
    @FocusState private var focusedField: Field?

    private enum Field { case name, label }

    public init() {}

    public var body: some View {
        PanelSectionBody(String(localized: "Agent settings")) {
            if let agent = state.selectedAgent {
                AgentAvatar(agent: agent, size: .large)
                    .frame(maxWidth: .infinity, alignment: .center)

                field(String(localized: "Name"), text: $name, focus: .name)
                field(String(localized: "Label"), text: $label, focus: .label)
                modelRow(agent)
            }
        }
        .onChange(of: state.selectedAgentID, initial: true) { load() }
        .onChange(of: focusedField) { previous, _ in
            // Saved on blur, which means the save is driven by focus leaving a field rather than
            // by every keystroke. A per-keystroke save would put a write on the engine for each
            // letter of a rename.
            guard previous != nil else { return }
            commit()
        }
    }

    private func field(_ title: String, text: Binding<String>, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).captionText().foregroundStyle(Palette.textSecondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .bodyText()
                .focused($focusedField, equals: focus)
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .background(
                    Palette.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                )
        }
    }

    /// The row the model router exists for.
    ///
    /// Provider and capabilities under the name, because "Claude Sonnet 4.5" alone does not tell
    /// somebody whether this agent can look at a screenshot.
    private func modelRow(_ agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(String(localized: "Model")).captionText().foregroundStyle(Palette.textSecondary)

            Menu {
                ForEach(state.models, id: \.self) { model in
                    Button("\(model.provider) · \(model.model)") {
                        state.updateSelectedAgent(AgentPatch(model: model))
                    }
                }
            } label: {
                HStack {
                    Text(agent.model?.model ?? String(localized: "Not set")).bodyText()
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(
                Palette.elevatedSurface,
                in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            )

            if let model = agent.model {
                Text(([model.provider] + model.capabilities).joined(separator: " · "))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func load() {
        name = state.selectedAgent?.name ?? ""
        label = state.selectedAgent?.label ?? ""
    }

    private func commit() {
        guard let agent = state.selectedAgent else { return }
        var patch = AgentPatch()
        if name != agent.name, !name.isEmpty { patch.name = name }
        if label != agent.label { patch.label = label }
        guard patch != AgentPatch() else { return }
        state.updateSelectedAgent(patch)
    }
}
