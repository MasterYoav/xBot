import Foundation
import Observation
import XBotCore
import XBotEngine
import XBotRuntime

@Observable
@MainActor
public final class OnboardingCoordinator {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome
        case systemCheck
        case engineSetup
        case connectModel
        case meetAgent
    }

    public enum RuntimeBranch: Sendable, Equatable {
        case checking
        case ready
        case installedNotRunning
        case absent
    }

    public enum ValidationState: Sendable, Equatable {
        case idle
        case validating
        case succeeded(modelCount: Int)
        case failed(message: String)
    }

    public enum RuntimeInstallState: Sendable, Equatable {
        case idle
        case installing(RuntimeInstallProgress)
        case failed(message: String)
    }

    public private(set) var step: Step = .welcome
    public private(set) var systemResult: SystemRequirements.Result?
    public private(set) var runtimeBranch: RuntimeBranch = .checking
    public private(set) var ramWarningAccepted = false
    public private(set) var isPollingRuntime = false

    public var selectedProviderID: String = ModelProviderCatalog.all[0].id
    public var apiKey = ""
    public private(set) var validation: ValidationState = .idle
    public private(set) var ollamaModelCount: Int?
    public private(set) var didSkipModel = false
    public private(set) var runtimeInstallState: RuntimeInstallState = .idle

    public let runtime: RuntimeController
    public let environmentFactory: @Sendable (UInt16, String) -> [String: String]
    private let validator: ModelProviderValidator
    private var pollingTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?

    public init(
        runtime: RuntimeController = EngineBootstrap.runtimeController(),
        environmentFactory: @escaping @Sendable (UInt16, String) -> [String: String] = EngineBootstrap.environmentFactory(),
        validator: ModelProviderValidator = ModelProviderValidator()
    ) {
        self.runtime = runtime
        self.environmentFactory = environmentFactory
        self.validator = validator
    }

    public var canGoBack: Bool {
        switch step {
        case .welcome: false
        case .systemCheck: true
        case .engineSetup: true
        case .connectModel: true
        case .meetAgent: false
        }
    }

    public var canConnect: Bool {
        guard validation != .validating else { return false }
        if selectedProviderID == "ollama" {
            return ollamaModelCount != nil
        }
        return !ProviderKeyStore.normalize(apiKey).isEmpty
    }

    public func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .systemCheck {
            Task { await runSystemCheck() }
        }
        if next == .connectModel {
            Task { await refreshOllamaState() }
        }
    }

    public func back() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    public func acceptRAMWarning() {
        ramWarningAccepted = true
        maybeAutoAdvanceFromSystemCheck()
    }

    public func runSystemCheck() async {
        runtimeBranch = .checking
        systemResult = SystemRequirements.check()

        let probe = await runtime.detect()
        switch probe {
        case .ready:
            RuntimeChoiceStore.markDetected()
            runtimeBranch = .ready
        case .installedNotRunning:
            runtimeBranch = .installedNotRunning
        case .absent:
            runtimeBranch = .absent
        }

        maybeAutoAdvanceFromSystemCheck()
    }

    public func startRuntimePolling() {
        guard pollingTask == nil else { return }
        isPollingRuntime = true
        pollingTask = Task {
            defer {
                isPollingRuntime = false
                pollingTask = nil
            }
            while !Task.isCancelled {
                await runSystemCheck()
                if runtimeBranch == .ready { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    public func stopRuntimePolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPollingRuntime = false
    }

    public func startDockerDesktop() {
        RuntimeLauncher.openDockerDesktop()
        startRuntimePolling()
    }

    public func openDockerDownloadPage() {
        RuntimeChoiceStore.markDockerManual()
        RuntimeLauncher.openDockerDownloadPage()
        startRuntimePolling()
    }

    public func startRuntimeInstall() {
        guard installTask == nil else { return }
        RuntimeChoiceStore.markColimaInstalled()
        runtimeInstallState = .installing(
            RuntimeInstallProgress(phase: .downloading, label: String(localized: "Preparing download"))
        )
        installTask = Task {
            defer { installTask = nil }
            let installer = ColimaInstaller()
            do {
                try await installer.install { [weak self] progress in
                    Task { @MainActor in
                        self?.runtimeInstallState = .installing(progress)
                    }
                }
                runtimeInstallState = .idle
                startRuntimePolling()
            } catch {
                runtimeInstallState = .failed(
                    message: String(localized: "Couldn't install the container runtime.")
                )
            }
        }
    }

    public func copyDiagnostics() async {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let diagnostics = await runtime.diagnostics(appVersion: version)
        DiagnosticsClipboard.copy(diagnostics)
    }

    public func openStorageSettings() {
        RuntimeLauncher.openStorageSettings()
    }

    private func maybeAutoAdvanceFromSystemCheck() {
        guard step == .systemCheck, let systemResult else { return }
        guard case .supported = systemResult.macOS else { return }
        guard systemResult.diskSufficient else { return }
        if systemResult.showsRAMWarning, !ramWarningAccepted { return }
        guard runtimeBranch == .ready else { return }

        step = .engineSetup
    }

    public func startEngine() {
        Task { await runtime.start(environment: environmentFactory) }
    }

    public func cancelEngineSetup() {
        Task {
            switch await runtime.state {
            case .pulling, .starting, .failed:
                await runtime.stop()
            default:
                break
            }
            step = .systemCheck
            await runSystemCheck()
        }
    }

    public func resetValidation() {
        validation = .idle
    }

    public func selectProvider(_ id: String) {
        selectedProviderID = id
        validation = .idle
        if id == "ollama" {
            Task { await refreshOllamaState() }
        }
    }

    public func refreshOllamaState() async {
        if let result = await validator.detectOllama() {
            if case .valid(let count) = result {
                ollamaModelCount = count
            }
        } else {
            ollamaModelCount = nil
        }
    }

    public func validateAndConnect() async -> Bool {
        validation = .validating
        let result: ProviderValidationResult
        if selectedProviderID == "ollama" {
            result = await validator.validate(providerID: "ollama", key: "")
        } else {
            result = await validator.validate(providerID: selectedProviderID, key: apiKey)
        }

        switch result {
        case .valid(let count):
            do {
                if selectedProviderID != "ollama" {
                    try ProviderKeyStore.save(apiKey, for: selectedProviderID)
                }
                ProviderConnectionStore.shared.markConnected(selectedProviderID)
                validation = .succeeded(modelCount: count)
                didSkipModel = false
                advance()
                return true
            } catch {
                validation = .failed(message: String(localized: "Couldn't save the key"))
                return false
            }
        case .invalid(let message):
            validation = .failed(message: message)
            return false
        }
    }

    public func skipModelConnection() {
        didSkipModel = true
        ProviderConnectionStore.shared.markSkipped()
        advance()
    }

    public func createFirstAgent() async -> Agent.ID? {
        guard case .running(let endpoint) = await runtime.state else { return nil }
        let token = try? EngineTokenStore.token()
        let client = HTTPEngineClient(baseURL: endpoint.baseURL, token: token)
        let name = String(localized: "Assistant")
        guard var agent = try? await client.createAgent(AgentDraft(name: name, label: name)) else {
            return nil
        }

        if !didSkipModel,
           let providerID = ProviderConnectionStore.shared.connectedProviderIDs.first
        {
            let gateway = await runtime.hostGateway
            if let model = ModelProviderCatalog.selections(
                forConnectedProviders: [providerID],
                hostGateway: gateway
            ).first {
                agent = (try? await client.updateAgent(agent.id, AgentPatch(model: model))) ?? agent
            }
        }

        _ = try? await client.createChannel(agentIds: [agent.id])
        return agent.id
    }

    public func finish() async -> OnboardingHandoff {
        OnboardingHandoff(firstAgentID: await createFirstAgent(), modelSkipped: didSkipModel)
    }
}
