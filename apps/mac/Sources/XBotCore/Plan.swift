import Foundation

/// A plan: what the agent proposed, what the person approved, and how running it went. Saved as a
/// part of one assistant message and replaced in place on every change.
public struct Plan: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// The planning turn is investigating.
        case drafting
        /// Waiting for the person.
        case review
        case running
        case finished
        /// Cancelled in review (`startedAt == nil`), stopped mid-run, or halted by a failed turn.
        case stopped
    }

    /// What the person asked, kept so Try again can ask again.
    public var prompt: String
    public var status: Status
    public var summary: String = ""
    /// The latest step note, shown under the header; starts as the summary.
    public var note: String = ""
    public var steps: [PlanStep] = []
    /// What the planning turn looked at.
    public var investigation: [ToolPart] = []
    /// Text the planning turn wrote, shown only when no plan came back.
    public var reply: String = ""
    /// Why there is no plan, when there is none.
    public var problem: String?
    /// Steps the agent added while running.
    public var added: Int = 0
    /// The step whose turn failed and halted the plan; Resume starts there.
    public var haltedStepID: UUID?
    /// The agent's closing sentence.
    public var closing: String?
    public var startedAt: Date?
    public var endedAt: Date?

    public init(prompt: String, status: Status) {
        self.prompt = prompt
        self.status = status
    }

    public var doneCount: Int { steps.filter { $0.status == .done }.count }
    public var failedCount: Int { steps.filter { $0.status == .failed }.count }
    /// Cancelled from the review card: stopped before anything ran.
    public var isCancelled: Bool { status == .stopped && startedAt == nil && problem == nil }
}

public struct PlanStep: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case pending, running, done, failed, stopped }

    public var id: UUID
    public var title: String
    /// The step as an -ing phrase, shown while it runs. Becomes `title` when the person edits it.
    public var active: String
    public var status: Status
    public var note: String?
    public var tools: [ToolPart]
    /// Added by the agent while the plan ran.
    public var added: Bool
    public var startedAt: Date?
    public var endedAt: Date?

    public init(
        id: UUID = UUID(), title: String, active: String, status: Status = .pending, added: Bool = false
    ) {
        self.id = id
        self.title = title
        self.active = active
        self.status = status
        self.note = nil
        self.tools = []
        self.added = added
        self.startedAt = nil
        self.endedAt = nil
    }
}

/// The JSON Schemas the agent's answers must follow. Strict — no extra properties, every one
/// required — because Codex rejects anything looser, and every field is described because a field
/// without a description was misread in testing.
public enum PlanSchemas {
    private static let stepItem = #"""
    {"type":"object","additionalProperties":false,"required":["title","active"],"properties":{
      "title":{"type":"string","description":"The step as a short imperative, 3 to 8 words, e.g. 'Find where search fetches results'."},
      "active":{"type":"string","description":"The same step as an -ing phrase, e.g. 'Finding where search fetches results'."}}}
    """#

    public static let plan = #"""
    {"type":"object","additionalProperties":false,"required":["summary","steps"],"properties":{
      "summary":{"type":"string","description":"One sentence: what you will do and why."},
      "steps":{"type":"array","description":"The plan, in order: 3 to 8 steps.","items":
    """# + stepItem + "}}}"

    public static let step = #"""
    {"type":"object","additionalProperties":false,"required":["outcome","note","add"],"properties":{
      "outcome":{"type":"string","enum":["done","failed"],"description":"failed if the step could not be completed, e.g. a test failed."},
      "note":{"type":"string","description":"One sentence for the user about what you found or did."},
      "add":{"type":"array","description":"Steps to insert right after this one to finish the job. Usually none.","items":
    """# + stepItem + "}}}"
}

public struct StepDraft: Decodable, Equatable, Sendable {
    public var title: String
    public var active: String
}

public struct PlanAnswer: Decodable, Equatable, Sendable {
    public var summary: String
    public var steps: [StepDraft]

    public static func decode(_ json: String) -> PlanAnswer? {
        try? JSONDecoder().decode(PlanAnswer.self, from: Data(json.utf8))
    }
}

public struct StepAnswer: Decodable, Equatable, Sendable {
    public var outcome: String
    public var note: String
    public var add: [StepDraft]

    public var failed: Bool { outcome == "failed" }

    public static func decode(_ json: String) -> StepAnswer? {
        try? JSONDecoder().decode(StepAnswer.self, from: Data(json.utf8))
    }
}
