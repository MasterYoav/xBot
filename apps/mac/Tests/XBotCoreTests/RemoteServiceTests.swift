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

    func make(mailbox: (any CloudMailbox)? = nil, timeout: Duration = .seconds(150)) async -> (Workspace, RemoteService) {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await w.refreshHarnesses()
        let defaults = UserDefaults(suiteName: "remote-\(UUID().uuidString)")!
        return (w, RemoteService(workspace: w, secrets: MemorySecrets(), defaults: defaults, macName: "Test Mac",
                                 mailbox: mailbox, advertise: false, cloudTimeout: timeout))
    }

    func waitFor(_ seconds: Double = 5, _ done: () -> Bool) async {
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
        phone.send([ClientMessage.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "Yoav's iPhone")])
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
        try await phone.send([.hello(version: Wire.version, deviceID: invite.key.identity, deviceName: "Yoav's iPhone"), .away])
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
}
