import SwiftUI
import XBotRuntime
import XBotUI

struct EngineSetupStep: View {
    @Bindable var coordinator: OnboardingCoordinator
    @State private var runtimeState: RuntimeState = .stopped
    @State private var didStart = false

    var body: some View {
        OnboardingLayout(
            title: String(localized: "Setting up xBot"),
            showsBack: true,
            onBack: coordinator.cancelEngineSetup
        ) {
            VStack(alignment: .leading, spacing: Space.l) {
                phaseRow(
                    title: String(localized: "Downloading the engine"),
                    active: isPulling,
                    complete: isPastPulling,
                    detail: pullDetail
                )
                phaseRow(
                    title: String(localized: "Preparing storage"),
                    active: isStarting(.volumes),
                    complete: isPastVolumes
                )
                phaseRow(
                    title: String(localized: "Starting up"),
                    active: isStartingAfterVolumes,
                    complete: isRunning
                )

                if !isRunning, !isFailed {
                    Text(String(localized: "This is a one-time setup. Later updates are much smaller."))
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                }

                if case .failed(let error) = runtimeState {
                    failureView(error)
                } else if !isRunning {
                    Button(String(localized: "Cancel"), action: coordinator.cancelEngineSetup)
                        .buttonStyle(XBotButtonStyle())
                }
            }
        }
        .task { await observeRuntime() }
        .onAppear {
            Task {
                if case .running = await coordinator.runtime.state {
                    coordinator.advance()
                    return
                }
                guard !didStart else { return }
                didStart = true
                coordinator.startEngine()
            }
        }
    }

    private var isRunning: Bool {
        if case .running = runtimeState { return true }
        if case .degraded = runtimeState { return true }
        return false
    }

    private var isPulling: Bool {
        if case .pulling = runtimeState { return true }
        return false
    }

    private var isPastPulling: Bool { isPastVolumes || isStartingAfterVolumes || isRunning }

    private var isPastVolumes: Bool {
        switch runtimeState {
        case .starting(let stage):
            stage != .volumes
        case .running, .degraded:
            true
        default:
            false
        }
    }

    private func isStarting(_ stage: RuntimeState.Stage) -> Bool {
        if case .starting(let current) = runtimeState { return current == stage }
        return false
    }

    private var isStartingAfterVolumes: Bool {
        guard case .starting(let stage) = runtimeState else { return false }
        return stage != .volumes
    }

    private var isFailed: Bool {
        if case .failed = runtimeState { return true }
        return false
    }

    private var pullDetail: String? {
        guard case .pulling(let progress) = runtimeState else { return nil }
        if let fraction = progress.fraction {
            let percent = Int(fraction * 100)
            return String(localized: "\(percent)% complete")
        }
        if progress.layersTotal > 0 {
            return String(
                localized: "\(progress.layersComplete) of \(progress.layersTotal) layers"
            )
        }
        return nil
    }

    @ViewBuilder
    private func failureView(_ error: RuntimeError) -> some View {
        Text(error.sentence)
            .bodyText()
            .foregroundStyle(Palette.stateFailed)

        switch error {
        case .healthTimedOut:
            Text(String(
                localized: "The first start can take a couple of minutes while the database updates."
            ))
            .captionText()
            .foregroundStyle(Palette.textSecondary)
        case .daemonUnavailable:
            Text(String(localized: "Docker stopped unexpectedly."))
                .captionText()
                .foregroundStyle(Palette.textSecondary)
        case .noFreePort:
            EmptyView()
        default:
            Text(String(localized: "Something went wrong setting up the engine."))
                .captionText()
                .foregroundStyle(Palette.textSecondary)
        }

        HStack(spacing: Space.m) {
            Button(String(localized: "Try again")) {
                didStart = false
                coordinator.startEngine()
            }
            .buttonStyle(XBotButtonStyle())

            if case .daemonUnavailable = error {
                Button(String(localized: "Restart Docker"), action: coordinator.startDockerDesktop)
                    .buttonStyle(XBotButtonStyle())
            }

            if case .noFreePort = error {
                Button(String(localized: "Open Storage Settings"), action: coordinator.openStorageSettings)
                    .buttonStyle(XBotButtonStyle())
            }

            Button(String(localized: "Copy diagnostics")) {
                Task { await coordinator.copyDiagnostics() }
            }
            .buttonStyle(XBotButtonStyle())
        }
    }

    private func phaseRow(title: String, active: Bool, complete: Bool, detail: String? = nil) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: complete ? "checkmark.circle.fill" : (active ? "circle.inset.filled" : "circle"))
                .foregroundStyle(complete ? Palette.stateRunning : (active ? Palette.textPrimary : Palette.textTertiary))
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .bodyText()
                    .foregroundStyle(active || complete ? Palette.textPrimary : Palette.textSecondary)
                if active, let detail {
                    Text(detail)
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private func observeRuntime() async {
        for await event in await coordinator.runtime.events {
            guard case .stateChanged(let state) = event else { continue }
            runtimeState = state
            if case .running = state {
                coordinator.advance()
            }
        }
    }
}
