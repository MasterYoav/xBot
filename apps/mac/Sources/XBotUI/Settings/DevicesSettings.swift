import CoreImage.CIFilterBuiltins
import SwiftUI
import XBotCore
import XBotRemote

/// Settings › Devices: pair an iPhone or iPad, see which are connected, remove one.
struct DevicesSettings: View {
    let workspace: Workspace
    @State private var invite: PairingInvite?

    private var remote: RemoteService? { workspace.remote }

    var body: some View {
        Form {
            Section {
                Text(String(localized: "Keep working from your iPhone or iPad: your chats live, and the agents still run here. On the same Wi-Fi it connects directly; away, through your iCloud."))
                    .captionText().foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Pair an iPhone or iPad…")) { newInvite() }
                    .disabled(remote == nil)
            }
            if let remote {
                Section(String(localized: "Paired")) {
                    if remote.devices.isEmpty {
                        Text(String(localized: "None yet.")).foregroundStyle(Palette.textTertiary)
                    }
                    ForEach(remote.devices) { device in
                        HStack {
                            Image(systemName: device.name.localizedCaseInsensitiveContains("iPad") ? "ipad" : "iphone")
                                .foregroundStyle(Palette.textSecondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name)
                                Text(status(of: device, in: remote)).captionText().foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            Button(String(localized: "Remove"), role: .destructive) { remote.remove(device.id) }
                                .accessibilityLabel(String(localized: "Remove \(device.name)"))
                        }
                    }
                }
                Section {
                    Label(String(localized: "While a device is connected or an agent is working, this Mac stays awake. With the lid closed on battery it still sleeps."),
                          systemImage: "moon.zzz")
                        .captionText().foregroundStyle(Palette.textTertiary)
                    if let problem = remote.cloudProblem {
                        Label(problem, systemImage: "exclamationmark.icloud").captionText().foregroundStyle(Palette.warning)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // One sheet for the whole visit: a new code replaces the old one in place.
        .sheet(isPresented: Binding(get: { invite != nil }, set: { (shown: Bool) in if !shown { closeInvite() } })) {
            if let invite {
                PairingSheet(invite: invite, remote: remote, renew: { newInvite() }, done: { closeInvite() })
            }
        }
    }

    /// A fresh code; the one on screen before it (if any) stops working.
    private func newInvite() {
        if let invite { remote?.withdraw(invite) }
        invite = remote?.invite(host: LocalAddress.ipv4)
        #if DEBUG
        // For the simulator, which has no camera: `xcrun simctl openurl booted <this>`.
        if let invite { print("XBOT_PAIRING_URL \(invite.url.absoluteString)") }
        #endif
    }

    /// The sheet closed, however it closed: a code nobody used stops working at once.
    private func closeInvite() {
        if let invite { remote?.withdraw(invite) }
        invite = nil
    }

    private func status(of device: PairedDevice, in remote: RemoteService) -> String {
        switch remote.attached[device.id] {
        case .local: String(localized: "Connected · same network")
        case .cloud: String(localized: "Connected · through iCloud")
        case nil:
            device.lastSeen.map { String(localized: "Last seen \($0.formatted(.relative(presentation: .named)))") }
                ?? String(localized: "Not connected yet")
        }
    }
}

/// The QR code, until the device connects or the code runs out.
private struct PairingSheet: View {
    let invite: PairingInvite
    let remote: RemoteService?
    let renew: () -> Void
    let done: () -> Void

    private var paired: Bool { remote?.devices.contains { $0.id == invite.key.identity } == true }
    private var expired: Bool { !paired && remote?.isLive(invite) != true }
    private var minutes: Int { max(1, Int((remote?.inviteLifetime ?? .seconds(600)).components.seconds / 60)) }

    var body: some View {
        VStack(spacing: Space.l) {
            HStack {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 18)).foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: Radius.medium).fill(Palette.accentTint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Pair an iPhone or iPad")).titleText()
                    Text(String(localized: "Open xBot on it and scan this code.")).captionText().foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                IconButton("xmark", help: String(localized: "Close"), action: done)
            }
            if paired {
                Label(String(localized: "Paired. You can close this."), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success).frame(height: 220)
            } else if expired {
                VStack(spacing: Space.m) {
                    Label(String(localized: "This code has expired."), systemImage: "clock.badge.xmark")
                        .foregroundStyle(Palette.textSecondary)
                    Button(String(localized: "Show a new code"), action: renew)
                }
                .frame(height: 220)
            } else if let image = QRCode.image(invite.url.absoluteString) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 220, height: 220)
                    .accessibilityLabel(String(localized: "Pairing code"))
                Text(String(localized: "The code pairs one device and works for \(minutes) minutes, until you close this. Keep it to yourself: it's the key to this Mac."))
                    .captionText().foregroundStyle(Palette.textTertiary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(paired ? String(localized: "Done") : String(localized: "Cancel"), action: done)
                    .keyboardShortcut(paired ? .defaultAction : .cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 380)
        // However the sheet goes (Settings closed with it open, say), an unused code stops working.
        .onDisappear { remote?.withdraw(invite) }
    }
}

enum QRCode {
    static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}

/// This Mac's Wi-Fi/Ethernet address, put in the invite so a phone can connect even where
/// Bonjour is blocked.
enum LocalAddress {
    static var ipv4: String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return nil }
        defer { freeifaddrs(first) }
        var found: String?
        for pointer in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                found = String(cString: host)
                if name == "en0" { break }
            }
        }
        return found
    }
}
