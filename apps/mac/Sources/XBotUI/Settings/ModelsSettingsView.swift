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
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Models"))
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
}
