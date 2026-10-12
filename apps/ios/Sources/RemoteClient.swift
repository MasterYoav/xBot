import CloudKit
import Foundation
import Network
import Observation
import Security
import UIKit
import XBotRemote

/// The phone's mirror of the Mac's workspace, and the way to act on it. Connects directly when the
/// Mac is on the same network (Bonjour, or the address in the pairing code), through iCloud when
/// it isn't, and switches by itself. Nothing runs while the app is in the background.
@MainActor @Observable
final class RemoteClient {
    enum Link: Equatable {
        case unpaired
        case searching
        case local
        case cloud
        case unreachable(String)
    }

    struct Answer: Sendable { var ok: Bool; var reason: String?; var chatID: UUID?; var payload: HostMessage? = nil }

    private(set) var link: Link = .unpaired
    private(set) var macName: String?
    private(set) var projects: [RemoteProject] = []
    private(set) var chats: [RemoteChat] = []
    private(set) var agents: [RemoteAgent] = []
    private(set) var transcripts: [UUID: [RemoteMessage]] = [:]
    private(set) var live: [UUID: [RemotePart]] = [:]
    /// Shown once: a refused request's reason.
    var notice: String?

    private(set) var pairing: PairingInvite?
    @ObservationIgnored private var opened: Set<UUID> = []
    @ObservationIgnored private var local: FramedConnection<HostMessage>?
    @ObservationIgnored private let browser = LocalBrowser()
    @ObservationIgnored private var cloud: CloudChannel<ClientMessage, HostMessage>?
    @ObservationIgnored private var cloudTimer: Task<Void, Never>?
    @ObservationIgnored private var fallback: Task<Void, Never>?
    @ObservationIgnored private var pending: [UUID: CheckedContinuation<Answer, Never>] = [:]
    @ObservationIgnored private var running = false
    @ObservationIgnored private var lastEndpoint: NWEndpoint?

    init() {
        pairing = PairingStore.load()
        link = pairing == nil ? .unpaired : .searching
        if let cached = Cache.load() { projects = cached.projects; chats = cached.chats; agents = cached.agents; macName = cached.macName }
    }

    var deviceName: String { UIDevice.current.name }

    // MARK: Pairing

    func pair(with invite: PairingInvite) {
        PairingStore.save(invite)
        pairing = invite
        macName = invite.macName
        projects = []; chats = []; transcripts = [:]; live = [:]
        stop()
        start()
    }

    func unpair() {
        stop()
        PairingStore.clear()
        Cache.clear()
        pairing = nil
        macName = nil
        projects = []; chats = []; agents = []; transcripts = [:]; live = [:]
        link = .unpaired
    }

    // MARK: Lifecycle

    /// The app came to the front: find the Mac.
    func start() {
        guard let pairing, !running else { return }
        running = true
        link = .searching
        browser.onFound = { [weak self] endpoint in
            guard let self, let endpoint, self.local == nil else { return }
            self.connect(to: endpoint)
        }
        browser.start(macID: pairing.macID)
        if let host = pairing.host, let port = pairing.port, let nwPort = NWEndpoint.Port(rawValue: port) {
            connect(to: .hostPort(host: .init(host), port: nwPort))
        }
        // Not found nearby in a few seconds: away from home, use iCloud.
        fallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.local == nil else { return }
            await self.startCloud()
        }
    }

    /// The app went to the background: let go of everything.
    func stop() {
        running = false
        fallback?.cancel()
        browser.stop()
        local?.cancel()
        local = nil
        stopCloud()
        for (_, waiter) in pending { waiter.resume(returning: Answer(ok: false, reason: String(localized: "Disconnected."), chatID: nil)) }
        pending = [:]
        if pairing != nil { link = .searching }
    }

    // MARK: Local

    private func connect(to endpoint: NWEndpoint) {
        guard let pairing, local == nil else { return }
        let connection = FramedConnection<HostMessage>(to: endpoint, key: pairing.key)
        local = connection
        connection.onState = { [weak self, weak connection] state in
            guard let self, let connection, self.local === connection else { return }
            switch state {
            case .ready:
                self.fallback?.cancel()
                self.stopCloud()
                self.link = .local
                self.lastEndpoint = endpoint
                connection.send([ClientMessage.hello(version: Wire.version, deviceID: pairing.key.identity, deviceName: self.deviceName)])
                connection.send(self.opened.map { ClientMessage.open(chatID: $0) })
            case .closed(let reason):
                self.local = nil
                guard self.running else { return }
                if self.link == .local { self.link = .searching }
                // Try iCloud while Bonjour looks again.
                Task { await self.startCloud() }
                if reason != nil, self.link != .cloud { self.link = .searching }
            }
        }
        connection.onMessages = { [weak self] messages in for m in messages { self?.receive(m) } }
        connection.start()
    }

    // MARK: iCloud

    private func startCloud() async {
        guard running, cloud == nil, local == nil, let pairing else { return }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            link = .unreachable(String(localized: "Your Mac isn't on this network, and iCloud is off on this device."))
            return
        }
        let mailbox = CloudKitMailbox(side: pairing.key.identity)
        do {
            try await mailbox.prepare(subscriptionID: "xbot-remote-\(pairing.key.identity)")
        } catch {
            link = .unreachable(String(localized: "Can't reach your Mac: \(error.localizedDescription)"))
            return
        }
        guard running, local == nil else { return }
        let channel = CloudChannel<ClientMessage, HostMessage>(me: pairing.key.identity, peer: "mac", secret: pairing.key.secret,
                                                                mailbox: mailbox)
        cloud = channel
        link = .cloud
        let hello: [ClientMessage] = [.hello(version: Wire.version, deviceID: pairing.key.identity, deviceName: deviceName), .away]
            + opened.map { .open(chatID: $0) }
        try? await channel.send(hello)
        // While on screen: read every 2 s (pushes can lag), and say "still here" each minute.
        cloudTimer = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let channel = self.cloud else { return }
                await self.cloudPoll()
                ticks += 1
                if ticks % 30 == 0 { try? await channel.send([.away]) }
            }
        }
    }

    func cloudPoll() async {
        guard let cloud, let messages = try? await cloud.poll() else { return }
        for message in messages { receive(message) }
    }

    private func stopCloud() {
        cloudTimer?.cancel()
        cloudTimer = nil
        cloud = nil
        if link == .cloud { link = .searching }
    }

    // MARK: Sending

    private func post(_ messages: [ClientMessage]) {
        if let local { local.send(messages); return }
        if let cloud { Task { try? await cloud.send(messages) } }
    }

    func request(_ make: (UUID) -> ClientMessage) async -> Answer {
        guard local != nil || cloud != nil else {
            return Answer(ok: false, reason: String(localized: "Not connected to your Mac."), chatID: nil)
        }
        let id = UUID()
        let message = make(id)
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            post([message])
            // Through iCloud an answer can take a few seconds; give up after 30.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.pending.removeValue(forKey: id)?.resume(returning: Answer(ok: false, reason: String(localized: "Your Mac didn't answer."), chatID: nil))
            }
        }
    }

    /// A request answered with data (a folder, a file, git status…); nil when refused, with the
    /// reason shown, unless `quiet`.
    func call(quiet: Bool = false, _ make: (UUID) -> ClientMessage) async -> HostMessage? {
        let answer = await request(make)
        if !answer.ok, !quiet { notice = answer.reason }
        return answer.payload
    }

    /// A request answered with ok or a reason; false (reason shown) when refused.
    @discardableResult
    func act(_ make: (UUID) -> ClientMessage) async -> Bool {
        let answer = await request(make)
        if !answer.ok { notice = answer.reason }
        return answer.ok
    }

    @discardableResult
    func send(_ text: String, in chatID: UUID) async -> Answer {
        let answer = await request { .send(requestID: $0, chatID: chatID, text: text) }
        if !answer.ok { notice = answer.reason }
        return answer
    }

    func newChat(in projectID: UUID?, text: String, settings: RemoteChatSettings) async -> UUID? {
        let answer = await request { .newChat(requestID: $0, projectID: projectID, text: text, settings: settings) }
        if !answer.ok { notice = answer.reason }
        return answer.ok ? answer.chatID : nil
    }

    func stop(_ chatID: UUID) async { _ = await request { .stop(requestID: $0, chatID: chatID) } }

    func edit(_ messageID: UUID, to text: String, in chatID: UUID) async {
        let answer = await request { .edit(requestID: $0, chatID: chatID, messageID: messageID, text: text) }
        if !answer.ok { notice = answer.reason }
    }

    func runPlan(_ messageID: UUID, in chatID: UUID) async {
        let answer = await request { .runPlan(requestID: $0, chatID: chatID, messageID: messageID) }
        if !answer.ok { notice = answer.reason }
    }

    func cancelPlan(_ messageID: UUID, in chatID: UUID) async { _ = await request { .cancelPlan(requestID: $0, chatID: chatID, messageID: messageID) } }

    func set(_ settings: RemoteChatSettings, for chatID: UUID) async {
        let answer = await request { .setChat(requestID: $0, chatID: chatID, settings: settings) }
        if !answer.ok { notice = answer.reason }
    }

    @discardableResult
    func rename(_ chatID: UUID, to title: String) async -> Bool {
        let answer = await request { .rename(requestID: $0, chatID: chatID, title: title) }
        if !answer.ok { notice = answer.reason }
        return answer.ok
    }

    func retry(_ chatID: UUID) async {
        let answer = await request { .retry(requestID: $0, chatID: chatID) }
        if !answer.ok { notice = answer.reason }
    }

    /// The chat just deleted, for the Undo banner.
    private(set) var lastDeleted: RemoteChat?

    func delete(_ chatID: UUID) async {
        let chat = chats.first { $0.id == chatID }
        // Gone from the list at once; back if the Mac says no.
        chats.removeAll { $0.id == chatID }
        let answer = await request { .delete(requestID: $0, chatID: chatID) }
        if answer.ok {
            lastDeleted = chat
            transcripts[chatID] = nil
            opened.remove(chatID)
        } else {
            if let chat, !chats.contains(where: { $0.id == chat.id }) { chats.append(chat); chats.sort { $0.updatedAt > $1.updatedAt } }
            notice = answer.reason
        }
    }

    func undoDelete() async {
        guard let chat = lastDeleted else { return }
        lastDeleted = nil
        let answer = await request { .undoDelete(requestID: $0, chatID: chat.id) }
        if !answer.ok { notice = answer.reason }
    }

    func forgetDeleted() { lastDeleted = nil }

    func open(_ chatID: UUID) {
        guard opened.insert(chatID).inserted else { return }
        post([.open(chatID: chatID)])
    }

    func close(_ chatID: UUID) {
        guard opened.remove(chatID) != nil else { return }
        post([.close(chatID: chatID)])
    }

    // MARK: Receiving

    func receive(_ message: HostMessage) {
        switch message {
        case .hello(_, let name, _):
            macName = name
        case .workspace(let projects, let chats, let agents):
            self.projects = projects
            self.chats = chats.sorted { $0.updatedAt > $1.updatedAt }
            self.agents = agents
            saveCache()
        case .chat(let chat):
            if let index = chats.firstIndex(where: { $0.id == chat.id }) { chats[index] = chat } else { chats.append(chat) }
            chats.sort { $0.updatedAt > $1.updatedAt }
            saveCache()
        case .chatRemoved(let id):
            chats.removeAll { $0.id == id }
            transcripts[id] = nil
        case .agents(let agents):
            self.agents = agents
        case .transcript(let chatID, let messages):
            transcripts[chatID] = messages
        case .message(let chatID, let message):
            var list = transcripts[chatID] ?? []
            if let index = list.firstIndex(where: { $0.id == message.id }) { list[index] = message } else { list.append(message) }
            transcripts[chatID] = list.sorted { $0.createdAt < $1.createdAt }
        case .messageRemoved(let chatID, let messageID):
            transcripts[chatID]?.removeAll { $0.id == messageID }
        case .live(let chatID, let parts):
            live[chatID] = parts.isEmpty ? nil : parts
        case .reply(let requestID, let ok, let reason, let chatID):
            pending.removeValue(forKey: requestID)?.resume(returning: Answer(ok: ok, reason: reason, chatID: chatID))
        case .folder(let requestID, _), .file(let requestID, _), .git(let requestID, _), .diff(let requestID, _),
             .macFolders(let requestID, _, _), .notes(let requestID, _, _), .automations(let requestID, _, _, _),
             .crew(let requestID, _, _), .avatarImage(let requestID, _):
            pending.removeValue(forKey: requestID)?.resume(returning: Answer(ok: true, reason: nil, chatID: nil, payload: message))
        }
    }

    func chat(_ id: UUID) -> RemoteChat? { chats.first { $0.id == id } }
    func project(_ id: UUID?) -> RemoteProject? { id.flatMap { id in projects.first { $0.id == id } } }
    func agent(_ id: String) -> RemoteAgent? { agents.first { $0.id == id } }

    private func saveCache() {
        Cache.save(.init(macName: macName, projects: projects, chats: chats, agents: agents))
    }
}

/// The pairing, in this device's Keychain (not synced: the key belongs to this device).
enum PairingStore {
    static let service = "dev.xbot.mobile.pairing"

    static func load() -> PairingInvite? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? Wire.decoder.decode(PairingInvite.self, from: data)
    }

    static func save(_ invite: PairingInvite) {
        clear()
        guard let data = try? Wire.encoder.encode(invite) else { return }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                   kSecValueData as String: data]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

/// The last chat list, so the app opens on something while it finds the Mac.
enum Cache {
    struct Snapshot: Codable { var macName: String?; var projects: [RemoteProject]; var chats: [RemoteChat]; var agents: [RemoteAgent] }
    static var url: URL { URL.cachesDirectory.appending(path: "workspace.json") }
    static func load() -> Snapshot? { (try? Data(contentsOf: url)).flatMap { try? Wire.decoder.decode(Snapshot.self, from: $0) } }
    static func save(_ snapshot: Snapshot) { try? Wire.encoder.encode(snapshot).write(to: url, options: .atomic) }
    static func clear() { try? FileManager.default.removeItem(at: url) }
}
