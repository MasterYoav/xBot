import Foundation

/// The Agents page's little map: where each agent stands, which way it faces, whether it's
/// walking, standing about, or sitting at its desk. Advanced by the view's clock; drawn by the UI.
public struct WorkplaceWorld: Sendable {
    public enum Pose: Equatable, Sendable { case standing, walking, sitting }

    public struct Walker: Equatable, Sendable {
        public var x: Double
        public var pose: Pose = .standing
        /// 1 facing right, -1 facing left.
        public var facing: Double = 1
        /// Seconds into the walking cycle, for the legs.
        public var stride: Double = 0
        var target: Double?
        var rest: Double = 0
    }

    public private(set) var width: Double
    public let margin: Double = 44
    public private(set) var walkers: [UUID: Walker] = [:]
    public private(set) var order: [UUID] = []
    /// Where each one lives in the org chart: their desk, and how far they stroll from it.
    public struct Slot: Equatable, Sendable {
        public var home: Double
        public var range: Double
        public init(home: Double, range: Double) { self.home = home; self.range = range }
    }
    public private(set) var slots: [UUID: Slot] = [:]
    private var rng: Generator

    public init(width: Double, seed: UInt64 = 1) {
        self.width = max(width, 200)
        rng = Generator(seed: seed)
    }

    /// The crew, in order: newcomers appear at a random spot, the departed leave.
    public mutating func sync(_ ids: [UUID]) {
        order = ids
        // Each newcomer starts near its own desk, so the crew starts spread out, not in a huddle.
        for id in ids where walkers[id] == nil {
            if let slot = slots[id] {
                walkers[id] = Walker(x: slot.home + Double.random(in: -slot.range...slot.range, using: &rng),
                                     facing: Bool.random(using: &rng) ? 1 : -1, rest: Double.random(in: 0.2...2.5, using: &rng))
                continue
            }
            let x = min(max(desk(of: id) + Double.random(in: -50...50, using: &rng), margin), width - margin)
            walkers[id] = Walker(x: x, facing: Bool.random(using: &rng) ? 1 : -1,
                                 rest: Double.random(in: 0.2...2.5, using: &rng))
        }
        for id in walkers.keys where !ids.contains(id) { walkers[id] = nil }
    }

    public mutating func resize(_ newWidth: Double) {
        let newWidth = max(newWidth, 200)
        guard newWidth != width else { return }
        // In slots, everyone keeps to their own: nothing to stretch.
        if !slots.isEmpty { width = newWidth; return }
        let scale = (newWidth - 2 * margin) / (width - 2 * margin)
        width = newWidth
        for id in walkers.keys {
            walkers[id]!.x = margin + (walkers[id]!.x - margin) * scale
            walkers[id]!.target = walkers[id]!.target.map { margin + ($0 - margin) * scale }
        }
    }

    /// Places everyone in their slot; someone whose slot moved walks over to it.
    public mutating func arrange(_ new: [UUID: Slot]) {
        guard new != slots else { return }
        slots = new
        for (id, slot) in new {
            guard var walker = walkers[id] else { continue }
            if abs(walker.x - slot.home) > slot.range + 0.5 {
                walker.target = slot.home
                walker.rest = 0
            }
            walkers[id] = walker
        }
    }

    /// Each agent's desk: their slot's centre, else spread evenly along the floor, in crew order.
    public func desk(of id: UUID) -> Double {
        if let slot = slots[id] { return slot.home }
        let index = Double(order.firstIndex(of: id) ?? 0)
        let span = (width - 2 * margin) / Double(max(order.count, 1))
        return margin + span * (index + 0.5)
    }

    public mutating func step(_ dt: Double, working: Set<UUID>) {
        for id in order {
            guard var walker = walkers[id] else { continue }
            if working.contains(id) {
                let desk = desk(of: id)
                if abs(walker.x - desk) < 0.5 {
                    walker.x = desk
                    walker.pose = .sitting
                    walker.facing = 1
                    walker.target = nil
                } else {
                    walk(&walker, to: desk, speed: 90, dt: dt)
                }
            } else {
                if walker.pose == .sitting {
                    walker.pose = .standing
                    walker.rest = Double.random(in: 0.6...1.6, using: &rng)
                }
                if walker.rest > 0 {
                    walker.rest -= dt
                    walker.pose = .standing
                } else if let target = walker.target {
                    walk(&walker, to: target, speed: 42, dt: dt)
                    if walker.x == target {
                        walker.target = nil
                        walker.pose = .standing
                        walker.rest = Double.random(in: 1.5...5.5, using: &rng)
                        // Sometimes look the other way while standing about.
                        if Double.random(in: 0...1, using: &rng) < 0.3 { walker.facing *= -1 }
                    }
                } else if let slot = slots[id] {
                    // A stroll near their own desk.
                    walker.target = slot.home + Double.random(in: -slot.range...slot.range, using: &rng)
                } else {
                    // Somewhere new, not where someone else is standing or heading.
                    let others = order.filter { $0 != id }.compactMap { walkers[$0] }.map { $0.target ?? $0.x }
                    var target = walker.x
                    for _ in 0..<6 {
                        let reach = Double.random(in: 60...260, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
                        target = min(max(walker.x + reach, margin), width - margin)
                        if others.allSatisfy({ abs($0 - target) > 70 }) { break }
                    }
                    walker.target = target
                }
            }
            walkers[id] = walker
        }
    }

    private func walk(_ walker: inout Walker, to target: Double, speed: Double, dt: Double) {
        let distance = target - walker.x
        let move = speed * dt
        walker.pose = .walking
        walker.facing = distance < 0 ? -1 : 1
        walker.stride += dt
        walker.x = abs(distance) <= move ? target : walker.x + move * walker.facing
    }

    /// xorshift: a world with the same seed plays the same way, which the tests rely on.
    struct Generator: RandomNumberGenerator, Sendable {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed &* 0x2545_F491_4F6C_DD1D }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }
}

/// Where the crew lives. Chosen on the Agents page and remembered.
public enum WorkplaceSetting: String, CaseIterable, Sendable {
    /// Mushroom houses, grass and desks.
    case village
    /// High above the clouds among planets and rainbows; the crew rides golden clouds.
    case skyRealm
    case underwater
    case moonbase
    case enchantedForest

    public var title: String {
        switch self {
        case .village: String(localized: "Village")
        case .skyRealm: String(localized: "Sky Realm")
        case .underwater: String(localized: "Underwater Kingdom")
        case .moonbase: String(localized: "Moonbase")
        case .enchantedForest: String(localized: "Enchanted Forest")
        }
    }

    public var symbol: String {
        switch self {
        case .village: "house"
        case .skyRealm: "cloud.sun"
        case .underwater: "water.waves"
        case .moonbase: "moon.stars"
        case .enchantedForest: "tree"
        }
    }
}
