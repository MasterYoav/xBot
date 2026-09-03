import SwiftUI
import XBotCore
import XBotUI

struct MeetAgentStep: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onComplete: (OnboardingHandoff) -> Void

    @State private var phase: Phase = .creating
    @State private var handoff = OnboardingHandoff()

    private enum Phase {
        case creating
        case ready
        case failed
    }

    var body: some View {
        OnboardingLayout(title: String(localized: "Meet your agent")) {
            VStack(alignment: .leading, spacing: Space.l) {
                switch phase {
                case .creating:
                    ProgressView(String(localized: "Creating your first agent…"))
                case .ready:
                    introMessage
                    Button(String(localized: "Open xBot"), action: { onComplete(handoff) })
                        .buttonStyle(XBotButtonStyle())
                case .failed:
                    Text(String(localized: "Couldn't create your first agent. You can add one from the sidebar after opening xBot."))
                        .bodyText()
                        .foregroundStyle(Palette.textSecondary)
                    Button(String(localized: "Open xBot anyway"), action: { onComplete(handoff) })
                        .buttonStyle(XBotButtonStyle())
                }
            }
        }
        .task {
            handoff.modelSkipped = coordinator.didSkipModel
            if let id = await coordinator.createFirstAgent() {
                handoff.firstAgentID = id
                phase = .ready
            } else {
                phase = .failed
            }
        }
    }

    private var introMessage: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(String(localized: "Hi. I'm your first agent."))
                .sectionTitle()
            Text(String(
                localized: "I have a browser and files of my own, and I'll ask before doing anything that matters."
            ))
            .bodyText()
            .foregroundStyle(Palette.textSecondary)
            Text(String(localized: "Try me with something like:"))
                .bodyEmphasis()
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("• \(String(localized: "\"Find three well-reviewed ramen places near me\""))")
                Text("• \(String(localized: "\"Open my calendar and summarise this week\""))")
            }
            .bodyText()
            .foregroundStyle(Palette.textSecondary)
        }
    }
}
