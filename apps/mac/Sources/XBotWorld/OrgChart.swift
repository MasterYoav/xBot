import Foundation

/// Who reports to whom. HeadMaster is the CEO and reports to the person; everyone else reports to
/// a manager on the crew (nil: to HeadMaster). The person decides; `suggestedManager` proposes what
/// most companies do, from each role's title: executives under the CEO, leads under their
/// executive, everyone else under their department's lead or executive.
public enum OrgChart {
    public struct Member: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var role: String
        public var isHeadMaster: Bool
        /// Nil: HeadMaster (or, for HeadMaster, the person).
        public var managerID: UUID?

        public init(id: UUID, name: String, role: String, isHeadMaster: Bool, managerID: UUID?) {
            self.id = id
            self.name = name
            self.role = role
            self.isHeadMaster = isHeadMaster
            self.managerID = managerID
        }
    }

    public enum Department: String, CaseIterable, Sendable {
        case engineering, product, finance, marketing, operations, general
    }

    public enum Rank: Int, Comparable, Sendable {
        case ceo, executive, lead, member
        public static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Position: Equatable, Sendable {
        public var department: Department
        public var rank: Rank
    }

    // MARK: Reading a role

    private static let keywords: [(Department, [String])] = [
        (.product, ["product", "cpo", "designer", "design", "ux", "ui ", "research", "planner", "pm"]),
        (.engineering, ["cto", "engineer", "developer", "dev", "programmer", "coder", "builder", "architect", "tester", "qa",
                        "test", "devops", "sre", "infrastructure", "security", "reviewer", "refactor", "backend", "frontend",
                        "ios", "android", "mobile", "technical", "technology", "software", "code"]),
        (.finance, ["cfo", "finance", "financial", "accountant", "accounting", "analyst", "data", "billing", "treasury"]),
        (.marketing, ["cmo", "marketing", "growth", "brand", "content", "writer", "copy", "scribe", "docs", "documentation",
                      "translator", "localis", "localiz", "social", "seo", "community", "sales"]),
        (.operations, ["coo", "operations", "ops", "support", "hr", "people", "recruit", "legal", "admin", "assistant"]),
    ]

    private static func words(_ role: String) -> [String] {
        role.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The department and rank a role's title suggests.
    public static func position(of role: String) -> Position {
        let lower = " " + role.lowercased() + " "
        let words = Set(words(role))
        func has(_ key: String) -> Bool {
            key.contains(" ") ? lower.contains(" " + key) : words.contains(key) || (key.count > 4 && lower.contains(key))
        }
        if has("ceo") || has("founder") || lower.contains("chief executive") || has("orchestrator") {
            return Position(department: .general, rank: .ceo)
        }
        // "Chief Product Officer" is product even though "officer"… check exact C-titles first.
        let titles: [(String, Department)] = [("cto", .engineering), ("cpo", .product), ("cfo", .finance), ("cmo", .marketing),
                                              ("coo", .operations)]
        for (title, department) in titles where words.contains(title) { return Position(department: department, rank: .executive) }
        var department = Department.general
        for (candidate, keys) in keywords where keys.contains(where: has) {
            department = candidate
            break
        }
        let executive = lower.contains("chief ") || words.contains("vp") || lower.contains("vice president")
            || lower.contains("head of") || lower.contains("director")
        if executive {
            if lower.contains("chief") {
                if lower.contains("techn") { department = .engineering }
                if lower.contains("financ") { department = .finance }
                if lower.contains("market") { department = .marketing }
                if lower.contains("operat") { department = .operations }
                if lower.contains("product") { department = .product }
            }
            return Position(department: department, rank: .executive)
        }
        let lead = words.contains("lead") || words.contains("manager") || words.contains("principal") || words.contains("staff")
        // A product manager is the product team's member, not a lead over it.
        if lead && !(department == .product && words.contains("product") && words.contains("manager")) {
            return Position(department: department, rank: .lead)
        }
        return Position(department: department, rank: .member)
    }

    /// Where most companies would put someone with this role, given who's on the crew. Nil: the
    /// person (for HeadMaster) — everyone else gets an id.
    public static func suggestedManager(role: String, id: UUID?, among members: [Member]) -> UUID? {
        guard let ceo = members.first(where: \.isHeadMaster) else { return nil }
        if let id, id == ceo.id { return nil }
        let me = position(of: role)
        let others = members.filter { $0.id != id && !$0.isHeadMaster }.map { ($0, position(of: $0.role)) }
        func find(_ department: Department, _ rank: Rank) -> UUID? {
            others.first { $0.1.department == department && $0.1.rank == rank }?.0.id
        }
        switch me.rank {
        case .ceo, .executive:
            return ceo.id
        case .lead:
            return find(me.department, .executive) ?? (me.department == .product ? find(.engineering, .executive) : nil) ?? ceo.id
        case .member:
            if me.department == .general { return ceo.id }
            if let lead = find(me.department, .lead) { return lead }
            if let executive = find(me.department, .executive) { return executive }
            // Product sits with engineering when there's no product leadership.
            if me.department == .product { return find(.engineering, .lead) ?? find(.engineering, .executive) ?? ceo.id }
            return ceo.id
        }
    }

    /// True if putting `id` under `manager` would make someone their own manager.
    public static func wouldLoop(_ id: UUID, under manager: UUID?, in members: [Member]) -> Bool {
        guard let manager else { return false }
        let byID = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var current: UUID? = manager
        var seen: Set<UUID> = []
        while let step = current, seen.insert(step).inserted {
            if step == id { return true }
            current = byID[step]?.managerID
        }
        return false
    }

    // MARK: The tree

    public struct Tree: Sendable {
        /// Level 0 is HeadMaster; each level in order, children after their manager's order.
        public let levels: [[Member]]
        let parent: [UUID: UUID]
        let children: [UUID: [UUID]]

        /// Their manager in the tree (nil for the top).
        public func manager(of id: UUID) -> UUID? { parent[id] }
        public func reports(of id: UUID) -> [UUID] { children[id] ?? [] }

        /// Everyone under them, at any depth.
        public func below(_ id: UUID) -> [UUID] {
            var out: [UUID] = []
            var queue = children[id] ?? []
            while !queue.isEmpty {
                let next = queue.removeFirst()
                out.append(next)
                queue += children[next] ?? []
            }
            return out
        }
    }

    /// The crew as a tree, in their order. A missing or looping manager means HeadMaster.
    public static func tree(_ members: [Member]) -> Tree {
        guard let root = members.first(where: \.isHeadMaster) ?? members.first else {
            return Tree(levels: [], parent: [:], children: [:])
        }
        let ids = Set(members.map(\.id))
        var parent: [UUID: UUID] = [:]
        for member in members where member.id != root.id {
            var manager = member.managerID.flatMap { ids.contains($0) && $0 != member.id ? $0 : nil } ?? root.id
            if manager != root.id, wouldLoop(member.id, under: manager, in: members) { manager = root.id }
            parent[member.id] = manager
        }
        // Loops among others (A under B under A) never reach the root: hang them on it.
        for member in members where member.id != root.id {
            var step: UUID? = member.id
            var seen: Set<UUID> = []
            while let current = step, current != root.id, seen.insert(current).inserted { step = parent[current] }
            if step != root.id { parent[member.id] = root.id }
        }
        var children: [UUID: [UUID]] = [:]
        for member in members where member.id != root.id { children[parent[member.id]!, default: []].append(member.id) }
        let byID = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var levels: [[Member]] = [[root]]
        while let last = levels.last {
            let next = last.flatMap { children[$0.id] ?? [] }.compactMap { byID[$0] }
            if next.isEmpty { break }
            levels.append(next)
        }
        return Tree(levels: levels, parent: parent, children: children)
    }

    public struct Layout: Sendable {
        /// Centre of each member's slot, from 0.
        public var x: [UUID: Double]
        public var depth: [UUID: Int]
        /// Slots across the widest part.
        public var width: Double
        public var levels: Int
    }

    /// Each leaf gets a slot; a manager sits centred over its reports.
    public static func layout(_ tree: Tree, slot: Double) -> Layout {
        var x: [UUID: Double] = [:]
        var depth: [UUID: Int] = [:]
        var next = 0.0
        func place(_ id: UUID, _ level: Int) {
            depth[id] = level
            let kids = tree.reports(of: id)
            if kids.isEmpty {
                x[id] = next + slot / 2
                next += slot
            } else {
                for kid in kids { place(kid, level + 1) }
                x[id] = (x[kids.first!]! + x[kids.last!]!) / 2
            }
        }
        if let root = tree.levels.first?.first { place(root.id, 0) }
        return Layout(x: x, depth: depth, width: next, levels: tree.levels.count)
    }
}
