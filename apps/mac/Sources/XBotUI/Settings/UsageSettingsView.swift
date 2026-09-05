import SwiftUI
import XBotCore

/// Settings → Usage. Honest empty state until the engine records token counts.
public struct UsageSettingsView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        Form {
            Section {
                if state.models.isEmpty {
                    Text(String(localized: "Connect a model to see usage here."))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(state.models, id: \.wireIdentity) { model in
                        LabeledContent("\(model.model) · \(model.provider)") {
                            Text(String(localized: "Not tracked yet"))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            } header: {
                Text(String(localized: "Providers"))
            } footer: {
                Text(
                    String(
                        localized:
                            "Usage tracking is coming in a future update. xBot never shows a quota percentage — your limits are with your vendor."
                    )
                )
            }
        }
        .formStyle(.grouped)
    }
}
