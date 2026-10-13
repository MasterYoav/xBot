import SwiftUI

/// Step 11: the crew in the chosen world, and Start.
struct ReadyStepView: View {
    let start: () -> Void

    var body: some View {
        StepPage(copy: .of(.ready), controlsBelow: true, zoom: 1) {
            ReadyScene()
        } controls: {
            VStack(spacing: Space.s) {
                Button(String(localized: "Start"), action: start)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Text(String(localized: "Help › Welcome Tour shows this again."))
                    .captionText().foregroundStyle(Palette.textTertiary)
            }
        }
    }
}
