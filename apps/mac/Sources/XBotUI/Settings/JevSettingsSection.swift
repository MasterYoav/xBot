import SwiftUI
import XBotCore

/// Settings › AI › TypeSafe Jev: the key (into the Keychain; shown only as saved, with its length),
/// Check, Remove, the model, and the Jev Workflows toggle.
struct JevSettingsSection: View {
    let jev: JevSettings
    @State private var typed = ""
    @State private var saveFailed = false
    @State private var model = ""

    var body: some View {
        Section {
            if let length = jev.keyLength {
                LabeledContent(String(localized: "API key")) {
                    HStack(spacing: Space.s) {
                        Text(String(localized: "Saved · \(length) characters"))
                            .foregroundStyle(Palette.textSecondary)
                        Button(String(localized: "Check")) { Task { await jev.check() } }
                            .disabled(jev.checkResult == .checking)
                        Button(String(localized: "Remove"), role: .destructive) { jev.removeKey() }
                    }
                }
                if let result = jev.checkResult {
                    Text(result.sentence)
                        .captionText()
                        .foregroundStyle(color(for: result))
                        .textSelection(.enabled)
                }
            } else {
                LabeledContent(String(localized: "API key")) {
                    HStack(spacing: Space.s) {
                        // Prompt inside the field, label hidden: in a Form the label otherwise sits
                        // beside the field and wraps.
                        SecureField(String(localized: "TypeSafe API key"), text: $typed,
                                    prompt: Text(String(localized: "Paste your key")))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(save)
                        Button(String(localized: "Save"), action: save)
                            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if saveFailed {
                    Text(String(localized: "The key couldn't be saved to the Keychain."))
                        .captionText().foregroundStyle(Palette.failure)
                }
            }
            TextField(String(localized: "Model"), text: $model, prompt: Text(verbatim: JevClient.defaultModel))
                .onChange(of: model) { jev.model = model }
            Toggle(isOn: Binding(get: { () -> Bool in jev.workflowsEnabled },
                                  set: { (on: Bool) in jev.workflowsEnabled = on })) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(String(localized: "Jev Workflows"))
                    Text(String(localized: "Workflows that mix your agents with Jev's quick decisions, and “Let Jev choose” in chats."))
                        .captionText().foregroundStyle(Palette.textTertiary)
                }
            }
        } header: {
            Text(verbatim: "TypeSafe Jev")
        } footer: {
            HStack(spacing: Space.xs) {
                Text(String(localized: "The key is kept in your Keychain."))
                Link(String(localized: "Get a key at console.typesafe.ai"),
                     destination: URL(string: "https://console.typesafe.ai")!)
            }
            .captionText()
            .foregroundStyle(Palette.textTertiary)
        }
        .onAppear { model = jev.model == JevClient.defaultModel ? "" : jev.model }
    }

    private func save() {
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saveFailed = !jev.saveKey(typed)
        // The field is cleared either way: the key isn't kept on screen or in memory longer than needed.
        typed = ""
        if !saveFailed { Task { await jev.check() } }
    }

    private func color(for result: JevSettings.CheckResult) -> Color {
        switch result {
        case .checking: Palette.textTertiary
        case .answered: Palette.success
        case .failed: Palette.failure
        }
    }
}
