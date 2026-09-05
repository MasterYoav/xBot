import SwiftUI
import XBotCore
import XBotRuntime

/// Settings → Updates. App and engine versions, and whether a newer build is published.
public struct UpdatesSettingsView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "xBot")) {
                    Text(AppState.appVersion)
                }
                LabeledContent(String(localized: "Channel")) {
                    Text(String(localized: "Stable"))
                }
                Button {
                    state.checkForAppUpdate()
                } label: {
                    Text(String(localized: "Check for app update"))
                }
                .buttonStyle(XBotButtonStyle())
                .disabled(!state.appUpdates.isConfigured || state.isTurnInFlight)
            } header: {
                Text(String(localized: "App"))
            } footer: {
                Text(appUpdateFooter)
            }

            Section {
                if let health = state.engineHealth {
                    LabeledContent(String(localized: "Running version")) {
                        Text(health.engineVersion)
                    }
                }
                if let image = state.pinnedEngineImage {
                    LabeledContent(String(localized: "Image")) {
                        Text(Self.shortDigest(image))
                            .textSelection(.enabled)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                if let status = state.engineUpdateStatus {
                    LabeledContent(String(localized: "Update check")) {
                        Text(status.sentence)
                            .foregroundStyle(statusColour(status))
                    }
                }
                if let outcome = state.lastEngineUpgradeOutcome {
                    LabeledContent(String(localized: "Last install")) {
                        Text(outcome.sentence)
                            .foregroundStyle(outcomeColour(outcome))
                    }
                }
                if state.engineUpdateStatus?.installableImage != nil {
                    Button {
                        Task { await state.installEngineUpdate() }
                    } label: {
                        if state.isInstallingEngineUpdate {
                            Text(String(localized: "Installing…"))
                        } else {
                            Text(String(localized: "Install engine update"))
                        }
                    }
                    .buttonStyle(XBotButtonStyle())
                    .disabled(installDisabled)
                }
                Button {
                    Task { await state.checkForEngineUpdate() }
                } label: {
                    if state.isCheckingEngineUpdate {
                        Text(String(localized: "Checking…"))
                    } else {
                        Text(String(localized: "Check for engine update"))
                    }
                }
                .buttonStyle(XBotButtonStyle())
                .disabled(state.isCheckingEngineUpdate || !state.hasManagedRuntime || state.isInstallingEngineUpdate)
            } header: {
                Text(String(localized: "Engine"))
            } footer: {
                Text(installFooter)
            }
        }
        .formStyle(.grouped)
        .task {
            if state.engineUpdateStatus == nil, state.hasManagedRuntime {
                await state.checkForEngineUpdate()
            }
        }
    }

    private var appUpdateFooter: String {
        if state.isTurnInFlight {
            return String(
                localized:
                    "Wait for the current reply to finish before checking for an app update."
            )
        }
        if state.appUpdates.isConfigured {
            return String(
                localized:
                    "xBot checks for app updates daily. You will be asked before anything installs."
            )
        }
        return String(
            localized:
                "App updates through Sparkle activate in signed release builds with an appcast URL."
        )
    }

    private var installDisabled: Bool {
        state.isInstallingEngineUpdate
            || state.isTurnInFlight
            || !state.hasManagedRuntime
            || state.isCheckingEngineUpdate
    }

    private var installFooter: String {
        if state.isTurnInFlight {
            return String(
                localized:
                    "Wait for the current reply to finish before installing an engine update."
            )
        }
        return String(
            localized:
                "The engine updates separately from the app. Installing pulls the new image, replaces the container, and keeps your conversations on the same volumes."
        )
    }

    private func statusColour(_ status: EngineUpdateStatus) -> Color {
        switch status {
        case .upToDate: Palette.stateRunning
        case .updateAvailable: Palette.stateReconnecting
        case .appTooOld: Palette.stateFailed
        case .unreachable: Palette.textSecondary
        }
    }

    private func outcomeColour(_ outcome: EngineUpgradeOutcome) -> Color {
        switch outcome {
        case .succeeded: Palette.stateRunning
        case .rolledBack: Palette.stateReconnecting
        case .failed: Palette.stateFailed
        }
    }

    private static func shortDigest(_ reference: String) -> String {
        guard let range = reference.range(of: "@sha256:") else { return reference }
        let digest = reference[range.upperBound...]
        return digest.count > 12 ? String(digest.prefix(12)) + "…" : String(digest)
    }
}
