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
            /*
             * The v1 limitation, said where a person is looking at what agents may do.
             *
             * The single-container shape has no supervisor, so no Docker socket, so every agent
             * shares one Chromium profile and one workspace: agent A can read the cookies agent B
             * used to sign into a bank. docs/10-security.md is blunt about the choice — "shipping
             * this quietly would be the worst decision available; shipping it with a sentence is
             * acceptable for an early version. Not shipping the sentence is not."
             *
             * The wording is the one that document specifies, not a paraphrase, and it is at the
             * top rather than in a footer at the bottom because it is a thing to know before
             * setting rules, not after.
             */
            Section {
                Text(
                    String(
                        localized:
                            "In this version, all your agents share one browser. An agent can see sites another agent has signed into. Give agents separate logins for anything sensitive."
                    )
                )
                .foregroundStyle(Palette.textSecondary)
            } header: {
                Label(String(localized: "One browser, shared"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.stateReconnecting)
            }

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
