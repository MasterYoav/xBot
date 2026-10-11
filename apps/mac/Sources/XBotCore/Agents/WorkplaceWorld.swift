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
            let x = min(max(desk(of: id) + Double.random(in: -50...50, using: &rng), margin), width - margin)
            walkers[id] = Walker(x: x, facing: Bool.random(using: &rng) ? 1 : -1,
                                 rest: Double.random(in: 0.2...2.5, using: &rng))
        }
        for id in walkers.keys where !ids.contains(id) { walkers[id] = nil }
    }

    public mutating func resize(_ newWidth: Double) {
        let newWidth = max(newWidth, 200)
        guard newWidth != width else { return }
        let scale = (newWidth - 2 * margin) / (width - 2 * margin)
        width = newWidth
        for id in walkers.keys {
            walkers[id]!.x = margin + (walkers[id]!.x - margin) * scale
            walkers[id]!.target = walkers[id]!.target.map { margin + ($0 - margin) * scale }
        }
    }

    /// Each agent's desk: spread evenly along the floor, in crew order.
    public func desk(of id: UUID) -> Double {
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
