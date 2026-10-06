import Foundation

/// Everything a brain says during one turn, in order.
///
/// Both brains — an agent CLI driven as a harness, and later the native loop — speak this and
/// nothing else, so the transcript never knows which one it is showing.
public enum BrainEvent: Equatable, Sendable {
    /// The brain's own id for this conversation. Passed back as `TurnRequest.resumeID` next turn.
    case session(String)
    /// A piece of streamed reply text, appended to the text block in progress.
    case textDelta(String)
    /// A whole block of reply text that arrives at once.
    case text(String)
    case toolCall(id: String, name: String, summary: String)
    case toolResult(id: String, output: String, isError: Bool)
    /// Something the harness said that is not part of the reply, such as a config warning.
    case notice(String)
    case done
    case failed(String)

    public var isTerminal: Bool {
        switch self {
        case .done, .failed: true
        default: false
        }
    }
}

public enum PermissionMode: String, Codable, CaseIterable, Sendable {
    /// Reads and answers; changes to the folder are refused.
    case readOnly
    /// Edits files in the folder.
    case editFiles
    /// Anything, without asking.
    case fullAccess
}

public struct TurnRequest: Equatable, Sendable {
    public var prompt: String
    public var directory: URL
    /// Nil means the CLI's own default.
    public var model: String?
    public var mode: PermissionMode
    public var resumeID: String?

    public init(
        prompt: String,
        directory: URL,
        model: String? = nil,
        mode: PermissionMode,
        resumeID: String? = nil
    ) {
        self.prompt = prompt
        self.directory = directory
        self.model = model
        self.mode = mode
        self.resumeID = resumeID
    }
}

public protocol Brain: Sendable {
    /// One turn. The stream ends with exactly one `.done` or `.failed`, and cancelling the task
    /// that consumes it stops the turn.
    func run(_ request: TurnRequest) -> AsyncStream<BrainEvent>
}
