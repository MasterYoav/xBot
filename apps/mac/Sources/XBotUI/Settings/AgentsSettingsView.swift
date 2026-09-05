import SwiftUI
import XBotCore
import XBotEngine

/// Settings → Agents. Defaults for agents created from the rail or command palette.
public struct AgentsSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var defaults = AgentDefaultsState()

    public init() {}

    public var body: some View {
        Form {
            Section {
                Picker(String(localized: "Default model"), selection: $defaults.defaultModelID) {
                    Text(String(localized: "None")).tag(String?.none)
                    ForEach(state.models, id: \.wireIdentity) { model in
                        Text("\(model.model) · \(model.provider)").tag(Optional(model.wireIdentity))
                    }
                }
                .onChange(of: defaults.defaultModelID) { _, _ in
                    defaults.save(models: state.models)
                }
            } footer: {
                Text(
                    String(
                        localized:
                            "New agents start with this model until you change it in their settings."
                    )
                )
            }

            Section {
                TextField(
                    String(localized: "Default description"),
                    text: $defaults.defaultDescription,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .onChange(of: defaults.defaultDescription) { _, _ in
                    defaults.save(models: state.models)
                }
            } header: {
                Text(String(localized: "Standing instruction"))
            } footer: {
                Text(
                    String(
                        localized:
                            "Applied as the agent's role when you create one. You can change it per agent later."
                    )
                )
            }

            Section {
                Text(
                    String(
                        localized:
                            "A shared instruction for every agent requires an engine update and is not available yet."
                    )
                )
                .foregroundStyle(Palette.textSecondary)
            } header: {
                Text(String(localized: "Shared preamble"))
            }
        }
        .formStyle(.grouped)
        .onAppear { defaults.load() }
    }
}
