import Foundation
import Network
import Synchronization
import Testing
import XBotBrain
import XBotRemote
@testable import XBotCore

final class MemorySecrets: PairingSecrets {
    let store = Mutex<[String: Data]>([:])
    func secret(for id: String) -> Data? { store.withLock { $0[id] } }
    func save(_ secret: Data, for id: String) { store.withLock { $0[id] = secret } }
    func remove(_ id: String) { store.withLock { $0[id] = nil } }
}

final class MemoryMailbox: CloudMailbox {
    let records = Mutex<[String: CloudBatch]>([:])
    func post(_ batch: CloudBatch) async throws { records.withLock { $0[batch.id] = batch } }
    func fetchNew() async throws -> [CloudBatch] { records.withLock { Array($0.values) } }
    func delete(_ ids: [String]) async throws { records.withLock { for id in ids { $0[id] = nil } } }
}

@MainActor @Suite(.serialized) struct RemoteServiceTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    func make(mailbox: (any CloudMailbox)? = nil, timeout: Duration = .seconds(150),
              checks: RemoteService.CloudChecks = .init(attached: .seconds(60), idle: .seconds(60)),
              secrets: MemorySecrets = MemorySecrets(), defaults: UserDefaults? = nil,
              inviteLifetime: Duration = .seconds(600)) async -> (Workspace, RemoteService) {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await w.refreshHarnesses()
        let defaults = defaults ?? UserDefaults(suiteName: "remote-\(UUID().uuidString)")!
        return (w, RemoteService(workspace: w, secrets: secrets, defaults: defaults, macName: "Test Mac",
                                 mailbox: mailbox, advertise: false, cloudTimeout: timeout, cloudChecks: checks,
                                 inviteLifetime: inviteLifetime))
    }

    /// A phone away from home holding `key`, saying hello through iCloud from installation `install`.
    func cloudPhone(_ key: PairingKey, box: any CloudMailbox, install: String = "install-1",
                    name: String = "Yoav's iPhone") async throws -> CloudChannel<ClientMessage, HostMessage> {
        let phone = CloudChannel<ClientMessage, HostMessage>(me: key.identity, peer: "mac", secret: key.secret, mailbox: box)
        try await phone.send([.hello(version: Wire.version, deviceID: key.identity, deviceName: name, installID: install), .away])
        return phone
    }

    /// Connects to the Mac's listener with `key`; true once the TLS handshake completes, false if refused.
    func handshake(port: UInt16, key: PairingKey) async -> (FramedConnection<HostMessage>, Bool) {
        let phone = FramedConnection<HostMessage>(to: .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!), key: key)
        var refused = false, joined = false
        phone.onState = { (state: FramedConnection<HostMessage>.State) in if case .closed = state { refused = true } else { joined = true } }
        phone.start()
        await waitFor { refused || joined }
        return (phone, joined && !refused)
    }

    func waitFor(_ seconds: Double = 20, _ done: () -> Bool) async {
        let end = Date.now.addingTimeInterval(seconds)
        while !done(), Date.now < end { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// Nothing paired: nothing listens.
    @Test func offUntilTheFirstPairing() async {
        let (_, service) = await make()
        service.start()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(service.port == nil && service.devices.isEmpty)
    }

    /// Scan the code, connect, say hello: the phone is listed, attached, and gets the workspace.
    /// Removed, it can't connect again.
    @Test func pairConnectAndRemove() async throws {
        let (w, service) = await make()
        _ = w.newChat(in: nil)
        let invite = service.invite()
        await waitFor { service.port != nil }
        let port = try #require(service.port)
        let phone = FramedConnection<HostMessage>(to: .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!), key: invite.key)
        var got: [HostMessage] = []
        var ready = false
        phone.onState = { if case .ready = $0 { ready = true } }
        phone.onMessages = { got += $0 }
        phone.start()
        await waitFor { ready }
        phone.send([ClientMessage.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "Yoav's iPhone", installID: "install-1")])
        await waitFor { got.count >= 2 }
        #expect(service.devices.map(\.name) == ["Yoav's iPhone"])
        #expect(service.attached[invite.key.identity] == .local)
        guard case .workspace(_, let chats, _) = got.dropFirst().first else { Issue.record("no workspace"); return }
        #expect(chats.count == 1)

        service.remove(invite.key.identity)
        #expect(service.devices.isEmpty)
        let again = FramedConnection<HostMessage>(to: .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!), key: invite.key)
        var refused = false, joined = false
        again.onState = { if case .closed = $0 { refused = true } else { joined = true } }
        again.start()
        await waitFor { refused || joined }
        #expect(refused && !joined)
        phone.cancel()
    }

    /// Away from home: the phone writes to iCloud, the Mac answers there, and lets it go once it
    /// stops writing.
    @Test func aPhoneAwayIsServedThroughICloudThenLetGo() async throws {
        let box = MemoryMailbox()
        let (_, service) = await make(mailbox: box, timeout: .milliseconds(300))
        let invite = service.invite()
        let phone = CloudChannel<ClientMessage, HostMessage>(me: invite.key.identity, peer: "mac", secret: invite.key.secret, mailbox: box)
        try await phone.send([.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "Yoav's iPhone", installID: "install-1"), .away])
        await service.cloudPushed()
        #expect(service.attached[invite.key.identity] == .cloud)
        try? await Task.sleep(for: .milliseconds(100))
        let got = try await phone.poll()
        #expect(got.contains { if case .hello = $0 { true } else { false } })
        #expect(got.contains { if case .workspace = $0 { true } else { false } })
        try? await Task.sleep(for: .milliseconds(500))
        #expect(service.attached[invite.key.identity] == nil)
        #expect(service.host.attachedCount == 0)
    }

    /// iCloud mail from a device that was never paired is ignored.
    @Test func anUnpairedDevicesMailIsIgnored() async throws {
        let box = MemoryMailbox()
        let (_, service) = await make(mailbox: box)
        _ = service.invite()
        let stranger = PairingKey.generate()
        let phone = CloudChannel<ClientMessage, HostMessage>(me: stranger.identity, peer: "mac", secret: stranger.secret, mailbox: box)
        try await phone.send([.hello(version: 1, deviceID: stranger.identity, deviceName: "Stranger")])
        await service.cloudPushed()
        #expect(service.attached.isEmpty && service.devices.isEmpty)
    }

    /// Pushes don't always come: with no push at all, the Mac still finds a phone that went away
    /// (the slow check) and then answers it quickly (the fast one).
    @Test func iCloudWorksWithoutPushes() async throws {
        let box = MemoryMailbox()
        let (_, service) = await make(mailbox: box, checks: .init(attached: .milliseconds(50), idle: .milliseconds(200)))
        let invite = service.invite()
        let phone = CloudChannel<ClientMessage, HostMessage>(me: invite.key.identity, peer: "mac", secret: invite.key.secret, mailbox: box)
        try await phone.send([.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "Yoav's iPhone", installID: "install-1"), .away])
        await waitFor(3) { service.attached[invite.key.identity] == .cloud }
        #expect(service.attached[invite.key.identity] == .cloud)
        _ = try await phone.poll()

        // A request, answered without a push.
        let request = UUID()
        // Every batch from a phone starts with its hello.
        try await phone.send([.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "Yoav's iPhone", installID: "install-1"),
                              .stop(requestID: request, chatID: UUID())])
        var replies: [HostMessage] = []
        let end = Date.now.addingTimeInterval(2)
        while Date.now < end, !replies.contains(where: { if case .reply(request, _, _, _) = $0 { true } else { false } }) {
            replies += try await phone.poll()
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(replies.contains { if case .reply(request, _, _, _) = $0 { true } else { false } })
        service.remove(invite.key.identity)
    }

    // MARK: Invites

    /// The sheet closed before anyone scanned it: the key is gone from the Keychain and neither lane
    /// takes it.
    @Test func aClosedInviteIsWithdrawnFromBothLanes() async throws {
        let box = MemoryMailbox(), secrets = MemorySecrets()
        let (_, service) = await make(mailbox: box, secrets: secrets)
        let invite = service.invite()
        await waitFor { service.port != nil }
        let port = try #require(service.port)
        service.withdraw(invite)
        #expect(secrets.secret(for: invite.key.identity) == nil)
        _ = try await cloudPhone(invite.key, box: box)
        await service.cloudPushed()
        #expect(service.attached.isEmpty && service.devices.isEmpty)
        let (phone, joined) = await handshake(port: port, key: invite.key)
        #expect(!joined)
        phone.cancel()
    }

    /// A code left on screen stops working on its own.
    @Test func anUnusedInviteExpires() async throws {
        let box = MemoryMailbox(), secrets = MemorySecrets()
        let (_, service) = await make(mailbox: box, secrets: secrets, inviteLifetime: .milliseconds(300))
        let invite = service.invite()
        await waitFor(5) { secrets.secret(for: invite.key.identity) == nil }
        #expect(secrets.secret(for: invite.key.identity) == nil)
        _ = try await cloudPhone(invite.key, box: box)
        await service.cloudPushed()
        #expect(service.attached.isEmpty && service.devices.isEmpty)
    }

    /// xBot quit with a code on screen: at the next launch that code is gone; paired devices stay.
    @Test func unusedInvitesAreRemovedAtRelaunch() async throws {
        let box = MemoryMailbox(), secrets = MemorySecrets()
        let defaults = UserDefaults(suiteName: "remote-\(UUID().uuidString)")!
        let (_, first) = await make(mailbox: box, secrets: secrets, defaults: defaults)
        let used = first.invite()
        _ = try await cloudPhone(used.key, box: box)
        await first.cloudPushed()
        #expect(first.devices.map(\.id) == [used.key.identity])
        let unused = first.invite()

        let (_, second) = await make(mailbox: MemoryMailbox(), secrets: secrets, defaults: defaults)
        #expect(secrets.secret(for: unused.key.identity) == nil)
        #expect(secrets.secret(for: used.key.identity) != nil)
        #expect(second.devices.map(\.id) == [used.key.identity])
    }

    /// A key left in the Keychain by something else (an older build's invite) opens nothing: only
    /// paired devices and live invites are accepted.
    @Test func aKeyThatIsNeitherPairedNorInvitedIsRefused() async throws {
        let box = MemoryMailbox(), secrets = MemorySecrets()
        let (_, service) = await make(mailbox: box, secrets: secrets)
        _ = service.invite()
        let leftover = PairingKey.generate()
        secrets.save(leftover.secret, for: leftover.identity)
        _ = try await cloudPhone(leftover, box: box)
        await service.cloudPushed()
        #expect(service.attached.isEmpty && service.devices.isEmpty)
    }

    // MARK: Replays

    /// A batch the Mac already read, posted again after xBot relaunched, isn't served.
    @Test func aReplayedBatchIsRefusedAfterARelaunch() async throws {
        let box = MemoryMailbox(), secrets = MemorySecrets()
        let defaults = UserDefaults(suiteName: "remote-\(UUID().uuidString)")!
        let (_, first) = await make(mailbox: box, secrets: secrets, defaults: defaults)
        let invite = first.invite()
        _ = try await cloudPhone(invite.key, box: box)
        let recorded = try #require(box.records.withLock { $0.values.first })
        await first.cloudPushed()
        #expect(first.attached[invite.key.identity] == .cloud)

        let (_, second) = await make(mailbox: box, secrets: secrets, defaults: defaults)
        box.records.withLock { $0 = [:] }
        try await box.post(CloudBatch(from: recorded.from, to: recorded.to, seq: recorded.seq, sealed: recorded.sealed))
        await second.cloudPushed()
        #expect(second.attached.isEmpty)
        #expect(box.records.withLock { $0.values.contains { $0.to == invite.key.identity } } == false)
    }

    // MARK: The hello and the handshake

    /// Nearby, a phone can only be the device whose key its TLS handshake used: one holding key A
    /// that says hello as B (another device, or a live invite) is turned away.
    @Test func aHelloMustNameTheKeyItsConnectionUsed() async throws {
        let (_, service) = await make()
        let mine = service.invite()
        let theirs = service.invite()
        await waitFor { service.port != nil }
        let port = try #require(service.port)
        let phone = FramedConnection<HostMessage>(to: .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!), key: mine.key)
        var got: [HostMessage] = []
        var ready = false, closed = false
        phone.onState = { (state: FramedConnection<HostMessage>.State) in
            switch state { case .ready: ready = true; case .closed: closed = true }
        }
        phone.onMessages = { (messages: [HostMessage]) in got += messages }
        phone.start()
        await waitFor { ready || closed }
        #expect(ready)
        phone.send([ClientMessage.hello(version: Wire.version, deviceID: theirs.key.identity, deviceName: "Impostor", installID: "install-1")])
        await waitFor(5) { closed }
        #expect(closed)
        #expect(got.isEmpty)
        #expect(service.devices.isEmpty && service.attached.isEmpty)
        #expect(service.isLive(theirs))
        phone.cancel()
    }

    // MARK: One code, one device

    /// Two phones scanned the same code; the first to use it is the one paired. Through iCloud the
    /// second's batches, with its own hello or none, are not served.
    @Test func anInvitePairsOneDeviceThroughICloud() async throws {
        let box = MemoryMailbox()
        let (_, service) = await make(mailbox: box)
        let invite = service.invite()
        let first = try await cloudPhone(invite.key, box: box, install: "first", name: "First iPhone")
        await service.cloudPushed()
        #expect(service.devices.map(\.name) == ["First iPhone"])
        _ = try await first.poll()

        let second = CloudChannel<ClientMessage, HostMessage>(me: invite.key.identity, peer: "mac", secret: invite.key.secret, mailbox: box)
        let withHello = UUID(), without = UUID()
        try await second.send([.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "Second iPhone", installID: "second"),
                               .stop(requestID: withHello, chatID: UUID())])
        try await second.send([.stop(requestID: without, chatID: UUID())])
        await service.cloudPushed()
        try? await Task.sleep(for: .milliseconds(300))
        let replies = try await second.poll()
        #expect(!replies.contains { if case .reply(withHello, _, _, _) = $0 { true } else { false } })
        #expect(!replies.contains { if case .reply(without, _, _, _) = $0 { true } else { false } })
        #expect(service.devices.map(\.name) == ["First iPhone"])

        // The first phone is still served.
        let mine = UUID()
        try await first.send([.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "First iPhone", installID: "first"),
                              .stop(requestID: mine, chatID: UUID())])
        await service.cloudPushed()
        var got: [HostMessage] = []
        let end = Date.now.addingTimeInterval(5)
        while Date.now < end, !got.contains(where: { if case .reply(mine, _, _, _) = $0 { true } else { false } }) {
            got += try await first.poll()
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(got.contains { if case .reply(mine, _, _, _) = $0 { true } else { false } })
    }

    /// The same on the local network: a second phone with the first one's code is turned away.
    @Test func anInvitePairsOneDeviceNearby() async throws {
        let (_, service) = await make()
        let invite = service.invite()
        await waitFor { service.port != nil }
        let port = try #require(service.port)
        let (first, firstJoined) = await handshake(port: port, key: invite.key)
        #expect(firstJoined)
        first.send([ClientMessage.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "First iPhone", installID: "first")])
        await waitFor { service.attached[invite.key.identity] == .local }
        #expect(service.devices.map(\.name) == ["First iPhone"])

        let second = FramedConnection<HostMessage>(to: .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!), key: invite.key)
        var got: [HostMessage] = []
        var ready = false, closed = false
        second.onState = { (state: FramedConnection<HostMessage>.State) in
            switch state { case .ready: ready = true; case .closed: closed = true }
        }
        second.onMessages = { (messages: [HostMessage]) in got += messages }
        second.start()
        await waitFor { ready || closed }
        second.send([ClientMessage.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "Second iPhone", installID: "second")])
        await waitFor(5) { closed }
        #expect(closed)
        #expect(got.isEmpty)
        #expect(service.devices.map(\.name) == ["First iPhone"])
        first.cancel(); second.cancel()
    }
}
