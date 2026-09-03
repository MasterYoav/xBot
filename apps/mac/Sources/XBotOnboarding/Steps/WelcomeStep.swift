import SwiftUI
import XBotUI

struct WelcomeStep: View {
    let onContinue: () -> Void
    @State private var revealed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bullets = [
        String(localized: "Bring any model — or run one locally, with nothing leaving your Mac"),
        String(localized: "Watch what your agents do, and take over whenever you want"),
        String(localized: "Everything stays here. No account, no cloud"),
    ]

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
