import SwiftUI
import XBotCore
import XBotUI

struct ConnectModelStep: View {
    @Bindable var coordinator: OnboardingCoordinator
    @FocusState private var keyFocused: Bool

    var body: some View {
        OnboardingLayout(
            title: String(localized: "Choose a model"),
            showsBack: true,
            onBack: coordinator.back
        ) {
            VStack(alignment: .leading, spacing: Space.l) {
                Text(String(
                    localized: "xBot doesn't include an AI model. Connect one you have a key for, or run one on your Mac for free."
                ))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)

                /*
                 * Where conversations are kept, before a key is typed.
                 *
                 * ADR-0007 requires exactly this and is specific about the placement: "Onboarding
                 * says where conversations are stored, in one sentence, before the user types a key
                 * — not in a privacy policy, and not after. An app whose pitch is local control
                 * must not be vague about the part that is not local."
                 *
                 * Above the provider list rather than under the field, because a disclosure a
                 * person reads after choosing is a disclosure that arrived too late to inform the
                 * choice.
                 */
                transcriptDisclosure

                VStack(spacing: Space.xs) {
                    ForEach(ModelProviderCatalog.all) { provider in
                        providerRow(provider)
                    }
                }

                if selectedProvider.needsKey {
                    keyField
                } else {
                    ollamaRow
                }

                intelligenceField

                HStack {
                    Button(String(localized: "Skip for now"), action: coordinator.skipModelConnection)
                        .buttonStyle(XBotButtonStyle())
                    Spacer()
                    connectButton
                }
            }
        }
        .task { await coordinator.refreshOllamaState() }
    }

    private var selectedProvider: ModelProviderOption {
        ModelProviderCatalog.option(id: coordinator.selectedProviderID) ?? ModelProviderCatalog.all[0]
    }

    private func providerRow(_ provider: ModelProviderOption) -> some View {
        let selected = coordinator.selectedProviderID == provider.id
        return Button {
            coordinator.selectProvider(provider.id)
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Palette.stateRunning : Palette.textTertiary)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(provider.name)
                        .bodyEmphasis()
                    Text(provider.subtitle)
                        .captionText()
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                if provider.id == "ollama", let count = coordinator.ollamaModelCount {
                    Text(String(localized: "Detected · \(count) models"))
                        .captionText()
                        .foregroundStyle(Palette.stateRunning)
                }
            }
            .padding(Space.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(selected ? Palette.elevatedSurface.opacity(0.9) : Palette.elevatedSurface.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    /// The sentence ADR-0007 requires. One source, so a test can hold the product to it.
    static let transcriptDisclosureText = String(
        localized: "Your agents and their files stay on this Mac. Your conversation history is stored by CopilotKit, the service xBot's engine is built on, so it leaves your Mac."
    )

    /// Says the part that is not local, in the place it can still change a decision.
    @ViewBuilder
    private var transcriptDisclosure: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "cloud")
                .font(.system(size: 13))
                .foregroundStyle(Palette.stateReconnecting)
            Text(Self.transcriptDisclosureText)
            .captionText()
            .foregroundStyle(Palette.textSecondary)
        }
        .padding(Space.s)
        .background(
            Palette.elevatedSurface,
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// The CopilotKit key, beside the model key, as ADR-0007 describes.
    ///
    /// Its own field rather than folded into the provider list, because it is not a model — it is
    /// where conversations are kept. Optional here so somebody evaluating the app still reaches a
    /// window; the composer says what is missing rather than the first turn failing.
    private var intelligenceField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(String(localized: "CopilotKit key"))
                .captionText()
                .foregroundStyle(Palette.textSecondary)
            SecureField(
                String(localized: "Paste your CopilotKit key"),
                text: $coordinator.intelligenceKey
            )
            .textFieldStyle(.roundedBorder)
            Text(String(
                localized: "Needed for xBot to keep your conversations. You can add it later in Settings — until then agents can't reply."
            ))
            .captionText()
            .foregroundStyle(Palette.textTertiary)
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SecureField(String(localized: "Paste your key here"), text: $coordinator.apiKey)
                .textFieldStyle(.roundedBorder)
                .focused($keyFocused)
                .onChange(of: coordinator.apiKey) { _, _ in
                    if case .failed = coordinator.validation {
                        coordinator.resetValidation()
                    }
                }

            Text(String(
                localized: "Your key is stored in your Mac's Keychain and only sent to \(ModelProviderCatalog.vendorName(for: coordinator.selectedProviderID))."
            ))
            .captionText()
            .foregroundStyle(Palette.textSecondary)

            if case .failed(let message) = coordinator.validation {
                Text(message)
                    .captionText()
                    .foregroundStyle(Palette.stateFailed)
            }
        }
    }

    @ViewBuilder
    private var ollamaRow: some View {
        if coordinator.ollamaModelCount == nil {
            Text(String(localized: "Ollama isn't running on this Mac."))
                .captionText()
                .foregroundStyle(Palette.textTertiary)
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        let validating = coordinator.validation == .validating
        Button(validating ? String(localized: "Checking…") : String(localized: "Connect")) {
            Task { _ = await coordinator.validateAndConnect() }
        }
        .buttonStyle(XBotButtonStyle())
        .disabled(!coordinator.canConnect || validating)
    }
}
