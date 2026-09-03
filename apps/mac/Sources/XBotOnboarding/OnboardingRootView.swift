import SwiftUI
import XBotCore
import XBotUI

/// First-run flow. Own coordinator — not `AppState` — until handoff at Step 5.
public struct OnboardingRootView: View {
    @Bindable var coordinator: OnboardingCoordinator
    private let onComplete: (OnboardingHandoff) -> Void

    public init(
        coordinator: OnboardingCoordinator,
        onComplete: @escaping (OnboardingHandoff) -> Void
    ) {
        self.coordinator = coordinator
        self.onComplete = onComplete
    }

    public init(onComplete: @escaping (OnboardingHandoff) -> Void) {
        self.coordinator = OnboardingCoordinator()
        self.onComplete = onComplete
    }

    public var body: some View {
        Group {
            switch coordinator.step {
            case .welcome:
                WelcomeStep(onContinue: coordinator.advance)
            case .systemCheck:
                SystemCheckStep(coordinator: coordinator)
            case .engineSetup:
                EngineSetupStep(coordinator: coordinator)
            case .connectModel:
                ConnectModelStep(coordinator: coordinator)
            case .meetAgent:
                MeetAgentStep(coordinator: coordinator, onComplete: onComplete)
            }
        }
        .motion(Motion.standard, value: coordinator.step)
    }
}
