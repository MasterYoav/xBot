import Foundation
import IOKit.pwr_mgt
import Observation
import XBotRemote

/// A phone or iPad paired with this Mac.
public struct PairedDevice: Codable, Equatable, Sendable, Identifiable {
    /// The pairing key's identity.
    public var id: String
    public var name: String
    public var pairedAt: Date
    public var lastSeen: Date?
}

/// Where pairing secrets are kept: the Keychain in the app, a dictionary in tests.
public protocol PairingSecrets: Sendable {
    func secret(for id: String) -> Data?
    func save(_ secret: Data, for id: String)
    func remove(_ id: String)
}

public struct KeychainPairingSecrets: PairingSecrets {
    static let service = "dev.xbot.remote.pairing"
    public init() {}
    public func secret(for id: String) -> Data? {
        (try? KeychainSecretStore.readExisting(service: Self.service, account: id)).flatMap { $0 }.flatMap { Data(base64Encoded: $0) }
    }
    public func save(_ secret: Data, for id: String) {
        try? KeychainSecretStore.write(secret.base64EncodedString(), service: Self.service, account: id)
    }
    public func remove(_ id: String) { try? KeychainSecretStore.remove(service: Self.service, account: id) }
}

/**
 xBot on the iPhone and iPad, from the Mac's side: pairing, the two lanes, and staying awake.

 Off until the first device is paired: no listener, no iCloud, nothing. With devices paired, a
 local listener waits on the kernel and an iCloud subscription waits for pushes; a phone attaches
 through whichever it reaches, and `RemoteHost` serves it.
 */
@MainActor @Observable
public final class RemoteService {
    public private(set) var devices: [PairedDevice] = []
    /// Who is attached right now, and how.
    public private(set) var attached: [String: RemoteLane] = [:]
    /// The local listener's port, once it's listening.
    public private(set) var port: UInt16?
    /// Why iCloud isn't available, if it isn't (no entitlement, signed out).
    public private(set) var cloudProblem: String?
    public let macID: UUID
    public let macName: String
    public let host: RemoteHost
    /// Called once iCloud is ready: the app registers for its silent pushes.
    @ObservationIgnored public var wantsPushes: (() -> Void)?

    @ObservationIgnored private let secrets: any PairingSecrets
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let listener = LocalListener()
    @ObservationIgnored private let advertise: Bool
    @ObservationIgnored private var mailbox: (any CloudMailbox)?
    @ObservationIgnored private var channels: [String: CloudChannel<HostMessage, ClientMessage>] = [:]
    @ObservationIgnored private var cloudLinks: [String: CloudLink] = [:]
    @ObservationIgnored private var sleepAssertion: IOPMAssertionID = 0
    /// A phone away from home that hasn't written for this long is let go.
    @ObservationIgnored let cloudTimeout: Duration

    public init(workspace: Workspace, secrets: any PairingSecrets = KeychainPairingSecrets(),
                defaults: UserDefaults = .standard, macName: String = Host.current().localizedName ?? "Mac",
                mailbox: (any CloudMailbox)? = nil, advertise: Bool = true, cloudTimeout: Duration = .seconds(150)) {
        self.secrets = secrets
        self.defaults = defaults
        self.advertise = advertise
        self.cloudTimeout = cloudTimeout
        if let saved = defaults.string(forKey: "remote.macID").flatMap(UUID.init(uuidString:)) {
            macID = saved
        } else {
            macID = UUID()
            defaults.set(macID.uuidString, forKey: "remote.macID")
        }
        self.macName = macName
        host = RemoteHost(workspace: workspace, macName: macName, macID: macID)
        self.mailbox = mailbox
        if let data = defaults.data(forKey: "remote.devices"), let saved = try? JSONDecoder().decode([PairedDevice].self, from: data) {
            devices = saved.filter { secrets.secret(for: $0.id) != nil }
        }
        host.keepAwake = { [weak self] in self?.setAwake($0) }
        listener.onReady = { [weak self] in self?.port = $0 }
        listener.onConnection = { [weak self] in self?.accept($0) }
    }

    /// Starts the lanes if anything is paired. Called at launch.
    public func start() {
        guard !devices.isEmpty else { return }
        restartListener()
        Task { await startCloud() }
    }

    // MARK: Pairing

    /// A new device's invite, for the QR code. The device is listed once it first connects.
    public func invite(host address: String? = nil) -> PairingInvite {
        let key = PairingKey.generate()
        secrets.save(key.secret, for: key.identity)
        pending.insert(key.identity)
        restartListener(including: key)
        Task { await startCloud() }
        return PairingInvite(macID: macID, macName: macName, key: key, host: address, port: port)
    }

    @ObservationIgnored private var pending: Set<String> = []

    public func remove(_ id: String) {
        devices.removeAll { $0.id == id }
        secrets.remove(id)
        save()
        cloudLinks[id]?.close()
        for link in localLinks.values where link.deviceID == id { link.close() }
        channels[id] = nil
        restartListener()
        if devices.isEmpty { listener.stop(); port = nil }
    }

    private func keys(including extra: PairingKey? = nil) -> [PairingKey] {
        var keys = (devices.map(\.id) + pending).compactMap { id in secrets.secret(for: id).map { PairingKey(identity: id, secret: $0) } }
        if let extra, !keys.contains(extra) { keys.append(extra) }
        return keys
    }

    private func restartListener(including extra: PairingKey? = nil) {
        let keys = keys(including: extra)
        guard !keys.isEmpty else { return }
        try? listener.start(keys: keys, macID: macID, macName: macName, advertise: advertise, port: port)
    }

    /// A device spoke: list it if it's new, and note when it was seen.
    func seen(_ id: String, name: String) {
        pending.remove(id)
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].lastSeen = .now
            if devices[index].name != name { devices[index].name = name }
        } else if secrets.secret(for: id) != nil {
            devices.append(PairedDevice(id: id, name: name, pairedAt: .now, lastSeen: .now))
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) { defaults.set(data, forKey: "remote.devices") }
    }

    // MARK: Local lane

    @ObservationIgnored private var localLinks: [UUID: LocalLink] = [:]

    private func accept(_ connection: FramedConnection<ClientMessage>) {
        let link = LocalLink(connection)
        // Held here until it closes: nothing else holds it before its hello.
        localLinks[link.id] = link
        connection.onState = { [weak self, weak link] state in
            guard let self, let link else { return }
            if case .closed = state {
                link.close()
                self.localLinks[link.id] = nil
                if let device = link.deviceID, self.attached[device] == .local {
                    self.attached[device] = self.cloudLinks[device] == nil ? nil : .cloud
                }
            }
        }
        // The first message says who it is; then the host takes over.
        connection.onMessages = { [weak self, weak link] messages in
            guard let self, let link else { return }
            for message in messages { link.deliver(message, service: self) }
        }
        connection.start()
    }

    fileprivate func localHello(_ link: LocalLink, deviceID: String, name: String) {
        guard secrets.secret(for: deviceID) != nil else { return link.close() }
        seen(deviceID, name: name)
        attached[deviceID] = .local
        host.attach(link)
    }

    // MARK: iCloud lane

    private func startCloud() async {
        if mailbox == nil {
            guard Self.hasCloudEntitlement else {
                cloudProblem = String(localized: "This copy of xBot isn't signed for iCloud, so phones can reach it on the same network only.")
                return
            }
            let box = CloudKitMailbox(side: "mac")
            do {
                try await box.prepare(subscriptionID: "xbot-remote-mac")
                mailbox = box
                cloudProblem = nil
                wantsPushes?()
            } catch {
                cloudProblem = String(localized: "iCloud isn't available: \(error.localizedDescription)")
                return
            }
        }
        await cloudPushed()
    }

    @ObservationIgnored private var cloudPass: Task<Void, Never>?

    /// A push said the mailbox changed (or the app just started): read it once for every device.
    /// One read at a time: a push during a read waits for it, then reads again.
    public func cloudPushed() async {
        let previous = cloudPass
        let pass = Task { [weak self] in
            await previous?.value
            await self?.readCloud()
        }
        cloudPass = pass
        await pass.value
    }

    private func readCloud() async {
        guard let mailbox, let fetched = try? await mailbox.fetchNew(), !fetched.isEmpty else { return }
        for id in Set(fetched.filter { $0.to == "mac" }.map(\.from)) where channels[id] == nil {
            guard let secret = secrets.secret(for: id) else { continue }
            channels[id] = CloudChannel(me: "mac", peer: id, secret: secret, mailbox: mailbox)
        }
        for (id, channel) in channels {
            let messages = await channel.receive(fetched)
            guard !messages.isEmpty else { continue }
            let link = cloudLinks[id] ?? attachCloud(id, channel: channel, messages: messages)
            link.heard()
            for message in messages { link.onReceive?(message) }
        }
    }

    private func attachCloud(_ id: String, channel: CloudChannel<HostMessage, ClientMessage>, messages: [ClientMessage]) -> CloudLink {
        let name = messages.lazy.compactMap { if case .hello(_, _, let n) = $0 { n } else { nil } }.first
            ?? devices.first { $0.id == id }?.name ?? String(localized: "iPhone")
        seen(id, name: name)
        let link = CloudLink(deviceID: id, channel: channel, timeout: cloudTimeout)
        link.onGone = { [weak self] in
            self?.cloudLinks[id] = nil
            if self?.attached[id] == .cloud { self?.attached[id] = nil }
        }
        cloudLinks[id] = link
        // Already here directly: the local lane wins; the phone stops writing to iCloud once it sees it.
        if attached[id] == nil { attached[id] = .cloud }
        host.attach(link)
        return link
    }

    static var hasCloudEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        return (value as? [String])?.contains(CloudKitMailbox.containerID) == true
    }

    // MARK: Awake

    private func setAwake(_ on: Bool) {
        if on, sleepAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "xBot: a phone is attached or an agent is working" as CFString, &sleepAssertion)
        } else if !on, sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }
}

/// A phone on the local network.
@MainActor final class LocalLink: RemoteLink {
    let id = UUID()
    let lane = RemoteLane.local
    var onReceive: ((ClientMessage) -> Void)?
    var onClose: (() -> Void)?
    private(set) var deviceID: String?
    private let connection: FramedConnection<ClientMessage>
    private var closed = false

    init(_ connection: FramedConnection<ClientMessage>) { self.connection = connection }

    func send(_ messages: [HostMessage]) { connection.send(messages) }

    func deliver(_ message: ClientMessage, service: RemoteService) {
        if deviceID == nil {
            // The TLS handshake proved the key; the hello names the device it belongs to.
            guard case .hello(_, let identity, let name) = message else { return }
            deviceID = identity
            service.localHello(self, deviceID: identity, name: name)
            return
        }
        onReceive?(message)
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?()
    }
}

/// A phone away from home, through iCloud.
@MainActor final class CloudLink: RemoteLink {
    let id = UUID()
    let lane = RemoteLane.cloud
    let deviceID: String
    var onReceive: ((ClientMessage) -> Void)?
    var onClose: (() -> Void)?
    var onGone: (() -> Void)?
    private let channel: CloudChannel<HostMessage, ClientMessage>
    private let timeout: Duration
    private var watchdog: Task<Void, Never>?

    init(deviceID: String, channel: CloudChannel<HostMessage, ClientMessage>, timeout: Duration) {
        self.deviceID = deviceID
        self.channel = channel
        self.timeout = timeout
    }

    func send(_ messages: [HostMessage]) {
        let channel = channel
        Task { try? await channel.send(messages) }
    }

    /// The phone wrote: it's still there. Silent for `timeout`, it's let go.
    func heard() {
        watchdog?.cancel()
        let timeout = timeout
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func close() {
        watchdog?.cancel()
        onClose?()
        onGone?()
    }
}
