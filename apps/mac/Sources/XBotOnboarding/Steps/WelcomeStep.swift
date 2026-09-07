import SwiftUI
import XBotUI

struct WelcomeStep: View {
    let onContinue: () -> Void
    @State private var revealed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /*
     * What v1 actually does, rather than what the pitch would prefer.
     *
     * The third bullet used to read "Everything stays here. No account, no cloud." ADR-0007 is
     * explicit that both halves of that are false for v1: onboarding needs a CopilotKit key, and
     * conversation history rests on their infrastructure. The ADR says the vision document "has
     * been changed rather than quietly reinterpreted" — the first screen of the product is the one
     * place that mattered most and it had not been.
     *
     * Agents, files and browsers really do stay on the Mac, so that claim keeps its place. The
     * transcript is the exception and step four says so in full before a key is typed.
     */
    /// The promises this screen makes. Exposed so a test can hold them to ADR-0007.
    static let bulletsForTesting = [
        String(localized: "Bring any model — or run one locally, with nothing leaving your Mac"),
        String(localized: "Watch what your agents do, and take over whenever you want"),
        String(localized: "Your agents, their files, and their browsers stay on this Mac"),
    ]

    private let bullets = Self.bulletsForTesting

    var body: some View {
        OnboardingLayout(title: String(localized: "Your own AI coworkers.")) {
            VStack(alignment: .leading, spacing: Space.l) {
                AppMarkView(size: 64)
                    .padding(.bottom, Space.s)

                Text(String(localized: "Agents that run on your Mac, with their own browser and their own files."))
                    .bodyText()
                    .foregroundStyle(Palette.textSecondary)

                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                        HStack(alignment: .top, spacing: Space.s) {
                            Text("•")
                                .bodyEmphasis()
                            Text(bullet)
                                .bodyText()
                        }
                        .foregroundStyle(Palette.textPrimary)
                        .opacity(revealed > index ? 1 : 0)
                        .offset(y: revealed > index ? 0 : 8)
                        .motion(Motion.standard, value: revealed)
                    }
                }

                Button(String(localized: "Get started"), action: onContinue)
                    .buttonStyle(XBotButtonStyle())
                    .padding(.top, Space.l)
                    .opacity(revealed >= bullets.count ? 1 : 0)
                    .motion(Motion.standard, value: revealed)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                revealed = bullets.count
                return
            }
            for index in 0...bullets.count {
                Task {
                    try? await Task.sleep(for: .milliseconds(index * 40))
                    revealed = index
                }
            }
        }
    }
}
