import SwiftUI
import XBotCore

/// The Agents page's map: a little MapleStory-like world where the crew wanders about, walks to
/// a desk to work, and says what it's doing. Click someone to open their chat.
struct WorkplaceScene: View {
    let workspace: Workspace
    var edit: (Agent) -> Void = { _ in }
    @State private var model = WorldModel()
    @State private var hovered: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 320
    static let ground: CGFloat = 74
    static let pixel: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                let agents = workspace.agents
                let statuses = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, workspace.status(of: $0.id)) })
                let world = model.advance(to: context.date, width: width, ids: agents.map(\.id),
                                          working: Set(statuses.filter { $0.value.isWorking }.map(\.key)),
                                          moving: !reduceMotion)
                let floor = Self.height - Self.ground
                ZStack(alignment: .topLeading) {
                    Scenery(date: context.date, width: width)
                    ForEach(agents) { agent in
                        if let walker = world.walkers[agent.id] {
                            let desk = world.desk(of: agent.id)
                            Desk(working: statuses[agent.id]?.isWorking == true, date: context.date)
                                .position(x: desk + 40, y: floor - 40)
                                .zIndex(walker.pose == .sitting ? 1.5 : 0)
                            Chair().position(x: desk - 2, y: floor - 20)
                            figure(agent, walker, status: statuses[agent.id] ?? .idle, date: context.date,
                                   tagDrop: Self.tagDrop(agent.id, in: world, order: agents.map(\.id)))
                                .position(x: walker.x, y: floor - 50 - (walker.pose == .sitting ? 10 : 0))
                                .zIndex(hovered == agent.id ? 2 : 1)
                        }
                    }
                }
                .frame(width: width, height: Self.height)
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "The workplace"))
    }

    /// Name tags of people standing close drop one below the other instead of overlapping.
    static func tagDrop(_ id: UUID, in world: WorkplaceWorld, order: [UUID]) -> CGFloat {
        guard let me = world.walkers[id], let index = order.firstIndex(of: id) else { return 0 }
        let crowd = order.prefix(index).filter { other in
            world.walkers[other].map { abs($0.x - me.x) < 64 } ?? false
        }.count
        return CGFloat(crowd % 3) * 17
    }

    private func figure(_ agent: Agent, _ walker: WorkplaceWorld.Walker, status: AgentStatus, date: Date,
                        tagDrop: CGFloat) -> some View {
        let legs: AvatarSprite.Legs = switch walker.pose {
        case .walking: .stride
        case .sitting: .sit
        case .standing: .stand
        }
        let seed = agent.id.hashValue
        let frame = LivingAvatar.frame(at: date, seed: seed, legs: legs, talking: status.isWorking, headOnly: false)
        return AvatarSprite(avatar: agent.avatar, frame: frame, pixel: Self.pixel)
            .scaleEffect(x: walker.facing, y: 1)
            .overlay(alignment: .bottom) {
                NameTag(name: agent.name, crown: agent.isHeadMaster, highlighted: hovered == agent.id)
                    .fixedSize()
                    .offset(y: 24 + tagDrop)
            }
            .overlay(alignment: .top) {
                if let line = Self.bubble(status, agent: agent, date: date, seed: seed) {
                    SpeechBubble(text: line, emphasis: status.isWorking)
                        .fixedSize()
                        .offset(y: -30)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? agent.id : (hovered == agent.id ? nil : hovered) }
            .onTapGesture { workspace.openLatestChat(with: agent.id) }
            .contextMenu {
                Button(String(localized: "New chat with \(agent.name)")) { workspace.talk(to: agent.id) }
                Button(String(localized: "Edit \(agent.name)…")) { edit(agent) }
            }
            .help(agent.role)
            .accessibilityElement()
            .accessibilityLabel("\(agent.name), \(Self.describe(status))")
            .accessibilityAddTraits(.isButton)
    }

    /// What someone says: what they're doing while working; now and then, something idle.
    static func bubble(_ status: AgentStatus, agent: Agent, date: Date, seed: Int) -> String? {
        switch status {
        case .working(let activity, _): return activity ?? String(localized: "Thinking…")
        case .done: return String(localized: "Done! ✓")
        case .idle:
            let t = date.timeIntervalSinceReferenceDate + Double(abs(seed % 1000))
            let cycle = 14 + Double(abs(seed % 7))
            guard t.truncatingRemainder(dividingBy: cycle) < 2.4 else { return nil }
            let hour = Calendar.current.component(.hour, from: date)
            let emotes = hour >= 23 || hour < 6 ? ["zZ", "…", "☕"] : ["♪", "…", "☕", "!", "♥", "?"]
            return emotes[Int(t / cycle) % emotes.count]
        }
    }

    static func describe(_ status: AgentStatus) -> String {
        switch status {
        case .working(let activity, _): activity ?? String(localized: "Working")
        case .done: String(localized: "Done")
        case .idle: String(localized: "Idle")
        }
    }
}

/// Holds the world between frames. Advanced from the view's clock, not observed: the clock redraws.
@MainActor
final class WorldModel {
    private var world = WorkplaceWorld(width: 900, seed: UInt64(Date.now.timeIntervalSince1970))
    private var last: Date?

    func advance(to date: Date, width: Double, ids: [UUID], working: Set<UUID>, moving: Bool) -> WorkplaceWorld {
        world.resize(width)
        if ids != world.order { world.sync(ids) }
        let dt = min(max(date.timeIntervalSince(last ?? date), 0), 0.1)
        last = date
        if moving {
            world.step(dt, working: working)
        } else if !working.isEmpty {
            // Reduce Motion: no wandering; working agents are simply at their desks.
            world.step(30, working: working)
        }
        return world
    }
}

// MARK: - Pieces

private struct NameTag: View {
    let name: String
    let crown: Bool
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 3) {
            if crown { Text(verbatim: "♛").foregroundStyle(AvatarPalette.gold) }
            Text(name)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(highlighted ? 0.85 : 0.6)))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(highlighted ? AvatarPalette.gold : .clear, lineWidth: 1))
    }
}

/// White, pixel-bordered, with a little tail: MapleStory's chat balloon.
private struct SpeechBubble: View {
    let text: String
    let emphasis: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 10.5, weight: emphasis ? .medium : .bold, design: .rounded))
                .foregroundStyle(Color(hex: "2A2533"))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 170)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Rectangle().fill(.white))
                .overlay(Rectangle().strokeBorder(Color(hex: "2A2533"), lineWidth: 1.5))
            Path { p in
                p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 8, y: 0)); p.addLine(to: .init(x: 4, y: 5)); p.closeSubpath()
            }
            .fill(Color(hex: "2A2533"))
            .frame(width: 8, height: 5)
        }
        .shadow(color: .black.opacity(0.15), radius: 0, x: 2, y: 2)
    }
}

private struct Desk: View {
    let working: Bool
    let date: Date

    var body: some View {
        Canvas { context, _ in
            let px: CGFloat = 4
            func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x * px, y: y * px, width: w * px, height: h * px)), with: .color(color))
            }
            let wood = Color(hex: "B8794A"), dark = Color(hex: "7A4B2A"), outline = AvatarPalette.outline
            // Monitor, facing the chair.
            block(3, 0, 10, 8, outline)
            block(4, 1, 8, 6, working ? Color(hex: "1E2B4A") : Color(hex: "3A3F4B"))
            if working {
                let tick = Int(date.timeIntervalSinceReferenceDate * 4)
                for line in 0..<3 {
                    let width = CGFloat(2 + (tick + line * 3) % 5)
                    block(5, CGFloat(2 + line * 2) - 0.5, width, 1, [Color(hex: "7CF29A"), Color(hex: "6DB6FF"), Color(hex: "FFD551")][line])
                }
            }
            block(7, 8, 2, 2, outline)
            // Desk top and legs.
            block(0, 10, 18, 1, outline)
            block(0, 11, 18, 2, wood)
            block(0, 13, 18, 1, dark)
            block(1, 14, 2, 6, dark)
            block(15, 14, 2, 6, dark)
        }
        .frame(width: 72, height: 80)
        .accessibilityHidden(true)
    }
}

private struct Chair: View {
    var body: some View {
        Canvas { context, _ in
            let px: CGFloat = 4
            func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x * px, y: y * px, width: w * px, height: h * px)), with: .color(color))
            }
            block(0, 0, 2, 6, Color(hex: "5B3A26"))
            block(0, 5, 9, 2, Color(hex: "7A4B2A"))
            block(1, 7, 1, 3, Color(hex: "5B3A26"))
            block(7, 7, 1, 3, Color(hex: "5B3A26"))
        }
        .frame(width: 36, height: 40)
        .accessibilityHidden(true)
    }
}

/// Sky, sun or moon, clouds, hills, mushroom houses and the ground, in big pixels.
private struct Scenery: View {
    let date: Date
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            let hour = Double(Calendar.current.component(.hour, from: date)) + Double(Calendar.current.component(.minute, from: date)) / 60
            let sky = Self.sky(hour)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let night = hour < 6 || hour >= 20
            let px: CGFloat = 4
            func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
            }
            // Stars, or the sun.
            if night {
                for i in 0..<40 {
                    let x = CGFloat((i * 7919) % Int(max(size.width, 1)))
                    let y = CGFloat((i * 104_729) % 150)
                    let twinkle = (Int(date.timeIntervalSinceReferenceDate * 2) + i) % 7 == 0
                    block(x, y, twinkle ? 3 : 2, twinkle ? 3 : 2, .white.opacity(twinkle ? 1 : 0.7))
                }
                block(size.width * 0.82, 30, 28, 28, Color(hex: "FFF6D5"))
                block(size.width * 0.82 + 10, 26, 24, 24, sky[0])
            } else {
                let x = size.width * 0.84
                block(x - 4, 28, 40, 32, Color(hex: "FFE58A").opacity(0.5))
                block(x, 24, 32, 40, Color(hex: "FFE58A").opacity(0.5))
                block(x, 28, 32, 32, Color(hex: "FFD44D"))
            }
            // Clouds drifting right.
            let cloud = ["..WWW.....", ".WWWWWW.WW", "WWWWWWWWWW", ".WWWWWWWW."]
            for i in 0..<4 {
                let speed = 6.0 + Double(i) * 2.5
                let span = Double(size.width) + 200
                let x = CGFloat((date.timeIntervalSinceReferenceDate * speed + Double(i) * 377).truncatingRemainder(dividingBy: span)) - 100
                let y = CGFloat(18 + (i * 37) % 90)
                for (r, row) in cloud.enumerated() {
                    for (c, ch) in row.enumerated() where ch == "W" {
                        block(x + CGFloat(c) * px * 1.5, y + CGFloat(r) * px * 1.5, px * 1.5, px * 1.5, .white.opacity(night ? 0.18 : 0.85))
                    }
                }
            }
            let floor = size.height - WorkplaceScene.ground
            // Two rows of stepped hills.
            for (layer, color) in [(0, Color(hex: night ? "2D3A5C" : "9ED8A6")), (1, Color(hex: night ? "26324F" : "6CC17E"))] {
                let base = floor - CGFloat(layer == 0 ? 40 : 14)
                var x: CGFloat = 0
                while x < size.width {
                    let wave = sin(Double(x) / (layer == 0 ? 120 : 80) + Double(layer) * 2) * 0.5 + 0.5
                    let h = CGFloat(wave) * (layer == 0 ? 70 : 40) + 20
                    block(x, base - h, 8, h + 60, color)
                    x += 8
                }
            }
            // Mushroom houses, Henesys-style.
            let house = [
                "....RRRRRR....",
                "..RRWWRRRRRR..",
                ".RRRWWRRRWWRR.",
                "RRRRRRRRRWWRRR",
                "RRWWRRRRRRRRRR",
                "RRWWRRRRRRWWRR",
                ".DDDDDDDDDDDD.",
                "...CCCCCCCC...",
                "...CBBCCCCC...",
                "...CBBCCDDC...",
                "...CCCCCDDC...",
                "...CCCCCDDC...",
            ]
            let colors: [Character: Color] = [
                "R": Color(hex: "F0793A"), "W": Color(hex: "FFF3E0"), "D": Color(hex: "B8552A"),
                "C": Color(hex: "FFE8C2"), "B": night ? Color(hex: "FFE27A") : Color(hex: "7FB8E8"),
            ]
            for (i, fraction) in [0.08, 0.5, 0.93].enumerated() where size.width > 500 || i != 1 {
                let scale: CGFloat = i == 1 ? 3 : 4
                let x0 = size.width * fraction - 7 * scale
                let y0 = floor - 12 * scale + 2
                for (r, row) in house.enumerated() {
                    for (c, ch) in row.enumerated() {
                        if let color = colors[ch] { block(x0 + CGFloat(c) * scale, y0 + CGFloat(r) * scale, scale, scale, color) }
                    }
                }
            }
            // Ground: jagged grass over dirt with pebbles.
            block(0, floor, size.width, size.height - floor, Color(hex: "9A6A43"))
            var x: CGFloat = 0
            var i = 0
            while x < size.width {
                let tuft: CGFloat = i % 3 == 0 ? 6 : (i % 5 == 0 ? 3 : 0)
                block(x, floor - tuft, 6, 14 + tuft, Color(hex: night ? "3E7A4F" : "5DBB63"))
                block(x, floor + 14, 6, 4, Color(hex: night ? "2F5E3C" : "3F9A4C"))
                x += 6
                i += 1
            }
            for j in 0..<Int(size.width / 18) {
                let px = CGFloat((j * 7_919) % Int(max(size.width, 1)))
                let py = floor + 26 + CGFloat((j * 31) % Int(WorkplaceScene.ground - 32))
                block(px, py, 6, 4, Color(hex: "7D5434"))
            }
        }
        .accessibilityHidden(true)
    }

    static func sky(_ hour: Double) -> [Color] {
        switch hour {
        case 6..<8: [Color(hex: "FFB38A"), Color(hex: "FFE3C2")]
        case 8..<17: [Color(hex: "7CC8FF"), Color(hex: "DDF2FF")]
        case 17..<20: [Color(hex: "FF8E6B"), Color(hex: "FFD3A1")]
        default: [Color(hex: "151B3D"), Color(hex: "39407A")]
        }
    }
}
