import SwiftUI
import XBotCore
import XBotEngine
import XBotOnboarding
import XBotRuntime
import XBotUI

@main
struct XBotApp: App {
    private let appUpdates = SparkleAppUpdateController()
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
        _state = State(
            wrappedValue: Self.productionState(
                runtime: runtime,
                environment: environment,
                appUpdates: appUpdates
            )
        )
        _onboardingCoordinator = State(
            wrappedValue: OnboardingCoordinator(runtime: runtime, environmentFactory: environment)
        )
    }

    private static func productionState(
        runtime: RuntimeController,
        environment: @escaping @Sendable (UInt16, String) -> [String: String],
        appUpdates: SparkleAppUpdateController
    ) -> AppState {
        return AppState(
            runtime: runtime,
            environment: environment,
            engineFactory: { endpoint in
                /*
                 * Read when the engine is actually reachable, not while the app is starting.
                 *
                 * This used to run in `init`, before any scene existed. The first Keychain read
                 * after a build's signing identity changes puts up a system password prompt, and
                 * because it happened during `init` the window was not created until somebody
                 * answered it — the app looked like it had failed to launch. A signed release
                 * prompts once rather than every build, but launch is the wrong place for it
                 * either way: nothing on screen can explain a prompt that is blocking the screen.
                 *
                 * Here it happens when the runtime reports `.running`, by which point there is a
                 * window to show the prompt over.
                 */
                let token = (try? EngineTokenStore.token()) ?? ""
                return HTTPEngineClient(baseURL: endpoint.baseURL, token: token)
            },
            appUpdates: appUpdates
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

        // No `Settings` scene. Settings live in the main window — see `AppState.isShowingSettings`.
        // A separate floating panel put them somewhere the person had to go and find, and it hid
        // the rail, so which agent was selected stopped being visible while its model was changed.
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
