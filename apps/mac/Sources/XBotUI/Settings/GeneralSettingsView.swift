import SwiftUI
import XBotCore
import XBotEngine
import XBotRuntime

/// Settings → General: what the engine is doing, and the three things you can do about it.
///
/// The one screen that answers "is it working?" without a terminal. `docs/09-ui-spec.md`'s rule
/// applies here more than anywhere: the app degrades honestly. A stopped engine says it is stopped
/// and offers Start; a failed one says why in a sentence and offers Retry. Neither shows an empty
/// state that implies everything is fine.
public struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var copied = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Status")) {
                    Text(statusText)
                        .foregroundStyle(statusColour)
                }
                if let health = state.engineHealth {
                    LabeledContent(String(localized: "Engine version")) {
                        Text(health.engineVersion)
                    }
                    // The upstream revision underneath. For the developer audience and for us:
                    // a bug report that names it saves an hour — docs/11-packaging-and-updates.md.
                    LabeledContent(String(localized: "Database")) {
                        Text(health.schemaVersion)
                    }
                }
                if let address = state.engineBaseURL?.absoluteString {
                    LabeledContent(String(localized: "Address")) {
                        // Loopback only, always. Shown because somebody debugging will ask, not
                        // because anything here needs configuring — the app negotiates the port.
                        Text(address).textSelection(.enabled)
                    }
                }
            } header: {
                Text(String(localized: "Engine"))
            } footer: {
                Text(
                    String(
                        localized:
                            "Your agents run here, on this Mac. It listens only to this computer."
                    )
                )
            }

            Section {
                HStack(spacing: Space.s) {
                    if isRunning {
                        Button(String(localized: "Restart")) { state.restartEngine() }
                            .buttonStyle(XBotButtonStyle())
                        Button(String(localized: "Stop")) { state.stopEngine() }
                            .buttonStyle(XBotButtonStyle())
                    } else {
                        Button(String(localized: "Start")) { state.startEngine() }
                            .buttonStyle(XBotButtonStyle())
                    }
                    Spacer()
                    Button(copied ? String(localized: "Copied") : String(localized: "Copy diagnostics")) {
                        Task {
                            await state.copyDiagnostics()
                            copied = true
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                    .buttonStyle(XBotButtonStyle())
                }
            } footer: {
                Text(
                    String(
                        localized:
                            "Diagnostics describe this Mac and the engine's recent activity. They never include your keys or anything your agents said."
                    )
                )
            }
        }
        .formStyle(.grouped)
    }

    private var isRunning: Bool {
        if case .running = state.runtimeState { return true }
        if case .degraded = state.runtimeState { return true }
        return false
    }

    /// One sentence per runtime state. Never "unknown" where a real answer exists.
    private var statusText: String {
        switch state.runtimeState {
        case .running: String(localized: "Running")
        case .degraded(let reason): reason.sentence
        case .stopped: String(localized: "Stopped")
        case .starting(let stage): stage.sentence
        case .pulling: String(localized: "Downloading the engine")
        case .failed(let error): error.sentence
        case .notDetected:
            String(localized: "No container runtime — xBot needs one to run your agents")
        case .none:
            // No runtime at all: a stub build, where there is nothing to report and saying
            // "stopped" would be a guess about something that does not exist.
            String(localized: "Not managed by this app")
        }
    }

    private var statusColour: Color {
        switch state.runtimeState {
        case .running: Palette.stateRunning
        case .degraded, .pulling, .starting: Palette.stateReconnecting
        case .failed, .notDetected: Palette.stateFailed
        default: Palette.textSecondary
        }
    }
}
