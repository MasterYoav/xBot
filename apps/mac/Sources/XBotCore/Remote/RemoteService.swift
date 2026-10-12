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
    /// The installation of the app that paired with the key: no other may use it. (A device
    /// paired before this was recorded claims it with its next hello.)
    public var installID: String?
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

/// Pairing keys in a JSON file (identity → base64 secret), for debug builds run on a sandbox home:
/// each rebuild changes the binary's signature, and the login Keychain would ask for the password
/// every time. Never used by a release.
public struct FilePairingSecrets: PairingSecrets {
    let url: URL
    public init(url: URL) { self.url = url }

    private func read() -> [String: String] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    private func write(_ all: [String: String]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: url, options: [.atomic, .completeFileProtection])
    }

    public func secret(for id: String) -> Data? { read()[id].flatMap { Data(base64Encoded: $0) } }
    public func save(_ secret: Data, for id: String) { var all = read(); all[id] = secret.base64EncodedString(); write(all) }
    public func remove(_ id: String) { var all = read(); all[id] = nil; write(all) }
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

    /// How often the Mac reads iCloud on its own. Pushes are best-effort (Apple throttles and
    /// coalesces them), so they only make it quicker: a phone attached through iCloud is read
    /// every couple of seconds, like the phone reads the Mac; otherwise a slow check finds a phone
    /// that just went away. Each check is one small CloudKit request.
    public struct CloudChecks: Sendable {
        public var attached: Duration
        public var idle: Duration
        public init(attached: Duration = .seconds(2), idle: Duration = .seconds(15)) {
            self.attached = attached
            self.idle = idle
        }
    }

    @ObservationIgnored let cloudChecks: CloudChecks
    @ObservationIgnored private var cloudClock: Task<Void, Never>?

    public init(workspace: Workspace, secrets: any PairingSecrets = KeychainPairingSecrets(),
                defaults: UserDefaults = .standard, macName: String = Host.current().localizedName ?? "Mac",
                mailbox: (any CloudMailbox)? = nil, advertise: Bool = true, cloudTimeout: Duration = .seconds(150),
                cloudChecks: CloudChecks = .init(), inviteLifetime: Duration = .seconds(600)) {
        self.secrets = secrets
        self.inviteLifetime = inviteLifetime
        self.cloudChecks = cloudChecks
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
        // Invites still outstanding when xBot last quit were never used: take their keys back.
        for id in defaults.stringArray(forKey: "remote.pending") ?? [] where !devices.contains(where: { $0.id == id }) {
            secrets.remove(id)
        }
        defaults.removeObject(forKey: "remote.pending")
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

    /// A new device's invite, for the QR code. The device is listed once it first connects. The
    /// invite works once, until the sheet is closed (`withdraw`) or `inviteLifetime` passes,
    /// whichever comes first; xBot quitting withdraws it too (see `init`).
    public func invite(host address: String? = nil) -> PairingInvite {
        let key = PairingKey.generate()
        secrets.save(key.secret, for: key.identity)
        invites[key.identity] = Date.now.addingTimeInterval(Self.seconds(inviteLifetime))
        savePending()
        let lifetime = inviteLifetime
        expiries[key.identity] = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            self?.withdraw(key.identity)
        }
        restartListener(including: key)
        Task { await startCloud() }
        return PairingInvite(macID: macID, macName: macName, key: key, host: address, port: port)
    }

    /// Invites shown and not yet used, and when each stops working.
    public private(set) var invites: [String: Date] = [:]
    @ObservationIgnored private var expiries: [String: Task<Void, Never>] = [:]
    /// How long a pairing code works if nobody uses it.
    @ObservationIgnored public let inviteLifetime: Duration

    /// Whether this invite's code can still pair a device.
    public func isLive(_ invite: PairingInvite) -> Bool { isLiveInvite(invite.key.identity) }

    private func isLiveInvite(_ id: String) -> Bool { invites[id].map { $0 > .now } ?? false }

    /// A key the Mac answers to: a paired device's, or a live invite's. Anything else in the
    /// Keychain (an invite from an older build, say) opens nothing.
    private func accepts(_ id: String) -> Bool { devices.contains { $0.id == id } || isLiveInvite(id) }

    /// The sheet closed: an invite nobody used stops working, on both lanes, and its key leaves
    /// the Keychain. Once a device has paired with it, this does nothing.
    public func withdraw(_ invite: PairingInvite) { withdraw(invite.key.identity) }

    func withdraw(_ id: String) {
        expiries.removeValue(forKey: id)?.cancel()
        guard invites.removeValue(forKey: id) != nil else { return }
        savePending()
        guard !devices.contains(where: { $0.id == id }) else { return }
        secrets.remove(id)
        channels[id] = nil
        for link in localLinks.values where link.deviceID == id { link.close() }
        restartListener()
    }

    public func remove(_ id: String) {
        devices.removeAll { $0.id == id }
        secrets.remove(id)
        save()
        cloudMarks[id] = nil
        cloudLinks[id]?.close()
        for link in localLinks.values where link.deviceID == id { link.close() }
        channels[id] = nil
        restartListener()
    }

    private func keys(including extra: PairingKey? = nil) -> [PairingKey] {
        var keys = (devices.map(\.id) + invites.keys.filter(isLiveInvite)).compactMap { id in
            secrets.secret(for: id).map { PairingKey(identity: id, secret: $0) }
        }
        if let extra, !keys.contains(extra) { keys.append(extra) }
        return keys
    }

    /// Listens with exactly the keys the Mac accepts now; with none, stops (and stops reading iCloud).
    private func restartListener(including extra: PairingKey? = nil) {
        let keys = keys(including: extra)
        guard !keys.isEmpty else {
            listener.stop()
            port = nil
            stopCloudClock()
            return
        }
        try? listener.start(keys: keys, macID: macID, macName: macName, advertise: advertise, port: port)
    }

    /// A device said hello with a key the Mac accepts: list it if it's new, and note when it was
    /// seen. An invite pairs one installation: the first to say hello with its key is the device,
    /// and the key is refused from any other. False (and nothing changes) when refused.
    @discardableResult
    func admit(_ id: String, installID: String?, name: String) -> Bool {
        guard let installID, !installID.isEmpty, accepts(id), secrets.secret(for: id) != nil else { return false }
        if let index = devices.firstIndex(where: { $0.id == id }) {
            if let claimed = devices[index].installID, claimed != installID { return false }
            devices[index].installID = installID
            devices[index].lastSeen = .now
            if devices[index].name != name { devices[index].name = name }
        } else {
            expiries.removeValue(forKey: id)?.cancel()
            invites[id] = nil
            savePending()
            devices.append(PairedDevice(id: id, name: name, pairedAt: .now, lastSeen: .now, installID: installID))
        }
        save()
        return true
    }

    /// Invites outstanding, by identity, so a relaunch can take back the ones never used.
    private func savePending() { defaults.set(Array(invites.keys), forKey: "remote.pending") }

    static func seconds(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
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

    /// A phone nearby said who it is. False if it's refused (the caller closes it).
    fileprivate func localHello(_ link: LocalLink, deviceID: String, name: String, installID: String?) -> Bool {
        guard admit(deviceID, installID: installID, name: name) else { return false }
        link.deviceID = deviceID
        attached[deviceID] = .local
        host.attach(link)
        return true
    }

    // MARK: iCloud lane

    private func startCloud() async {
        guard !devices.isEmpty || !invites.isEmpty else { return }
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
        startCloudClock()
        await cloudPushed()
    }

    /// Per device, the sequence number of the last iCloud batch read from it.
    private var cloudMarks: [String: Int64] {
        get { (defaults.dictionary(forKey: "remote.cloud.marks") as? [String: Int64]) ?? [:] }
        set { defaults.set(newValue, forKey: "remote.cloud.marks") }
    }

    private func startCloudClock() {
        guard cloudClock == nil else { return }
        cloudClock = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = self.cloudLinks.isEmpty ? self.cloudChecks.idle : self.cloudChecks.attached
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
                await self.cloudPushed()
            }
        }
    }

    private func stopCloudClock() {
        cloudClock?.cancel()
        cloudClock = nil
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
            guard accepts(id), let secret = secrets.secret(for: id) else { continue }
            channels[id] = CloudChannel(me: "mac", peer: id, secret: secret, mailbox: mailbox, after: cloudMarks[id] ?? -1)
        }
        // Mail for the Mac from a key it doesn't accept (a withdrawn invite, a removed device) is
        // never read; don't leave it in iCloud.
        let unread = fetched.filter { $0.to == "mac" && channels[$0.from] == nil }.map(\.id)
        if !unread.isEmpty { try? await mailbox.delete(unread) }
        for (id, channel) in channels {
            guard accepts(id) else {
                // An invite that expired or was withdrawn since its channel was opened.
                channels[id] = nil
                continue
            }
            // Every batch from a phone starts with its hello, so each one is checked against the
            // installation that paired: one that isn't that device's is dropped whole.
            var messages: [ClientMessage] = []
            for batch in await channel.open(fetched) {
                guard case .hello(_, let deviceID, let name, let installID)? = batch.messages.first(where: { if case .hello = $0 { true } else { false } }),
                      deviceID == id, admit(id, installID: installID, name: name) else { continue }
                await channel.accept(batch.seq)
                messages += batch.messages
            }
            // The replay mark outlives the app: a batch read before a relaunch isn't read again.
            let mark = await channel.delivered
            if mark > (cloudMarks[id] ?? -1) { cloudMarks[id] = mark }
            guard !messages.isEmpty else { continue }
            let link = cloudLinks[id] ?? attachCloud(id, channel: channel)
            link.heard()
            for message in messages { link.onReceive?(message) }
        }
    }

    private func attachCloud(_ id: String, channel: CloudChannel<HostMessage, ClientMessage>) -> CloudLink {
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
    fileprivate(set) var deviceID: String?
    private let connection: FramedConnection<ClientMessage>
    private var closed = false

    init(_ connection: FramedConnection<ClientMessage>) { self.connection = connection }

    func send(_ messages: [HostMessage]) { connection.send(messages) }

    func deliver(_ message: ClientMessage, service: RemoteService) {
        guard !closed else { return }
        if deviceID == nil {
            // The TLS handshake proved a key; the hello must name the device that key belongs
            // to (the identity the handshake used, not just any the Mac knows). Anything else
            // first, or a hello the Mac refuses, ends the connection.
            guard case .hello(_, let identity, let name, let installID) = message,
                  let used = connection.pskIdentity, identity == used,
                  service.localHello(self, deviceID: identity, name: name, installID: installID) else { return close() }
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
