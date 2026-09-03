import SwiftUI
import XBotUI

struct OnboardingLayout<Content: View>: View {
    let title: String
    var showsBack = false
    var onBack: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack {
                    if showsBack, let onBack {
                        Button(action: onBack) {
                            Label(String(localized: "Back"), systemImage: "chevron.left")
                        }
                        .buttonStyle(XBotButtonStyle())
                    }
                    Spacer()
                }

                Text(title)
                    .displayTitle()
                    .foregroundStyle(Palette.textPrimary)

                content()

                Spacer(minLength: 0)
            }
            .padding(Space.xxl)
        }
        .frame(width: Metrics.onboardingWindow.width, height: Metrics.onboardingWindow.height)
        .background(WindowChromeConfigurator(style: .onboarding))
    }
}
