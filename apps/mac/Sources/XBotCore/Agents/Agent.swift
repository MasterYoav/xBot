import Foundation
import XBotBrain

/// A persona over one of the CLIs: who it is, how it looks, how it works. See the agents spec.
public struct Agent: Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// One line: what it does.
    public var role: String
    /// How it works. Sent with every turn, after who it is and who the crew are.
    public var instructions: String
    public var avatar: AgentAvatar
    public var harness: HarnessKind
    /// Nil: the CLI's default.
    public var model: String?
    /// Where its chats start. Nil: the project in context, else the Inbox.
    public var projectID: UUID?
    /// The founding orchestrator. Exactly one; it hands work to the others and cannot be deleted.
    public var isHeadMaster: Bool
    public var sortIndex: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(), name: String, role: String, instructions: String, avatar: AgentAvatar,
        harness: HarnessKind = .claude, model: String? = nil, projectID: UUID? = nil,
        isHeadMaster: Bool = false, sortIndex: Int = 0, createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.instructions = instructions
        self.avatar = avatar
        self.harness = harness
        self.model = model
        self.projectID = projectID
        self.isHeadMaster = isHeadMaster
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

/// What an agent is doing, from its chats.
public enum AgentStatus: Equatable, Sendable {
    case idle
    /// A turn is running; `activity` is the tool in use or the start of what it's writing.
    case working(activity: String?, since: Date)
    /// Finished recently and not looked at yet.
    case done

    public var isWorking: Bool { if case .working = self { true } else { false } }
}

// MARK: - AgentAvatar

/// An original pixel-art chibi, as a choice per part. Drawn by `AvatarSprite` in the UI.
public struct AgentAvatar: Codable, Equatable, Hashable, Sendable {
    public var skin = 0
    public var hair = 0
    public var hairColor = 0
    public var eyes = 0
    public var outfit = 0
    public var outfitColor = 0
    public var accessory = 0

    public enum Part: String, CaseIterable, Sendable {
        case skin, hair, hairColor, eyes, outfit, outfitColor, accessory

        /// How many choices the sprite draws for this part.
        public var count: Int {
            switch self {
            case .skin: 6
            case .hair: 9
            case .hairColor: 10
            case .eyes: 6
            case .outfit: 7
            case .outfitColor: 10
            case .accessory: 8
            }
        }

        public var title: String {
            switch self {
            case .skin: String(localized: "Skin")
            case .hair: String(localized: "Hair")
            case .hairColor: String(localized: "Hair colour")
            case .eyes: String(localized: "Eyes")
            case .outfit: String(localized: "Outfit")
            case .outfitColor: String(localized: "Outfit colour")
            case .accessory: String(localized: "Accessory")
            }
        }
    }

    public init(skin: Int = 0, hair: Int = 0, hairColor: Int = 0, eyes: Int = 0, outfit: Int = 0,
                outfitColor: Int = 0, accessory: Int = 0) {
        self.skin = skin
        self.hair = hair
        self.hairColor = hairColor
        self.eyes = eyes
        self.outfit = outfit
        self.outfitColor = outfitColor
        self.accessory = accessory
    }

    public subscript(part: Part) -> Int {
        get {
            switch part {
            case .skin: skin
            case .hair: hair
            case .hairColor: hairColor
            case .eyes: eyes
            case .outfit: outfit
            case .outfitColor: outfitColor
            case .accessory: accessory
            }
        }
        set {
            let value = ((newValue % part.count) + part.count) % part.count
            switch part {
            case .skin: skin = value
            case .hair: hair = value
            case .hairColor: hairColor = value
            case .eyes: eyes = value
            case .outfit: outfit = value
            case .outfitColor: outfitColor = value
            case .accessory: accessory = value
            }
        }
    }

    public mutating func step(_ part: Part, by delta: Int) { self[part] += delta }

    public static func random(using rng: inout some RandomNumberGenerator) -> AgentAvatar {
        var avatar = AgentAvatar()
        for part in Part.allCases { avatar[part] = Int.random(in: 0..<part.count, using: &rng) }
        return avatar
    }

    public static func random() -> AgentAvatar {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }

    enum CodingKeys: String, CodingKey { case skin, hair, hairColor, eyes, outfit, outfitColor, accessory }

    /// Missing parts are the first choice and out-of-range ones wrap, so an avatar saved by another
    /// version of xBot always draws.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for part in Part.allCases {
            let key = CodingKeys(rawValue: part.rawValue)!
            self[part] = (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0
        }
    }
}

// MARK: - Hand-offs

/// HeadMaster giving work to a crew member, written in its reply as a fenced `handoff` block.
public struct Handoff: Equatable, Sendable {
    public var to: String
    public var task: String

    public init(to: String, task: String) {
        self.to = to
        self.task = task
    }

    /// The reply as a person reads it: the blocks are for xBot, and show as hand-off cards instead.
    public static func stripping(_ text: String) -> String {
        var kept: [String] = []
        var inside = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inside, trimmed.hasPrefix("```"), trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() == "handoff" {
                inside = true
                continue
            }
            if inside {
                if trimmed.hasPrefix("```") { inside = false }
                continue
            }
            kept.append(line)
        }
        var result = kept.joined(separator: "\n")
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The notices in HeadMaster's chat, which the chat shows as cards with the member's face.
    public static func handedPrefix(_ name: String) -> String { String(localized: "Handed to \(name): ") }
    public static func finishedPrefix(_ name: String) -> String { String(localized: "\(name) finished: ") }

    public static func all(in text: String) -> [Handoff] {
        var found: [Handoff] = []
        var inside = false
        var to: String?
        var task: [String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !inside {
                if line.hasPrefix("```") && line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() == "handoff" {
                    inside = true
                    to = nil
                    task = nil
                }
                continue
            }
            if line.hasPrefix("```") {
                inside = false
                let body = (task ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if let name = to, !name.isEmpty, !body.isEmpty { found.append(Handoff(to: name, task: body)) }
                continue
            }
            if task != nil {
                task?.append(raw)
            } else if line.lowercased().hasPrefix("to:") {
                to = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().hasPrefix("task:") {
                task = [line.dropFirst(5).trimmingCharacters(in: .whitespaces)]
            }
        }
        return found
    }
}

// MARK: - The founding crew

extension Agent {
    /// The world xBot starts with: HeadMaster and three. Seeded once, by the store's migration.
    static func foundingCrew(now: Date = .now) -> [Agent] {
        [
            Agent(
                name: "HeadMaster",
                role: String(localized: "Founder and orchestrator of the crew"),
                instructions: """
                    You founded this workplace and you are responsible for it. Take the big asks: \
                    understand what is really wanted, think creatively about the best way to get there, \
                    make a short plan, and decide who does what. Do small things yourself. Hand larger \
                    parts to the crew member whose role fits, with a clear, self-contained task: what to \
                    do, where, and what "done" looks like. Be honest about risks and trade-offs, keep the \
                    person informed, and never claim work is finished before it is.
                    """,
                avatar: AgentAvatar(skin: 1, hair: 6, hairColor: 8, eyes: 2, outfit: 5, outfitColor: 7, accessory: 4),
                isHeadMaster: true, sortIndex: 0, createdAt: now
            ),
            Agent(
                name: "Forge",
                role: String(localized: "Builder: features end to end"),
                instructions: """
                    You build. Read the code around the change first, then work test first: a failing \
                    test, the smallest change that passes it, then tidy up. Run the tests and the build \
                    before saying you're done, and report what you changed, what you verified, and what \
                    is left.
                    """,
                avatar: AgentAvatar(skin: 3, hair: 2, hairColor: 2, eyes: 0, outfit: 2, outfitColor: 1, accessory: 2),
                sortIndex: 1, createdAt: now
            ),
            Agent(
                name: "Hawk",
                role: String(localized: "Reviewer: bugs, risks, missing tests"),
                instructions: """
                    You review; you don't edit files. Read the changes (git diff, or what you are pointed \
                    at) and look for real problems: bugs, edge cases, security issues, missing tests, \
                    confusing names. Rank them by how much they matter, quote the lines, and suggest the \
                    fix. Say plainly when something is good.
                    """,
                avatar: AgentAvatar(skin: 0, hair: 4, hairColor: 0, eyes: 3, outfit: 3, outfitColor: 4, accessory: 1),
                sortIndex: 2, createdAt: now
            ),
            Agent(
                name: "Quill",
                role: String(localized: "Scribe: ideas and release notes"),
                instructions: """
                    You keep the project's notes, in its notes/ folder as markdown: ideas, decisions, and \
                    the next release notes. Read the recent git history and the existing notes, then write \
                    for people, not machines: what changed, why it matters, in plain words. Keep one \
                    running file for the next release, and don't touch code.
                    """,
                avatar: AgentAvatar(skin: 2, hair: 7, hairColor: 5, eyes: 4, outfit: 1, outfitColor: 3, accessory: 6),
                sortIndex: 3, createdAt: now
            ),
        ]
    }
}
