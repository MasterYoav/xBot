import CloudKit
import CryptoKit
import Foundation

/// One posting in the iCloud mailbox: some frames from one side to the other, sealed with the
/// pairing key (AES-GCM), so iCloud only ever holds ciphertext.
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

    public init(me: String, peer: String, secret: Data, mailbox: any CloudMailbox) {
        self.me = me
        self.peer = peer
        self.key = SymmetricKey(data: secret)
        self.mailbox = mailbox
        // Rising across relaunches without storing a counter.
        self.seq = Int64(Date.now.timeIntervalSince1970 * 1000)
    }

    public func onMessages(_ handler: @escaping @Sendable ([Incoming]) -> Void) { self.handler = handler }

    public func send(_ messages: [Outgoing]) async throws {
        guard !messages.isEmpty else { return }
        let body = try Wire.encoder.encode(messages)
        let sealed = try AES.GCM.seal(body, using: key).combined ?? Data()
        seq += 1
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
        let batches = fetched
            .filter { $0.to == me && $0.from == peer && !seen.contains($0.id) }
            .sorted { $0.seq < $1.seq }
        var out: [Incoming] = []
        var done: [String] = []
        for batch in batches {
            seen.insert(batch.id)
            done.append(batch.id)
            // Older than what was already delivered: a replay, dropped.
            guard batch.seq > lastSeq else { continue }
            guard let box = try? AES.GCM.SealedBox(combined: batch.sealed),
                  let body = try? AES.GCM.open(box, using: key),
                  let messages = try? Wire.decoder.decode([Incoming].self, from: body) else { continue }
            lastSeq = batch.seq
            out += messages
        }
        if !done.isEmpty { try? await mailbox.delete(done) }
        if !out.isEmpty { handler?(out) }
        return out
    }
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
