import Foundation
import Network

/// The local-network connection between the Mac and a phone: TCP with TLS 1.2 keyed by the
/// pre-shared key from pairing (no certificates, nothing to trust but the key), advertised over
/// Bonjour as `_xbot._tcp` with the Mac's id in its TXT record. Messages are length-prefixed JSON
/// frames (`Frame`). Waits on the kernel; no timers or polling.
public enum LocalTLS {
    /// Parameters for either side. The listener takes every paired device's key; a phone, its own.
    public static func parameters(keys: [PairingKey]) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        for key in keys {
            let secret = key.secret.withUnsafeBytes { DispatchData(bytes: $0) }
            let identity = Data(key.identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
            sec_protocol_options_add_pre_shared_key(options, secret as __DispatchData, identity as __DispatchData)
        }
        // PSK suites exist in TLS 1.2 only.
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(options, suite)
        }
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// A device's pairing: an id the TLS handshake names it by, and a 256-bit secret.
public struct PairingKey: Codable, Equatable, Sendable, Identifiable {
    public var identity: String
    public var secret: Data
    public var id: String { identity }

    public init(identity: String, secret: Data) { self.identity = identity; self.secret = secret }

    public static func generate() -> PairingKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PairingKey(identity: UUID().uuidString, secret: Data(bytes))
    }
}

/// What the QR code on the Mac carries: everything a phone needs to find and trust it.
public struct PairingInvite: Codable, Equatable, Sendable {
    public var macID: UUID
    public var macName: String
    public var key: PairingKey
    /// Where to reach it directly if Bonjour can't (same network, a VPN): host and port.
    public var host: String?
    public var port: UInt16?

    public init(macID: UUID, macName: String, key: PairingKey, host: String? = nil, port: UInt16? = nil) {
        self.macID = macID; self.macName = macName; self.key = key; self.host = host; self.port = port
    }

    /// `xbot://pair?…`, the QR code's text.
    public var url: URL {
        let body = (try? Wire.encoder.encode(self)) ?? Data()
        var parts = URLComponents()
        parts.scheme = "xbot"
        parts.host = "pair"
        parts.queryItems = [URLQueryItem(name: "v", value: body.base64EncodedString())]
        return parts.url!
    }

    public init?(url: URL) {
        guard url.scheme == "xbot", url.host == "pair",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value,
              let data = Data(base64Encoded: value),
              let invite = try? Wire.decoder.decode(PairingInvite.self, from: data) else { return nil }
        self = invite
    }
}

/// One framed connection: decodes `Incoming` frames as they arrive, sends any `Encodable` ones.
public final class FramedConnection<Incoming: Decodable & Sendable>: @unchecked Sendable {
    public enum State: Sendable { case ready, closed(String?) }

    public let connection: NWConnection
    /// Called on the main queue.
    public var onMessages: (@MainActor ([Incoming]) -> Void)?
    public var onState: (@MainActor (State) -> Void)?
    private let queue = DispatchQueue(label: "xbot.remote.connection")
    private var buffer = Data()
    private var closed = false

    public init(_ connection: NWConnection) { self.connection = connection }

    public convenience init(to endpoint: NWEndpoint, key: PairingKey) {
        self.init(NWConnection(to: endpoint, using: LocalTLS.parameters(keys: [key])))
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.report(.ready)
            case .failed(let error): self.close(error.localizedDescription)
            case .cancelled: self.close(nil)
            case .waiting(let error):
                // A wrong key or an unreachable Mac: don't wait for the network to change.
                self.close(error.localizedDescription)
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    public func send<M: Encodable>(_ messages: [M]) {
        guard !messages.isEmpty else { return }
        var data = Data()
        for message in messages { if let frame = try? Frame.encode(message) { data.append(frame) } }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.close(error.localizedDescription) }
        })
    }

    public func cancel() { connection.cancel() }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                do {
                    let messages = try Frame.decode(Incoming.self, from: &self.buffer)
                    if !messages.isEmpty {
                        let handler = self.onMessages
                        DispatchQueue.main.async { MainActor.assumeIsolated { handler?(messages) } }
                    }
                } catch {
                    self.connection.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    private func close(_ reason: String?) {
        guard !closed else { return }
        closed = true
        connection.cancel()
        report(.closed(reason))
    }

    private func report(_ state: State) {
        let handler = onState
        DispatchQueue.main.async { MainActor.assumeIsolated { handler?(state) } }
    }
}

/// The Mac's listener. Restarted with the new keys when a device is paired or removed.
public final class LocalListener: @unchecked Sendable {
    public private(set) var port: UInt16?
    /// A phone connected and completed the handshake.
    public var onConnection: (@MainActor (FramedConnection<ClientMessage>) -> Void)?
    public var onReady: (@MainActor (UInt16) -> Void)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "xbot.remote.listener")

    public init() {}

    /// `advertise`: publish on Bonjour (off in tests). `port`: fixed, or any free one.
    public func start(keys: [PairingKey], macID: UUID, macName: String, advertise: Bool = true, port: UInt16? = nil) throws {
        stop()
        guard !keys.isEmpty else { return }
        let parameters = LocalTLS.parameters(keys: keys)
        let listener = try port.flatMap(NWEndpoint.Port.init(rawValue:)).map { try NWListener(using: parameters, on: $0) }
            ?? NWListener(using: parameters)
        if advertise {
            let txt = NWTXTRecord(["mac": macID.uuidString, "v": "\(Wire.version)"])
            listener.service = NWListener.Service(name: macName, type: Wire.bonjourType, txtRecord: txt)
        }
        listener.newConnectionHandler = { [weak self] connection in
            let framed = FramedConnection<ClientMessage>(connection)
            let handler = self?.onConnection
            DispatchQueue.main.async { MainActor.assumeIsolated { handler?(framed) } }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            if case .ready = state, let port = listener?.port?.rawValue {
                self?.port = port
                let ready = self?.onReady
                DispatchQueue.main.async { MainActor.assumeIsolated { ready?(port) } }
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }
}

/// The phone's search for its Mac on the local network, by the id in the Bonjour TXT record.
public final class LocalBrowser: @unchecked Sendable {
    public var onFound: (@MainActor (NWEndpoint?) -> Void)?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "xbot.remote.browser")

    public init() {}

    public func start(macID: UUID) {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Wire.bonjourType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let match = results.first { result in
                if case .bonjour(let txt) = result.metadata { return txt["mac"] == macID.uuidString }
                return false
            }
            let found = self?.onFound
            DispatchQueue.main.async { MainActor.assumeIsolated { found?(match?.endpoint) } }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }
}
