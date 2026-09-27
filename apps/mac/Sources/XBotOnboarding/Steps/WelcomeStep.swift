import SwiftUI
import XBotUI

struct WelcomeStep: View {
    let onContinue: () -> Void
    @State private var revealed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /*
     * What v1 actually does, rather than what the pitch would prefer.
     *
     * The third bullet used to read "Everything stays here. No account, no cloud." "No cloud" is
     * still not true of a hosted model: what a person sends it goes to its vendor, and step four
     * says so before a key is typed. What is true since ADR-0008 is that conversations are kept
     * here, alongside the agents, their files and their browsers — so that is what it claims.
     */
    /// The promises this screen makes. Exposed so a test can hold them to what v1 does.
    static let bulletsForTesting = [
        String(localized: "Bring any model — or run one locally, with nothing leaving your Mac"),
        String(localized: "Watch what your agents do, and take over whenever you want"),
        String(localized: "Your agents, their files, and your conversations stay on this Mac"),
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
