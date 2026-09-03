import SwiftUI
import XBotCore
import XBotEngine
import XBotOnboarding
import XBotRuntime
import XBotUI

/// Root shell: onboarding crossfades into the main window with rail and panel expanding in.
struct AppShellView: View {
    @Bindable var state: AppState
    @Bindable var coordinator: OnboardingCoordinator
    @Binding var showOnboarding: Bool

    @State private var revealChrome = false

    var body: some View {
        ZStack {
            MainWindow()
                .environment(state)
                .opacity(showOnboarding ? 0 : 1)
                .scaleEffect(showOnboarding ? 0.98 : 1)

            if showOnboarding {
                OnboardingRootView(coordinator: coordinator, onComplete: completeOnboarding)
            }
        }
        .background {
            WindowSizeConfigurator(
                contentSize: showOnboarding ? Metrics.onboardingWindow : Metrics.minimumWindow,
                resizable: !showOnboarding
            )
        }
        .motion(Motion.panel, value: showOnboarding)
        .motion(Motion.panel, value: revealChrome)
    }

    private func completeOnboarding(_ handoff: OnboardingHandoff) {
        state.isRailVisible = false
        state.isPanelVisible = false
        OnboardingVersion.markComplete()

        withAnimation(Motion.panel) {
            showOnboarding = false
            revealChrome = true
        }

        Task {
            await state.completeOnboarding(handoff)
            withAnimation(Motion.panel) {
                state.isRailVisible = true
                state.isPanelVisible = true
            }
        }
    }
}
