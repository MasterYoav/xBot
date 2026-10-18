import SwiftUI
import XBotCore
import XBotRemote

/// Step 9 (optional): the same pairing code as Settings › Devices, with the same rules: it pairs one
/// device, runs out after its lifetime, and stops working as soon as the step is left.
struct PhoneStepView: View {
    let remote: RemoteService?
    let notNow: () -> Void
    @State private var invite: PairingInvite?

    var body: some View {
        StepPage(copy: .of(.phone)) {
            PhoneScene()
        } controls: {
            VStack(alignment: .leading, spacing: Space.m) {
                if let remote {
                    if let invite {
                        code(invite, remote: remote)
                    } else {
                        Text(String(localized: "Open xBot on your iPhone or iPad, then show the code here and scan it."))
                            .captionText().foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Space.s) {
                            Button(String(localized: "Show the code")) { invite = remote.invite(host: LocalAddress.ipv4) }
                                .buttonStyle(PrimaryButtonStyle())
                            Button(String(localized: "Not now"), action: notNow)
                                .buttonStyle(QuietButtonStyle())
                        }
                    }
                } else {
                    Text(String(localized: "Pairing isn't available in this copy of xBot."))
                        .captionText().foregroundStyle(Palette.textTertiary)
                }
            }
        }
        // Leaving the step, however it's left, withdraws a code nobody used.
        .onDisappear { withdraw() }
    }

    @ViewBuilder private func code(_ invite: PairingInvite, remote: RemoteService) -> some View {
        if let device = remote.devices.first(where: { $0.id == invite.key.identity }) {
            Label(String(localized: "Paired with \(device.name)."), systemImage: "checkmark.circle.fill")
                .emphasisText().foregroundStyle(Palette.success)
        } else if !remote.isLive(invite) {
            Label(String(localized: "This code has expired."), systemImage: "clock.badge.xmark")
                .captionText().foregroundStyle(Palette.textSecondary)
            Button(String(localized: "Show a new code")) {
                withdraw()
                self.invite = remote.invite(host: LocalAddress.ipv4)
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            HStack(alignment: .top, spacing: Space.m) {
                if let image = QRCode.image(invite.url.absoluteString) {
                    Image(nsImage: image).interpolation(.none).resizable()
                        .frame(width: Metrics.onboardingQR, height: Metrics.onboardingQR)
                        .padding(Space.s)
                        .background(Palette.knob, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .accessibilityLabel(String(localized: "Pairing code"))
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(String(localized: "Scan it with xBot on your iPhone or iPad."))
                        .captionText().foregroundStyle(Palette.textSecondary)
                    Text(String(localized: "It pairs one device. Keep it to yourself: it's the key to this Mac."))
                        .captionText().foregroundStyle(Palette.textTertiary)
                    Button(String(localized: "Hide the code")) { withdraw() }
                        .buttonStyle(QuietButtonStyle())
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func withdraw() {
        if let invite { remote?.withdraw(invite) }
        invite = nil
    }
}
