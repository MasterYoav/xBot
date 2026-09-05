import SwiftUI
import XBotCore
import XBotEngine

/// Settings → Computer. What agents may do in the browser, in plain language.
public struct ComputerSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var settings = ComputerSettingsState()

    public init() {}

    public var body: some View {
        Form {
            if let problem = settings.problem {
                Section {
                    Text(problem).foregroundStyle(Palette.stateFailed)
                }
            }

            if settings.policy != nil {
                Section {
                    Toggle(
                        String(localized: "Auto-review"),
                        isOn: Binding(
                            get: { settings.policy?.mode == .enforce },
                            set: { enabled in
                                Task {
                                    await settings.setAutoReview(enabled) {
                                        try await state.saveActionPolicy($0)
                                    }
                                }
                            }
                        )
                    )
                    .disabled(settings.isSaving)
                } footer: {
                    Text(
                        String(
                            localized:
                                "xBot checks each action before it runs and asks you first when needed. Add rules to customise what agents can do automatically."
                        )
                    )
                }

                Section {
                    ForEach(ComputerPolicyPreset.allCases) { preset in
                        Toggle(
                            preset.label,
                            isOn: Binding(
                                get: { settings.isPresetEnabled(preset) },
                                set: { enabled in
                                    Task {
                                        await settings.setPreset(preset, enabled: enabled) {
                                            try await state.saveActionPolicy($0)
                                        }
                                    }
                                }
                            )
                        )
                        .disabled(settings.isSaving)
                    }
                } header: {
                    Text(String(localized: "Always ask before…"))
                }

                Section {
                    Button(String(localized: "Edit rules directly…")) {
                        state.preparePluginsAdmin(path: "admin/boundaries")
                        openWindow(id: "plugins-admin")
                    }
                    .buttonStyle(XBotButtonStyle())
                } footer: {
                    Text(
                        String(
                            localized:
                                "Opens the full boundary editor with dry-run against your audit trail."
                        )
                    )
                }
            } else if settings.isLoading {
                Section {
                    Text(String(localized: "Loading…"))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await settings.load { try await state.fetchActionPolicy() }
        }
    }
}
