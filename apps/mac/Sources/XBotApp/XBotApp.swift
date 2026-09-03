import SwiftUI
import XBotCore
import XBotEngine
import XBotOnboarding
import XBotRuntime
import XBotUI

@main
struct XBotApp: App {
    @State private var state: AppState
    @State private var onboardingCoordinator: OnboardingCoordinator
    @State private var showOnboarding = Self.initialShowOnboarding

    init() {
        Task { @MainActor in AppIconConfigurator.apply() }
        #if DEBUG
        if ProcessInfo.processInfo.environment["XBOT_USE_RUNTIME"] != "1" {
            _state = State(wrappedValue: AppState(engine: StubEngineClient()))
            _onboardingCoordinator = State(wrappedValue: OnboardingCoordinator())
            return
        }
        #endif
        let runtime = EngineBootstrap.runtimeController()
        let environment = EngineBootstrap.environmentFactory()
        _state = State(wrappedValue: Self.productionState(runtime: runtime, environment: environment))
        _onboardingCoordinator = State(
            wrappedValue: OnboardingCoordinator(runtime: runtime, environmentFactory: environment)
        )
    }

    private static func productionState(
        runtime: RuntimeController,
        environment: @escaping @Sendable (UInt16, String) -> [String: String]
    ) -> AppState {
        let engineToken = (try? EngineTokenStore.token()) ?? ""

        return AppState(
            runtime: runtime,
            environment: environment,
            engineFactory: { endpoint in
                HTTPEngineClient(baseURL: endpoint.baseURL, token: engineToken)
            }
        )
    }

    var body: some Scene {
        Window("", id: "main") {
            AppShellView(
                state: state,
                coordinator: onboardingCoordinator,
                showOnboarding: $showOnboarding
            )
        }
        .defaultSize(showOnboarding ? Metrics.onboardingWindow : Metrics.minimumWindow)
        .windowResizability(showOnboarding ? .contentSize : .automatic)
        .windowToolbarStyle(.unified)

        Window(String(localized: "Plugins"), id: "plugins-admin") {
            PluginsAdminView()
                .environment(state)
        }
        .defaultSize(width: 960, height: 720)

        Settings {
            SettingsRootView()
                .environment(state)
        }
    }

    /// Stub debug builds skip onboarding so the main window is reachable without Docker.
    private static var initialShowOnboarding: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XBOT_USE_RUNTIME"] != "1" {
            return false
        }
        #endif
        return !OnboardingVersion.isComplete
    }
}
