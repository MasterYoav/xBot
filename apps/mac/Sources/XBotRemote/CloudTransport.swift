import CloudKit
import CryptoKit
import Foundation

/// One posting in the iCloud mailbox: some frames from one side to the other, sealed with the
/// pairing key (AES-GCM), so iCloud only ever holds ciphertext. The sender, recipient and sequence
/// number travel in the clear (they're how the record is found) but are sealed in as
/// authenticated data, so a batch can't be re-addressed or renumbered (`authenticated`).
public struct CloudBatch: Equatable, Sendable, Identifiable {
    public var id: String
    public var from: String
    public var to: String
    public var seq: Int64
    public var sealed: Data
    public var createdAt: Date

    public init(id: String = UUID().uuidString, from: String, to: String, seq: Int64, sealed: Data, createdAt: Date = .now) {
        self.id = id; self.from = from; self.to = to; self.seq = seq; self.sealed = sealed; self.createdAt = createdAt
    }

    /// What the seal covers besides the frames.
    static func authenticated(from: String, to: String, seq: Int64) -> Data {
        (try? JSONEncoder().encode(["xbot.remote.batch", from, to, String(seq)])) ?? Data()
    }
}

/// Where batches are kept: the private CloudKit database in the app, a dictionary in tests.
public protocol CloudMailbox: Sendable {
    func post(_ batch: CloudBatch) async throws
    /// Batches posted since the last call (the first call: everything still there).
    func fetchNew() async throws -> [CloudBatch]
    func delete(_ ids: [String]) async throws
}

/// The iCloud lane between the Mac and one phone. Sends seal and post; on a push (or `poll`), new
/// batches addressed to this side are opened in order, once each, and deleted. Nothing runs between
/// pushes.
public actor CloudChannel<Outgoing: Encodable & Sendable, Incoming: Decodable & Sendable> {
    public let me: String
    public let peer: String
    private let key: SymmetricKey
    private let mailbox: any CloudMailbox
    private var seq: Int64
    private var seen: Set<String> = []
    private var lastSeq: Int64 = -1
    private var handler: (@Sendable ([Incoming]) -> Void)?

    /// The sequence number of the last batch delivered: save it, and hand it back as `after`
    /// when the channel is made again, so a batch read before isn't read again.
    public var delivered: Int64 { lastSeq }

    public init(me: String, peer: String, secret: Data, mailbox: any CloudMailbox, after delivered: Int64 = -1) {
        self.me = me
        self.peer = peer
        self.key = SymmetricKey(data: secret)
        self.mailbox = mailbox
        self.lastSeq = delivered
        // Rising across relaunches without storing a counter.
        self.seq = Int64(Date.now.timeIntervalSince1970 * 1000)
    }

    public func onMessages(_ handler: @escaping @Sendable ([Incoming]) -> Void) { self.handler = handler }

    public func send(_ messages: [Outgoing]) async throws {
        guard !messages.isEmpty else { return }
        let body = try Wire.encoder.encode(messages)
        seq += 1
        let sealed = try AES.GCM.seal(body, using: key, authenticating: CloudBatch.authenticated(from: me, to: peer, seq: seq)).combined ?? Data()
        try await mailbox.post(CloudBatch(from: me, to: peer, seq: seq, sealed: sealed))
    }

    /// Fetches and reads what arrived: for a side with one channel (the phone).
    @discardableResult
    public func poll() async throws -> [Incoming] {
        await receive(try await mailbox.fetchNew())
    }

    /// Reads this channel's batches out of a fetch. On the Mac one fetch per push is handed to
    /// every phone's channel (a change token can only be read once).
    @discardableResult
    public func receive(_ fetched: [CloudBatch]) async -> [Incoming] {
        var out: [Incoming] = []
        for batch in await open(fetched) {
            accept(batch.seq)
            out += batch.messages
        }
        if !out.isEmpty { handler?(out) }
        return out
    }

    /// One batch, opened.
    public struct Opened: Sendable {
        public var seq: Int64
        public var messages: [Incoming]
    }

    /// This channel's new batches in a fetch, opened, in order, each once (and deleted from the
    /// mailbox), without delivering them: the caller decides which to take and `accept`s those.
    /// Only an accepted batch moves the replay mark, so a batch that's refused can't push it
    /// ahead and lock out the real sender.
    public func open(_ fetched: [CloudBatch]) async -> [Opened] {
        let batches = fetched
            .filter { $0.to == me && $0.from == peer && !seen.contains($0.id) }
            .sorted { $0.seq < $1.seq }
        var out: [Opened] = []
        var done: [String] = []
        for batch in batches {
            seen.insert(batch.id)
            done.append(batch.id)
            // Older than what was already delivered: a replay, dropped.
            guard batch.seq > lastSeq, batch.seq > (out.last?.seq ?? .min) else { continue }
            guard let box = try? AES.GCM.SealedBox(combined: batch.sealed),
                  let body = try? AES.GCM.open(box, using: key, authenticating: CloudBatch.authenticated(from: batch.from, to: batch.to, seq: batch.seq)),
                  let messages = try? Wire.decoder.decode([Incoming].self, from: body) else { continue }
            out.append(Opened(seq: batch.seq, messages: messages))
        }
        if !done.isEmpty { try? await mailbox.delete(done) }
        return out
    }

    /// Takes an opened batch: nothing at or below its sequence number is read again.
    public func accept(_ seq: Int64) { lastSeq = max(lastSeq, seq) }
}

/// The real mailbox: a zone in the private CloudKit database, read with zone changes and a
/// silent-push subscription. Container `iCloud.dev.xbot`.
public final class CloudKitMailbox: CloudMailbox, @unchecked Sendable {
    public static let containerID = "iCloud.dev.xbot"
    static let zone = CKRecordZone.ID(zoneName: "XBotRemote", ownerName: CKCurrentUserDefaultName)
    static let recordType = "Batch"

    private let database: CKDatabase
    private let tokenKey: String
    private let lock = NSLock()
    private var token: CKServerChangeToken?
    private var ready = false

    /// `side`: "mac" or the device id, so each side keeps its own change token.
    public init(side: String, container: CKContainer = CKContainer(identifier: CloudKitMailbox.containerID)) {
        database = container.privateCloudDatabase
        tokenKey = "remote.cloud.token.\(side)"
        if let data = UserDefaults.standard.data(forKey: tokenKey) {
            token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
    }

    /// Makes the zone and the push subscription once.
    public func prepare(subscriptionID: String) async throws {
        if lock.withLock({ ready }) { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zone)], deleting: [])
        let subscription = CKRecordZoneSubscription(zoneID: Self.zone, subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        lock.withLock { ready = true }
    }

    public func post(_ batch: CloudBatch) async throws {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: batch.id, zoneID: Self.zone))
        record["from"] = batch.from
        record["to"] = batch.to
        record["seq"] = batch.seq
        record["sealed"] = batch.sealed
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    public func fetchNew() async throws -> [CloudBatch] {
        var since = lock.withLock { token }
        var out: [CloudBatch] = []
        while true {
            let changes = try await database.recordZoneChanges(inZoneWith: Self.zone, since: since)
            for (_, result) in changes.modificationResultsByID {
                guard let record = try? result.get().record,
                      let from = record["from"] as? String, let to = record["to"] as? String,
                      let seq = record["seq"] as? Int64, let sealed = record["sealed"] as? Data else { continue }
                out.append(CloudBatch(id: record.recordID.recordName, from: from, to: to, seq: seq, sealed: sealed,
                                      createdAt: record.creationDate ?? .now))
            }
            since = changes.changeToken
            if !changes.moreComing { break }
        }
        lock.withLock { token = since }
        if let since, let data = try? NSKeyedArchiver.archivedData(withRootObject: since, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: tokenKey)
        }
        return out
    }

    public func delete(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await database.modifyRecords(saving: [], deleting: ids.map { CKRecord.ID(recordName: $0, zoneID: Self.zone) })
    }
}
