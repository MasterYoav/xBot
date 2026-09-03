import Foundation

/// Where the engine is. Explicit and exhaustive: every state here has something the UI can show.
///
/// There is deliberately no "probably starting" case. A spinner with no state behind it is how an
/// app ends up force-quit, because the user has no way to tell waiting from stuck.
public enum RuntimeState: Sendable, Equatable {
    case notDetected(ProbeResult)
    case stopped
    case pulling(PullProgress)
    case starting(Stage)
    case running(EngineEndpoint)
    case degraded(reason: DegradedReason)
    case failed(RuntimeError)

    /// The steps of a start, named, so the UI says which one is happening.
    public enum Stage: String, Sendable, CaseIterable {
        /// Waiting for the container runtime's own daemon, which the app just asked to start.
        case runtime
        case volumes
        case ports
        case container
        case migrations
        case health

        public var sentence: String {
            switch self {
            case .runtime: String(localized: "Starting the container runtime")
            case .volumes: String(localized: "Preparing storage")
            case .ports: String(localized: "Choosing a port")
            case .container: String(localized: "Starting the engine")
            case .migrations: String(localized: "Updating the database")
            case .health: String(localized: "Almost ready")
            }
        }
    }

    /// Up, but not well.
    ///
    /// A real and common state that is neither running nor failed — the API answering while the
    /// computer is down, or health flapping after the Mac wakes. Collapsing it into `failed` makes
    /// the app cry wolf; collapsing it into `running` makes it lie.
    public enum DegradedReason: String, Sendable {
        case healthLost
        case computerDown
        case slowToRespond

        public var sentence: String {
            switch self {
            case .healthLost: String(localized: "Reconnecting")
            case .computerDown: String(localized: "The agent's computer is restarting")
            case .slowToRespond: String(localized: "The engine is slow to respond")
            }
        }
    }
}

public struct EngineEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16

    public init(host: String = "127.0.0.1", port: UInt16) {
        self.host = host
        self.port = port
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }
}

public enum RuntimeEvent: Sendable, Equatable {
    case stateChanged(RuntimeState)
    case log(String)
}
