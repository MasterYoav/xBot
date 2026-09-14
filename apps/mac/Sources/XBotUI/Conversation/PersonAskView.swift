import SwiftUI
import XBotCore
import XBotEngine

/// The agent asking the person for something it cannot do itself. Sits above the composer, where the
/// person is already looking, for as long as the turn waits on it.
struct PersonAskView: View {
    @Environment(AppState.self) private var state
    let ask: PersonAsk

    @State private var secret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            switch ask {
            case .help(let reason):
                Text(String(localized: "\(agentName) needs you"))
                    .bodyEmphasis()
                if !reason.isEmpty {
                    Text(reason).captionText().foregroundStyle(Palette.textSecondary)
                }
                Button(String(localized: "Take control")) { state.takeControlForAsk() }
                    .buttonStyle(XBotButtonStyle())
                    .disabled(state.control == .human)

            case .secret(let label):
                Text(String(localized: "\(agentName) is asking for \(label)"))
                    .bodyEmphasis()
                Text(String(localized: "It's typed straight into the page. \(agentName) is never told what it is."))
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
                HStack(spacing: Space.s) {
                    SecureField(label, text: $secret)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                    Button(String(localized: "Enter"), action: submit)
                        .buttonStyle(XBotButtonStyle())
                        .disabled(secret.isEmpty)
                }
                if let problem = state.secretProblem {
                    Text(problem).captionText().foregroundStyle(Palette.attention)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.elevatedSurface, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Palette.attention, lineWidth: 1)
        )
    }

    private var agentName: String { state.selectedAgent?.name ?? String(localized: "Your agent") }

    private func submit() {
        state.supplySecret(secret)
        // Out of this view's memory the moment it is sent, success or not.
        secret = ""
    }
}
