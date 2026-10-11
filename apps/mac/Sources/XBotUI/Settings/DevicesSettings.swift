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
                Button(String(localized: "Pair an iPhone or iPad…")) { invite = remote?.invite(host: LocalAddress.ipv4) }
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
        .sheet(item: Binding(get: { invite.map(InviteBox.init) }, set: { if $0 == nil { invite = nil } })) { box in
            PairingSheet(invite: box.invite, remote: remote) { invite = nil }
        }
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

private struct InviteBox: Identifiable {
    let invite: PairingInvite
    var id: String { invite.key.identity }
}

/// The QR code, until the device connects.
private struct PairingSheet: View {
    let invite: PairingInvite
    let remote: RemoteService?
    let done: () -> Void

    private var paired: Bool { remote?.devices.contains { $0.id == invite.key.identity } == true }

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
            } else if let image = QRCode.image(invite.url.absoluteString) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 220, height: 220)
                    .accessibilityLabel(String(localized: "Pairing code"))
                Text(String(localized: "The code works once, for one device. Keep it to yourself: it's the key to this Mac."))
                    .captionText().foregroundStyle(Palette.textTertiary).multilineTextAlignment(.center)
            }
            HStack {
                Spacer()
                Button(paired ? String(localized: "Done") : String(localized: "Cancel"), action: done)
                    .keyboardShortcut(paired ? .defaultAction : .cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 380)
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
