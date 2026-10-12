import Foundation
import Synchronization
import Testing
@testable import XBotRemote

/// The iCloud mailbox, in memory: what both sides see, and what's left behind.
final class FakeMailbox: CloudMailbox {
    let records = Mutex<[String: CloudBatch]>([:])
    let cursors = Mutex<[ObjectIdentifier: Set<String>]>([:])
    let posts = Mutex(0)

    func post(_ batch: CloudBatch) async throws {
        posts.withLock { $0 += 1 }
        records.withLock { $0[batch.id] = batch }
    }

    func fetchNew() async throws -> [CloudBatch] { records.withLock { Array($0.values) } }

    func delete(_ ids: [String]) async throws { records.withLock { for id in ids { $0[id] = nil } } }
}

@Suite struct CloudTransportTests {
    let secret = PairingKey.generate().secret

    @Test func messagesCrossInOrderOnceEachAndAreCleanedUp() async throws {
        let box = FakeMailbox()
        let mac = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "phone", secret: secret, mailbox: box)
        let phone = CloudChannel<ClientMessage, HostMessage>(me: "phone", peer: "mac", secret: secret, mailbox: box)
        let a = UUID(), b = UUID()
        try await mac.send([.chatRemoved(a)])
        try await mac.send([.chatRemoved(b)])
        let got = try await phone.poll()
        #expect(got == [.chatRemoved(a), .chatRemoved(b)])
        #expect(try await phone.poll().isEmpty)
        // Read batches are deleted; nothing piles up in iCloud.
        #expect(box.records.withLock { $0.isEmpty })
        try await phone.send([.away])
        #expect(try await mac.poll() == [.away])
    }

    /// iCloud holds ciphertext only, and a batch sealed with another key is dropped.
    @Test func batchesAreSealedAndAWrongKeyCantOpenThem() async throws {
        let box = FakeMailbox()
        let mac = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "phone", secret: secret, mailbox: box)
        try await mac.send([.live(chatID: UUID(), parts: [.text("top secret plan")])])
        let stored = try #require(box.records.withLock { $0.values.first })
        #expect(String(decoding: stored.sealed, as: UTF8.self).contains("top secret") == false)
        let intruder = CloudChannel<ClientMessage, HostMessage>(me: "phone", peer: "mac", secret: PairingKey.generate().secret, mailbox: box)
        #expect(try await intruder.poll().isEmpty)
    }

    /// Another phone's mail, and the channel's own posts, aren't read as its own.
    @Test func onlyMailForThisPairIsRead() async throws {
        let box = FakeMailbox()
        let toPhone1 = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "phone1", secret: secret, mailbox: box)
        let phone2 = CloudChannel<ClientMessage, HostMessage>(me: "phone2", peer: "mac", secret: secret, mailbox: box)
        try await toPhone1.send([.chatRemoved(UUID())])
        #expect(try await phone2.poll().isEmpty)
        #expect(try await toPhone1.poll().isEmpty)
        #expect(box.records.withLock { $0.count } == 1)
    }

    @Test func aReplayedOldBatchIsDropped() async throws {
        let box = FakeMailbox()
        let mac = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "phone", secret: secret, mailbox: box)
        let phone = CloudChannel<ClientMessage, HostMessage>(me: "phone", peer: "mac", secret: secret, mailbox: box)
        try await mac.send([.chatRemoved(UUID())])
        let old = try #require(box.records.withLock { $0.values.first })
        _ = try await phone.poll()
        // The same ciphertext posted again under a new id.
        try await box.post(CloudBatch(from: "mac", to: "phone", seq: old.seq, sealed: old.sealed))
        #expect(try await phone.poll().isEmpty)
    }

    /// The sender, recipient and sequence number are sealed with the batch: the same ciphertext
    /// under a higher number is refused, even though it's newer than anything delivered.
    @Test func aRenumberedBatchIsRefused() async throws {
        let box = FakeMailbox()
        let mac = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "phone", secret: secret, mailbox: box)
        let phone = CloudChannel<ClientMessage, HostMessage>(me: "phone", peer: "mac", secret: secret, mailbox: box)
        try await mac.send([.chatRemoved(UUID())])
        let old = try #require(box.records.withLock { $0.values.first })
        #expect(try await phone.poll().count == 1)
        try await box.post(CloudBatch(from: "mac", to: "phone", seq: old.seq + 1_000, sealed: old.sealed))
        #expect(try await phone.poll().isEmpty)
    }

    /// A phone's own batch posted back to it as if from the Mac is refused.
    @Test func aReflectedBatchIsRefused() async throws {
        let box = FakeMailbox()
        let phone = CloudChannel<ClientMessage, ClientMessage>(me: "phone", peer: "mac", secret: secret, mailbox: box)
        try await phone.send([.away])
        let mine = try #require(box.records.withLock { $0.values.first })
        box.records.withLock { $0 = [:] }
        try await box.post(CloudBatch(from: "mac", to: "phone", seq: mine.seq, sealed: mine.sealed))
        #expect(try await phone.poll().isEmpty)
    }

    /// The replay mark outlives the channel: a channel started where the last one left off (a
    /// relaunch) refuses a batch the last one already read.
    @Test func aReplayAfterARestartIsRefused() async throws {
        let box = FakeMailbox()
        let mac = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "phone", secret: secret, mailbox: box)
        let before = CloudChannel<ClientMessage, HostMessage>(me: "phone", peer: "mac", secret: secret, mailbox: box)
        try await mac.send([.chatRemoved(UUID())])
        let old = try #require(box.records.withLock { $0.values.first })
        #expect(try await before.poll().count == 1)
        let mark = await before.delivered
        #expect(mark == old.seq)

        let after = CloudChannel<ClientMessage, HostMessage>(me: "phone", peer: "mac", secret: secret, mailbox: box, after: mark)
        try await box.post(CloudBatch(from: "mac", to: "phone", seq: old.seq, sealed: old.sealed))
        #expect(try await after.poll().isEmpty)
        try await mac.send([.chatRemoved(UUID())])
        #expect(try await after.poll().count == 1)
    }

    /// The Mac fetches once per push and every phone's channel takes its own batches from it.
    @Test func oneFetchServesEveryChannel() async throws {
        let box = FakeMailbox()
        let p1 = CloudChannel<ClientMessage, HostMessage>(me: "p1", peer: "mac", secret: secret, mailbox: box)
        let p2 = CloudChannel<ClientMessage, HostMessage>(me: "p2", peer: "mac", secret: secret, mailbox: box)
        let mac1 = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "p1", secret: secret, mailbox: box)
        let mac2 = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "p2", secret: secret, mailbox: box)
        try await p1.send([.hello(version: 1, deviceID: "dev", deviceName: "one")])
        try await p2.send([.hello(version: 1, deviceID: "dev", deviceName: "two")])
        let fetched = try await box.fetchNew()
        #expect(await mac1.receive(fetched) == [.hello(version: 1, deviceID: "dev", deviceName: "one")])
        #expect(await mac2.receive(fetched) == [.hello(version: 1, deviceID: "dev", deviceName: "two")])
    }

    @Test func nothingToSendPostsNothing() async throws {
        let box = FakeMailbox()
        let mac = CloudChannel<HostMessage, ClientMessage>(me: "mac", peer: "phone", secret: secret, mailbox: box)
        try await mac.send([])
        #expect(box.posts.withLock { $0 } == 0)
    }
}
