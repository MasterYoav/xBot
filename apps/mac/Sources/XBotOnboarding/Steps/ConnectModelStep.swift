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
                 * What leaves the Mac, before a key is typed.
                 *
                 * ADR-0007 set the rule and it outlives the CopilotKit key it was written for:
                 * onboarding says where conversations are kept, in one sentence, before a key is
                 * typed. Since ADR-0008 they are kept on this Mac, and the one thing that does leave
                 * is what a person sends to the model they pick — so that is what this names.
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
        localized: "Your agents, their files, and your conversations stay on this Mac. What you send an agent goes to the model you choose here — or nowhere, if the model runs on this Mac."
    )

    /// Says the part that is not local, in the place it can still change a decision.
    @ViewBuilder
    private var transcriptDisclosure: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
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
