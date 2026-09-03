import SwiftUI
import XBotRuntime
import XBotUI

struct SystemCheckStep: View {
    @Bindable var coordinator: OnboardingCoordinator

    var body: some View {
        OnboardingLayout(
            title: String(localized: "Checking your Mac"),
            showsBack: true,
            onBack: {
                coordinator.stopRuntimePolling()
                coordinator.back()
            }
        ) {
            if let result = coordinator.systemResult {
                content(for: result)
            } else {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .task { await coordinator.runSystemCheck() }
        .onDisappear { coordinator.stopRuntimePolling() }
    }

    @ViewBuilder
    private func content(for result: SystemRequirements.Result) -> some View {
        switch result.macOS {
        case .unsupported(let version):
            failure(
                String(localized: "xBot requires macOS 14 or later."),
                detail: String(localized: "This Mac is running macOS \(version).")
            )
        default:
            if !result.diskSufficient {
                VStack(alignment: .leading, spacing: Space.m) {
                    failure(
                        String(localized: "Not enough free disk space."),
                        detail: String(
                            localized: "\(formattedGB(result.freeDiskGigabytes)) free — xBot needs at least 12 GB."
                        )
                    )
                    Button(String(localized: "Open Storage Settings")) {
                        RuntimeLauncher.openStorageSettings()
                    }
                    .buttonStyle(XBotButtonStyle())
                }
            } else if result.showsRAMWarning, !coordinator.ramWarningAccepted {
                ramWarning(result)
            } else {
                runtimeBranchView
            }
        }
    }

    @ViewBuilder
    private var runtimeBranchView: some View {
        switch coordinator.runtimeBranch {
        case .checking:
            ProgressView(String(localized: "Checking container runtime…"))
        case .ready:
            EmptyView()
        case .installedNotRunning:
            VStack(alignment: .leading, spacing: Space.m) {
                Text(String(localized: "Docker Desktop is installed but not running."))
                    .bodyText()
                if coordinator.isPollingRuntime {
                    ProgressView(String(localized: "Waiting for Docker…"))
                }
                Button(String(localized: "Start Docker"), action: coordinator.startDockerDesktop)
                    .buttonStyle(XBotButtonStyle())
            }
        case .absent:
            VStack(alignment: .leading, spacing: Space.m) {
                Text(String(localized: "xBot needs a container runtime"))
                    .sectionTitle()
                Text(String(
                    localized: "Your agents run in isolated containers so they can't touch the rest of your Mac. That needs one free piece of software."
                ))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)
                Text(String(localized: "This takes about 5 minutes and around 4 GB."))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)

                switch coordinator.runtimeInstallState {
                case .idle:
                    EmptyView()
                case .installing(let progress):
                    VStack(alignment: .leading, spacing: Space.s) {
                        ProgressView(progress.label)
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction)
                        }
                    }
                case .failed(let message):
                    Text(message)
                        .bodyText()
                        .foregroundStyle(Palette.stateFailed)
                }

                if coordinator.isPollingRuntime {
                    ProgressView(String(localized: "Waiting for Docker…"))
                }

                Button(String(localized: "Install for me"), action: coordinator.startRuntimeInstall)
                    .buttonStyle(XBotButtonStyle())
                    .disabled(coordinator.runtimeInstallState != .idle)

                Button(String(localized: "I'll install Docker Desktop myself"), action: coordinator.openDockerDownloadPage)
                    .buttonStyle(XBotButtonStyle())
            }
        }
    }

    private func ramWarning(_ result: SystemRequirements.Result) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(String(localized: "This Mac has \(formattedGB(result.physicalMemoryGigabytes)) of memory."))
                .bodyText()
            Text(String(localized: "xBot works best with 16 GB or more. You can run one agent at a time."))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)
            Button(String(localized: "Continue anyway"), action: coordinator.acceptRAMWarning)
                .buttonStyle(XBotButtonStyle())
        }
    }

    private func failure(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .sectionTitle()
            Text(detail)
                .bodyText()
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func formattedGB(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }
}
