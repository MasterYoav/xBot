import Foundation
@_exported import XBotBrain

/// A folder on this Mac that chats work in. Any folder — git features appear only when it is a repo.
public struct Project: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var createdAt: Date
    public var url: URL { URL(filePath: path, directoryHint: .isDirectory) }

    public init(id: UUID = UUID(), name: String, path: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
    }
}

public struct Chat: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Nil: an Inbox chat, which works in xBot's own Inbox folder.
    public var projectID: UUID?
    public var title: String
    public var harness: HarnessKind
    public var model: String?
    public var mode: PermissionMode
    /// The CLI's session, so the next turn continues it. Belongs to `harness` and is cleared with it.
    public var sessionID: String?
    /// The Plan chip: messages become a plan, then steps.
    public var planMode: Bool
    /// With plan mode: wait for the person to review the plan before running it.
    public var reviewPlan: Bool
    /// How hard the agent thinks. Nil: the agent's own default.
    public var effort: Effort?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), projectID: UUID?, title: String, harness: HarnessKind, model: String? = nil,
        mode: PermissionMode, sessionID: String? = nil, planMode: Bool = false, reviewPlan: Bool = true,
        effort: Effort? = nil, createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.harness = harness
        self.model = model
        self.mode = mode
        self.sessionID = sessionID
        self.planMode = planMode
        self.reviewPlan = reviewPlan
        self.effort = effort
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum Role: String, Codable, Sendable {
    case user
    case assistant
}

public struct ToolPart: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    /// Nil while the tool is still running.
    public var output: String?
    public var isError: Bool
    /// What the result amounted to: "64 lines", "18 items", "+39".
    public var size: String?
    public var startedAt: Date?
    public var endedAt: Date?

    public init(
        id: String, name: String, summary: String, output: String?, isError: Bool,
        size: String? = nil, startedAt: Date? = nil, endedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.output = output
        self.isError = isError
        self.size = size
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum Part: Codable, Equatable, Sendable {
    case text(String)
    case tool(ToolPart)
    case notice(String)
    case failure(String)
    case plan(Plan)
}

public struct ChatMessage: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var chatID: UUID
    public var role: Role
    public var parts: [Part]
    public var createdAt: Date

    public init(id: UUID = UUID(), chatID: UUID, role: Role, parts: [Part], createdAt: Date = .now) {
        self.id = id
        self.chatID = chatID
        self.role = role
        self.parts = parts
        self.createdAt = createdAt
    }

    /// The plan this message holds, if it is a plan.
    public var plan: Plan? {
        for part in parts { if case .plan(let plan) = part { return plan } }
        return nil
    }
}

extension Array where Element == Part {
    /// Fold one brain event into a reply that is being written. `now` stamps tool calls and results.
    public mutating func apply(_ event: BrainEvent, at now: Date? = nil) {
        switch event {
        case .textDelta(let delta):
            if case .text(let text) = last { self[count - 1] = .text(text + delta) } else { append(.text(delta)) }
        case .text(let text):
            append(.text(text))
        case .toolCall(let id, let name, let summary, let size):
            append(.tool(ToolPart(id: id, name: name, summary: summary, output: nil, isError: false,
                                  size: size, startedAt: now)))
        case .toolResult(let id, let output, let isError):
            if let index = lastIndex(where: { if case .tool(let tool) = $0 { tool.id == id } else { false } }),
               case .tool(var tool) = self[index] {
                tool.finish(output: output, isError: isError, at: now)
                self[index] = .tool(tool)
            }
        case .notice(let text):
            append(.notice(text))
        case .failed(let reason):
            append(.failure(reason))
        case .session, .done, .structured:
            break
        }
    }
}

extension Array where Element == ToolPart {
    /// The tool rows of a plan step: the same folding, for tools only.
    public mutating func apply(_ event: BrainEvent, at now: Date? = nil) {
        switch event {
        case .toolCall(let id, let name, let summary, let size):
            append(ToolPart(id: id, name: name, summary: summary, output: nil, isError: false,
                            size: size, startedAt: now))
        case .toolResult(let id, let output, let isError):
            if let index = lastIndex(where: { $0.id == id }) { self[index].finish(output: output, isError: isError, at: now) }
        default:
            break
        }
    }

    /// Tools with no result when their turn ended never finished.
    public mutating func finishUnfinished() {
        for index in indices where self[index].output == nil {
            self[index].output = ""
            self[index].isError = true
        }
    }
}

extension ToolPart {
    mutating func finish(output: String, isError: Bool, at now: Date?) {
        self.output = output
        self.isError = isError
        endedAt = now
        size = size ?? ToolLabel.size(name: name, output: output)
    }
}
