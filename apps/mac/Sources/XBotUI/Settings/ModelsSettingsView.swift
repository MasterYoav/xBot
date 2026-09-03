import SwiftUI
import XBotCore

/// Settings → Models. One row per provider: a name, a state, and one action.
///
/// The shape is docs/04-model-providers.md's. What it deliberately does not have is a usage meter:
/// the quota is the person's, with their vendor, and a percentage we cannot verify or enforce is
/// worse than no number.
public struct ModelsSettingsView: View {
    @State private var settings = ModelSettingsState()
    @State private var editing: String?
    @State private var key = ""
    @State private var addingCustom = false
    @State private var customName = ""
    @State private var customURL = ""
    @State private var customModel = ""
    @State private var customKey = ""
    @State private var savingCustom = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                ForEach(settings.rows) { row in
                    providerRow(row)
                }
            } header: {
                Text(String(localized: "Models"))
            } footer: {
                // Said where the key is typed, not buried in a preferences pane nobody opens.
                Text(
                    String(
                        localized:
                            "Keys are stored in your Mac's Keychain and sent only to the provider they belong to."
                    )
                )
            }

            Section {
                ForEach(settings.custom) { provider in
                    customRow(provider)
                }
                if addingCustom {
                    customForm
                } else {
                    Button(String(localized: "Add a custom provider")) {
                        withAnimation(Motion.quick) { addingCustom = true }
                    }
                    .buttonStyle(XBotButtonStyle())
                }
            } header: {
                Text(String(localized: "Your own providers"))
            } footer: {
                Text(
                    addingCustom
                        ? String(
                            localized:
                                "The base URL is the endpoint's root, like https://openrouter.ai/api/v1. Leave the key empty if it needs none."
                        )
                        : String(
                            localized:
                                "Anything that speaks the OpenAI API — a gateway at work, OpenRouter, or a model running on this Mac."
                        )
                )
            }
        }
        .formStyle(.grouped)
        .task {
            settings.load()
            await settings.detectLocalProviders()
        }
    }

    @ViewBuilder
    private func providerRow(_ row: ProviderRow) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name).bodyEmphasis()
                    Text(stateText(row))
                        .captionText()
                        .foregroundStyle(stateColour(row.state))
                }
                Spacer()
                action(row)
            }

            if editing == row.id {
                keyField(row)
            }
        }
        .padding(.vertical, Space.xxs)
    }

    @ViewBuilder
    private func action(_ row: ProviderRow) -> some View {
        switch row.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .notDetected where !row.needsKey:
            // A link, never an instruction. Installing Ollama is not something this app narrates.
            Link(String(localized: "Get Ollama"), destination: URL(string: "https://ollama.com")!)
                .buttonStyle(.link)
        case .detectedLocally:
            EmptyView()
        default:
            Button(row.isConnected ? String(localized: "Disconnect") : String(localized: "Connect")) {
                if row.isConnected {
                    settings.disconnect(providerID: row.id)
                } else {
                    withAnimation(Motion.quick) {
                        editing = editing == row.id ? nil : row.id
                        key = ""
                    }
                }
            }
            .buttonStyle(XBotButtonStyle())
        }
    }

    private func keyField(_ row: ProviderRow) -> some View {
        HStack(spacing: Space.s) {
            // Secure, so a key is never on screen for a screen-share or a screenshot.
            SecureField(String(localized: "Paste your key"), text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit(row) }
            Button(String(localized: "Save")) { submit(row) }
                .buttonStyle(XBotButtonStyle())
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submit(_ row: ProviderRow) {
        let pasted = key
        Task {
            await settings.connect(providerID: row.id, key: pasted)
            if settings.rows.first(where: { $0.id == row.id })?.isConnected == true {
                // Cleared on success only: a rejected key stays in the field so the person can fix
                // a truncated paste rather than going back to the vendor for it again.
                key = ""
                editing = nil
            }
        }
    }

    private func stateText(_ row: ProviderRow) -> String {
        switch row.state {
        case .notConnected: row.subtitle
        case .checking: String(localized: "Checking…")
        case .connected(let count):
            count > 0
                ? String(localized: "Connected · \(count) models")
                : String(localized: "Connected")
        case .failed(let message): message
        case .detectedLocally(let count):
            String(localized: "Running on your Mac · \(count) models")
        case .notDetected: String(localized: "Not detected")
        }
    }

    private func stateColour(_ state: ProviderConnectionState) -> Color {
        switch state {
        case .failed: Palette.stateFailed
        case .connected, .detectedLocally: Palette.stateRunning
        default: Palette.textTertiary
        }
    }

    private func customRow(_ provider: CustomProvider) -> some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(provider.name).bodyEmphasis()
                Text("\(provider.model) · \(provider.baseURL)")
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(String(localized: "Remove")) {
                settings.removeCustomProvider(id: provider.id)
            }
            .buttonStyle(XBotButtonStyle())
        }
        .padding(.vertical, Space.xxs)
    }

    private var customForm: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            // Short labels, and the example in the section footer rather than in a placeholder.
            // A macOS `Form` lays every row out as label-on-the-left and takes that label from the
            // field's own title, so a title long enough to be useful wraps to two lines and a
            // placeholder becomes a second label beside it.
            TextField(String(localized: "Name"), text: $customName)
            TextField(String(localized: "Base URL"), text: $customURL)
            TextField(String(localized: "Model"), text: $customModel)
            // Optional, and the footer says so: a model on this Mac asks for no key, and an empty
            // field here is a valid answer rather than something left undone.
            SecureField(String(localized: "Key"), text: $customKey)

            if let problem = settings.customProblem {
                Text(problem).captionText().foregroundStyle(Palette.stateFailed)
            }

            HStack(spacing: Space.s) {
                Spacer()
                Button(String(localized: "Cancel")) {
                    withAnimation(Motion.quick) { resetCustomForm() }
                }
                .buttonStyle(XBotButtonStyle())
                Button(String(localized: "Add")) { saveCustom() }
                    .buttonStyle(XBotButtonStyle())
                    .disabled(savingCustom)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(.vertical, Space.xxs)
    }

    private func saveCustom() {
        savingCustom = true
        Task {
            let added = await settings.addCustomProvider(
                name: customName,
                baseURL: customURL,
                model: customModel,
                key: customKey
            )
            savingCustom = false
            // Kept on failure so the person can correct one field rather than retype all four.
            if added { withAnimation(Motion.quick) { resetCustomForm() } }
        }
    }

    private func resetCustomForm() {
        addingCustom = false
        customName = ""
        customURL = ""
        customModel = ""
        customKey = ""
    }
}
