import Foundation
import XBotBrain

/// A workflow: agent steps and Jev decision steps, run in order as one chat, with Jev's steps
/// gating, routing and scoring between them. Runs like an automation (Run now, or a schedule).
/// See docs/superpowers/specs/2026-10-12-jev-workflows-design.md.
public struct Workflow: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: Automation.Trigger
    public var steps: [WorkflowStep]
    /// The brain a "Jev picks" step falls back to when Jev can't be reached.
    public var harness: HarnessKind
    public var model: String?
    public var effort: Effort?
    /// Where it works. Nil: xBot's Inbox folder.
    public var projectID: UUID?
    public var isEnabled: Bool
    public var lastRunAt: Date?
    public var createdAt: Date
    public var sortIndex: Int

    public init(
        id: UUID = UUID(), name: String, trigger: Automation.Trigger, steps: [WorkflowStep], harness: HarnessKind = .claude,
        model: String? = nil, effort: Effort? = nil, projectID: UUID? = nil, isEnabled: Bool = true,
        lastRunAt: Date? = nil, createdAt: Date = .now, sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.steps = steps
        self.harness = harness
        self.model = model
        self.effort = effort
        self.projectID = projectID
        self.isEnabled = isEnabled
        self.lastRunAt = lastRunAt
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }

    public var fallback: BrainChoice { BrainChoice(harness: harness, model: model, effort: effort) }

    /// When it should next run: after its last run, or after it was made. Nil for Run now only.
    public func nextRun(calendar: Calendar = .current) -> Date? {
        guard case .schedule(let schedule) = trigger else { return nil }
        return schedule.next(after: lastRunAt ?? createdAt, calendar: calendar)
    }

    public func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, let next = nextRun(calendar: calendar) else { return false }
        return next <= now
    }

    /// Something to run: at least one agent step that says something.
    public var hasWork: Bool {
        steps.contains { step in
            guard case .agent(let agent) = step.kind else { return false }
            return !agent.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Asks Jev something when it runs: a Jev step, or an agent step set to Jev picks.
    public var needsJev: Bool {
        steps.contains { step in
            switch step.kind {
            case .jev: true
            case .agent(let agent): agent.brain == .jevPicks
            }
        }
    }

    // MARK: Editing

    /// Moves a step to `index` (0…steps.count), the way a dragged card lands.
    public mutating func move(_ id: UUID, to index: Int) {
        guard let from = steps.firstIndex(where: { $0.id == id }) else { return }
        let step = steps.remove(at: from)
        let index = min(max(index, 0), steps.count + 1)
        steps.insert(step, at: min(from < index ? index - 1 : index, steps.count))
    }

    /// Removes a step; a go-to that pointed at it goes on to the next step instead.
    public mutating func removeStep(_ id: UUID) {
        steps.removeAll { $0.id == id }
        for index in steps.indices {
            guard case .jev(var jev) = steps[index].kind else { continue }
            jev.retarget(from: id, to: .next)
            steps[index].kind = .jev(jev)
        }
    }

    public func step(_ id: UUID) -> WorkflowStep? { steps.first { $0.id == id } }

    /// The editor's palette: the kinds of step that can be dragged in.
    public enum PaletteKind: String, CaseIterable, Sendable {
        case agent, gate, route, score
    }

    /// What a palette tile or a step card carries when dragged.
    public static func dragItem(for kind: PaletteKind) -> String { "wadd:" + kind.rawValue }
    public static func dragItem(for step: WorkflowStep) -> String { "wstep:" + step.id.uuidString }

    /// A drop at `index` (0…steps.count): "wadd:gate" adds a step there, "wstep:<id>" moves that
    /// step there. False when the item isn't one of these.
    @discardableResult
    public mutating func drop(_ item: String, at index: Int) -> Bool {
        let index = min(max(index, 0), steps.count)
        if item.hasPrefix("wadd:"), let kind = PaletteKind(rawValue: String(item.dropFirst(5))) {
            steps.insert(Self.newStep(kind), at: index)
            return true
        }
        if item.hasPrefix("wstep:"), let id = UUID(uuidString: String(item.dropFirst(6))), step(id) != nil {
            move(id, to: index)
            return true
        }
        return false
    }

    /// A new step of a kind, with something to edit already in it.
    public static func newStep(_ kind: PaletteKind) -> WorkflowStep {
        switch kind {
        case .agent:
            WorkflowStep(title: String(localized: "Agent step"), kind: .agent(AgentStep(prompt: "")))
        case .gate:
            WorkflowStep(title: String(localized: "Gate"), kind: .jev(JevStep(question: "", decision: .gate(JevGate()))))
        case .route:
            WorkflowStep(title: String(localized: "Route"), kind: .jev(JevStep(question: "", decision: .route([
                RouteOption(label: String(localized: "First option")), RouteOption(label: String(localized: "Second option")),
            ]))))
        case .score:
            WorkflowStep(title: String(localized: "Score"), kind: .jev(JevStep(question: "", decision: .score([
                ScoreLevel(label: String(localized: "Low")), ScoreLevel(label: String(localized: "Medium")),
                ScoreLevel(label: String(localized: "High")),
            ]))))
        }
    }
}

public struct WorkflowStep: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: Equatable, Codable, Sendable {
        case agent(AgentStep)
        case jev(JevStep)
    }

    public var id: UUID
    public var title: String
    public var kind: Kind

    public init(id: UUID = UUID(), title: String, kind: Kind) {
        self.id = id
        self.title = title
        self.kind = kind
    }
}

/// A CLI, a model and an effort. Nil model or effort: the agent's own default.
public struct BrainChoice: Hashable, Codable, Sendable {
    public var harness: HarnessKind
    public var model: String?
    public var effort: Effort?
    public init(harness: HarnessKind, model: String? = nil, effort: Effort? = nil) {
        self.harness = harness
        self.model = model
        self.effort = effort
    }
}

public enum StepBrain: Hashable, Codable, Sendable {
    case fixed(BrainChoice)
    /// Jev picks the cheapest capable CLI, model and effort for the step's prompt, just before it runs.
    case jevPicks
}

/// A prompt in plain words for an LLM agent. Its reply is the step's output.
public struct AgentStep: Equatable, Codable, Sendable {
    public var prompt: String
    public var brain: StepBrain
    public var mode: PermissionMode

    public init(prompt: String, brain: StepBrain = .jevPicks, mode: PermissionMode = .editFiles) {
        self.prompt = prompt
        self.brain = brain
        self.mode = mode
    }
}

/// Where a run goes after a Jev step.
public enum StepTarget: Hashable, Codable, Sendable {
    /// The step after this one (or the end).
    case next
    case step(UUID)
    case stop
}

public struct JevGate: Equatable, Codable, Sendable {
    /// P(yes) at or above it is yes.
    public var threshold: Double
    public var yes: StepTarget
    public var no: StepTarget
    public init(threshold: Double = 0.5, yes: StepTarget = .next, no: StepTarget = .stop) {
        self.threshold = threshold
        self.yes = yes
        self.no = no
    }
}

public struct RouteOption: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var label: String
    public var target: StepTarget
    public init(id: UUID = UUID(), label: String, target: StepTarget = .next) {
        self.id = id
        self.label = label
        self.target = target
    }
}

public struct ScoreLevel: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var label: String
    public var target: StepTarget
    public init(id: UUID = UUID(), label: String, target: StepTarget = .next) {
        self.id = id
        self.label = label
        self.target = target
    }
}

/// One question to Jev about the run so far.
public struct JevStep: Equatable, Codable, Sendable {
    public enum Decision: Equatable, Codable, Sendable {
        /// Yes/no against a threshold.
        case gate(JevGate)
        /// One of the options, each going somewhere.
        case route([RouteOption])
        /// 2–10 ordered levels, lowest first, each going somewhere.
        case score([ScoreLevel])
    }

    public var question: String
    public var decision: Decision

    public init(question: String, decision: Decision) {
        self.question = question
        self.decision = decision
    }

    /// What a run does after asking: where it goes, and what Jev said, for the notice.
    public struct Outcome: Equatable, Sendable {
        public var target: StepTarget
        /// "yes (0.91)", "Fix code (0.88)", "OK, 1.38 (0.58)".
        public var said: String
    }

    /// The name the question is asked under.
    static let name = "decision"

    /// The question as Jev takes it.
    public func jevQuestion() -> JevQuestion {
        switch decision {
        case .gate: .noul(question)
        case .route(let options):
            .choice(question, options: options.enumerated().map { JevQuestion.Option(key: Self.key(for: $0.element, at: $0.offset), description: $0.element.label) })
        case .score(let levels): .score(question, levels: levels.map(\.label))
        }
    }

    /// Where Jev's answer leads. Nil: the answer doesn't fit the question (fail closed).
    public func decide(_ answer: JevAnswer) -> Outcome? {
        switch (decision, answer) {
        case (.gate(let gate), .noul(let p)):
            let yes = p >= gate.threshold
            return Outcome(target: yes ? gate.yes : gate.no,
                           said: (yes ? String(localized: "yes") : String(localized: "no")) + " (\(Self.format(p)))")
        case (.route(let options), .choice(let key, _, let confidence)):
            guard let index = options.indices.first(where: { Self.key(for: options[$0], at: $0) == key }) else { return nil }
            return Outcome(target: options[index].target, said: "\(options[index].label) (\(Self.format(confidence)))")
        case (.score(let levels), .score(let score, _, _, let confidence)):
            guard !levels.isEmpty else { return nil }
            let index = min(max(Int(score.rounded()), 0), levels.count - 1)
            return Outcome(target: levels[index].target,
                           said: "\(levels[index].label), \(Self.format(score)) (\(Self.format(confidence)))")
        default:
            return nil
        }
    }

    /// Changes go-tos at `id` to `replacement` (the step was removed).
    mutating func retarget(from id: UUID, to replacement: StepTarget) {
        func fix(_ target: inout StepTarget) { if target == .step(id) { target = replacement } }
        switch decision {
        case .gate(var gate):
            fix(&gate.yes); fix(&gate.no)
            decision = .gate(gate)
        case .route(var options):
            for i in options.indices { fix(&options[i].target) }
            decision = .route(options)
        case .score(var levels):
            for i in levels.indices { fix(&levels[i].target) }
            decision = .score(levels)
        }
    }

    /// A choice key from the option's words ("fix_code"), so Jev reads meaning in it too; its
    /// position keeps two alike options apart.
    static func key(for option: RouteOption, at index: Int) -> String {
        "\(index + 1)_" + slug(option.label)
    }

    static func slug(_ text: String) -> String {
        let words = text.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "_" }
        let joined = String(words).split(separator: "_").joined(separator: "_")
        return String(joined.prefix(40))
    }

    static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}

/// What a Jev step is asked about: the workflow's input, then every earlier step's output under
/// its title, newest last, trimmed from the oldest end to fit.
public enum WorkflowState {
    /// About 4,000 tokens: plenty for a decision, and a fraction of a cent at Jev's price.
    public static let limit = 16_000

    public static func assemble(input: String, outputs: [(title: String, text: String)], limit: Int = limit) -> String {
        var sections: [String] = []
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty { sections.append("Input:\n" + input) }
        for output in outputs {
            sections.append("## \(output.title)\n" + output.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let whole = sections.joined(separator: "\n\n")
        guard whole.count > limit else { return whole }
        return "…" + String(whole.suffix(max(limit - 1, 0)))
    }
}
