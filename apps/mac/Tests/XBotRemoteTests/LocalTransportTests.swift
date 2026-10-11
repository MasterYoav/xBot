import Foundation
import Network
import Testing
@testable import XBotRemote

@MainActor @Suite(.serialized) struct LocalTransportTests {
    func waitFor(_ seconds: Double = 5, _ done: () -> Bool) async {
        let end = Date.now.addingTimeInterval(seconds)
        while !done(), Date.now < end { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// A phone with the paired key reaches the Mac over TLS and both sides exchange frames.
    @Test func aPairedPhoneConnectsAndTalks() async throws {
        let key = PairingKey.generate()
        let listener = LocalListener()
        var port: UInt16?
        var macGot: [ClientMessage] = []
        var macSide: FramedConnection<ClientMessage>?
        listener.onReady = { port = $0 }
        listener.onConnection = { connection in
            macSide = connection
            connection.onMessages = { macGot += $0; connection.send([HostMessage.chatRemoved(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)]) }
            connection.start()
        }
        try listener.start(keys: [PairingKey.generate(), key], macID: UUID(), macName: "Test Mac", advertise: false)
        await waitFor { port != nil }
        let phone = FramedConnection<HostMessage>(to: .hostPort(host: "127.0.0.1", port: .init(rawValue: try #require(port))!), key: key)
        var phoneGot: [HostMessage] = []
        var ready = false
        phone.onState = { if case .ready = $0 { ready = true } }
        phone.onMessages = { phoneGot += $0 }
        phone.start()
        await waitFor { ready }
        #expect(ready)
        phone.send([ClientMessage.hello(version: 1, deviceID: "dev", deviceName: "Test iPhone")])
        await waitFor { !phoneGot.isEmpty }
        #expect(macGot == [.hello(version: 1, deviceID: "dev", deviceName: "Test iPhone")])
        #expect(phoneGot.count == 1)
        phone.cancel(); macSide?.cancel(); listener.stop()
    }

    /// A key the Mac doesn't have can't complete the handshake.
    @Test func aWrongKeyIsRefused() async throws {
        let listener = LocalListener()
        var port: UInt16?
        var accepted = false
        listener.onReady = { port = $0 }
        listener.onConnection = { connection in
            connection.onState = { if case .ready = $0 { accepted = true } }
            connection.start()
        }
        try listener.start(keys: [PairingKey.generate()], macID: UUID(), macName: "Test Mac", advertise: false)
        await waitFor { port != nil }
        let phone = FramedConnection<HostMessage>(to: .hostPort(host: "127.0.0.1", port: .init(rawValue: try #require(port))!),
                                                 key: PairingKey.generate())
        var closed = false, ready = false
        phone.onState = { state in if case .closed = state { closed = true } else { ready = true } }
        phone.start()
        await waitFor { closed || ready }
        #expect(closed && !ready && !accepted)
        listener.stop()
    }

    @Test func anInviteSurvivesItsQRCode() throws {
        let invite = PairingInvite(macID: UUID(), macName: "Yoav's Mac mini", key: .generate(), host: "192.168.1.5", port: 51234)
        #expect(PairingInvite(url: invite.url) == invite)
        #expect(invite.url.absoluteString.hasPrefix("xbot://pair?v="))
        #expect(PairingInvite(url: URL(string: "xbot://pair?v=garbage")!) == nil)
        #expect(PairingKey.generate().secret.count == 32 && PairingKey.generate() != PairingKey.generate())
    }
}
