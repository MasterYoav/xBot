import SwiftUI
import XBotCore
import XBotEngine

/// Settings → Computer. What agents may do in the browser, in plain language.
public struct ComputerSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var settings = ComputerSettingsState()

    public init() {}

    private var isEnforcing: Bool { settings.policy?.mode == .enforce }

    public var body: some View {
        Form {
            if let problem = settings.problem {
                Section {
                    Text(problem).foregroundStyle(Palette.stateFailed)
                }
            }

            if settings.policy != nil {
                Section {
                    // "Auto-review" was ambiguous in the worst direction for a safety control: it
                    // reads as "approve automatically", so somebody could turn it off believing
                    // they were tightening things, and instead switch enforcement off entirely.
                    Toggle(
                        String(localized: "Check every action before it runs"),
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
                    // Says what *off* means. It used to describe only the on state, so the one
                    // setting that stops the boundary acting explained nothing about doing so.
                    Text(
                        isEnforcing
                            ? String(
                                localized:
                                    "xBot checks each action against your rules before it runs, and asks you first when one matches."
                            )
                            : String(
                                localized:
                                    "Off. Actions are still recorded, but none are stopped — agents can do anything, including the things listed below."
                            )
                    )
                    .foregroundStyle(isEnforcing ? Palette.textSecondary : Palette.stateFailed)
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
                } footer: {
                    // A rule that is switched on and not being applied is worse than no rule: the
                    // person believes an agent will be stopped and it will not be.
                    if !isEnforcing {
                        Text(
                            String(
                                localized:
                                    "These are saved, but not in force while checking is off."
                            )
                        )
                        .foregroundStyle(Palette.stateFailed)
                    }
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
