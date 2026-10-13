import SwiftUI
import XBotWorld

/// Step 6, Your crew, organised like a company: HeadMaster on the top tier; a CTO is hired and
/// drops onto the tier below; Forge and Hawk walk in under them. HeadMaster hands a task down, the
/// CTO passes it on, the two work, and "Done" travels back up the same way.
struct CrewScene: View {
    var setting: WorkplaceSetting = .village

    init(setting: WorkplaceSetting = .village) { self.setting = setting }

    private enum Script {
        static let loop = 40.0
        static let ledge = 1.0
        static let hired = 1.4
        static let fall = 2.2
        static let land = 3.6
        static let walkIn = 3.8
        static let walkTakes = 3.2
        static let ask = 8.0
        static let handDown = 9.0
        static let handTakes = 2.0
        static let onIt = 11.0
        static let passDown = 12.0
        static let work = 14.0
        static let doneUp = 21.0
        static let doneUpTakes = 2.0
        static let reportUp = 24.0
        static let thanks = 26.4
        static let finalFrame = 34.0
    }

    private enum Layout {
        static let pixel: CGFloat = 3
        /// Feet on each tier, from the top of the 420 pt canvas.
        static let tiers: [CGFloat] = [138, 252, 366]
        static let ledge: CGFloat = 112
        static let pair: CGFloat = 104
    }

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat) { time in
            SceneStage { size in
                stage(time, size)
            }
        }
        .modifier(WorldFrame())
    }

    private func stage(_ time: SceneTime, _ size: CGSize) -> some View {
        let date = setting == .village ? time.worldDate(hour: 10) : time.date
        let mid = size.width / 2
        // The canvas grows taller in a taller room: keep the tiers above the ground.
        let drop = size.height - SceneMetrics.canvas.height
        let tiers = Layout.tiers.map { $0 + drop }
        let pixel = Layout.pixel
        let ledgeIn = Ease.spring(time.beat(Script.ledge, 1), bounce: 0.15)
        return ZStack(alignment: .topLeading) {
            WorldScenery(setting: setting, date: date, width: size.width)
                .frame(width: size.width, height: size.height)

            Ledge(width: Layout.ledge).position(x: mid, y: tiers[0] + 6)
            Ledge(width: Layout.ledge)
                .scaleEffect(x: ledgeIn, y: 1)
                .opacity(Ease.out(time.beat(Script.ledge, 0.5)))
                .position(x: mid, y: tiers[1] + 6)

            // HeadMaster, on top.
            ScenePerson(member: SceneCrew.headMaster, date: date, pixel: pixel,
                        talking: time.after(Script.ask) && !time.after(Script.handDown))
                .offset(y: -Ease.hop(time.beat(Script.thanks, 0.8)) * 10)
                .standing(at: mid, feet: tiers[0], pixel: pixel)

            Group {
                cto(time, x: mid, feet: tiers[1], date: date)
                walker(SceneCrew.forge, time, from: -50, to: mid - Layout.pair, feet: tiers[2], date: date)
                walker(SceneCrew.hawk, time, from: size.width + 50, to: mid + Layout.pair, feet: tiers[2], date: date)
                bubbles(time, mid: mid, tiers: tiers)
            }
            .opacity(time.seam)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// The CTO: a sparkle where they're hired, then a drop onto the empty tier, a squash on landing
    /// and a puff of dust.
    private func cto(_ time: SceneTime, x: CGFloat, feet: CGFloat, date: Date) -> some View {
        // A jump in from the right, MapleStory style: up in an arc, clear of HeadMaster, down onto the ledge.
        let jump = time.beat(Script.fall, Script.land - Script.fall)
        let squash = time.after(Script.land) ? 1 - Ease.spring(time.beat(Script.land, 0.8), bounce: 0.3) : 0
        let drift = Ease.lerp(330, 0, jump)
        let y = -CGFloat(Ease.hop(jump)) * 28
        let dust = time.beat(Script.land, 1.2)
        return ZStack {
            if time.after(Script.hired) && !time.after(Script.land + 2) {
                Sparkle(progress: time.beat(Script.hired, 1.6))
                    .position(x: x, y: feet - 70)
            }
            if time.after(Script.fall) {
                ScenePerson(member: SceneCrew.cto, date: date, facing: -1, pixel: Layout.pixel)
                    .scaleEffect(x: 1 + 0.12 * squash, y: 1 - 0.12 * squash, anchor: .bottom)
                    .offset(x: drift, y: y)
                    .standing(at: x, feet: feet, pixel: Layout.pixel)
            }
            if time.after(Script.land) && dust < 1 {
                Dust(progress: dust).position(x: x, y: feet - 2)
            }
        }
    }

    private func walker(_ member: SceneCrew.Member, _ time: SceneTime, from: CGFloat, to: CGFloat, feet: CGFloat,
                        date: Date) -> some View {
        let start = Script.walkIn + (member.seed == SceneCrew.hawk.seed ? 0.6 : 0)
        let walk = time.beat(start, Script.walkTakes)
        let x = Ease.lerp(from, to, walk < 0.8 ? walk / 0.8 * 0.9 : 0.9 + Ease.out((walk - 0.8) / 0.2) * 0.1)
        let arrived = walk >= 1
        let working = time.after(Script.work) && !time.after(Script.doneUp)
        // Facing the way they walk, which leaves them facing the middle when they stop.
        return ScenePerson(member: member, date: date, legs: arrived ? .stand : .stride, facing: to > from ? 1 : -1,
                           pixel: Layout.pixel, talking: working)
            .standing(at: x, feet: feet, pixel: Layout.pixel)
    }

    /// The speech: the ask, the task travelling down, the work, and "Done" travelling back up.
    @ViewBuilder
    private func bubbles(_ time: SceneTime, mid: CGFloat, tiers: [CGFloat]) -> some View {
        let head: (CGFloat) -> CGFloat = { $0 - 26 * Layout.pixel - Space.m }
        let task = String(localized: "Ship the sign-in fix")
        // HeadMaster says it…
        if time.after(Script.ask) && !time.after(Script.handDown) {
            SceneBubble(text: task)
                .scaleEffect(Ease.spring(time.beat(Script.ask, 0.6), bounce: 0.15), anchor: .bottom)
                .position(x: mid, y: head(tiers[0]))
        }
        // …and it travels down to the CTO…
        if time.after(Script.handDown) && !time.after(Script.handDown + Script.handTakes) {
            travelling(task, from: CGPoint(x: mid, y: head(tiers[0])), to: CGPoint(x: mid, y: head(tiers[1])),
                       progress: time.beat(Script.handDown, Script.handTakes), bend: 60)
        }
        if time.after(Script.onIt) && !time.after(Script.passDown) {
            SceneBubble(text: String(localized: "On it!"))
                .scaleEffect(Ease.spring(time.beat(Script.onIt, 0.6), bounce: 0.15), anchor: .bottom)
                .position(x: mid, y: head(tiers[1]))
        }
        // …who passes it to the builder and the reviewer.
        if time.after(Script.passDown) && !time.after(Script.passDown + Script.handTakes) {
            let p = time.beat(Script.passDown, Script.handTakes)
            travelling(String(localized: "Build it"), from: CGPoint(x: mid, y: head(tiers[1])),
                       to: CGPoint(x: mid - Layout.pair, y: head(tiers[2])), progress: p, bend: -40)
            travelling(String(localized: "Review it"), from: CGPoint(x: mid, y: head(tiers[1])),
                       to: CGPoint(x: mid + Layout.pair, y: head(tiers[2])), progress: p, bend: 40)
        }
        if time.after(Script.work) && !time.after(Script.doneUp) {
            SceneBubble(text: String(localized: "Building…"))
                .position(x: mid - Layout.pair, y: head(tiers[2]))
                .opacity(Ease.out(time.beat(Script.work, 0.6)))
            SceneBubble(text: String(localized: "Reviewing…"))
                .position(x: mid + Layout.pair, y: head(tiers[2]))
                .opacity(Ease.out(time.beat(Script.work + 0.4, 0.6)))
        }
        // Done goes back up the same way.
        if time.after(Script.doneUp) && !time.after(Script.doneUp + Script.doneUpTakes) {
            travelling(String(localized: "Done ✓"), from: CGPoint(x: mid - Layout.pair, y: head(tiers[2])),
                       to: CGPoint(x: mid, y: head(tiers[1])), progress: time.beat(Script.doneUp, Script.doneUpTakes),
                       bend: -40, done: true)
        }
        if time.after(Script.reportUp) && !time.after(Script.reportUp + Script.doneUpTakes) {
            travelling(String(localized: "Done ✓"), from: CGPoint(x: mid, y: head(tiers[1])),
                       to: CGPoint(x: mid, y: head(tiers[0])), progress: time.beat(Script.reportUp, Script.doneUpTakes),
                       bend: 60, done: true)
        }
        if time.after(Script.thanks) {
            SceneBubble(text: String(localized: "Great work, team ♥"))
                .scaleEffect(Ease.spring(time.beat(Script.thanks, 0.6), bounce: 0.15), anchor: .bottom)
                .position(x: mid, y: head(tiers[0]))
        }
    }

    /// A bubble flying from one head to another along a gentle arc, shrinking a little in flight.
    private func travelling(_ text: String, from: CGPoint, to: CGPoint, progress: Double, bend: CGFloat,
                            done: Bool = false) -> some View {
        let p = Ease.inOut(progress)
        let control = CGPoint(x: (from.x + to.x) / 2 + bend, y: (from.y + to.y) / 2)
        let u = CGFloat(p)
        let x = (1 - u) * (1 - u) * from.x + 2 * (1 - u) * u * control.x + u * u * to.x
        let y = (1 - u) * (1 - u) * from.y + 2 * (1 - u) * u * control.y + u * u * to.y
        let inFlight = sin(Double.pi * p)
        return SceneBubble(text: text, tail: false)
            .overlay(alignment: .topTrailing) {
                if done {
                    Circle().fill(AvatarPalette.gold).frame(width: 6, height: 6).offset(x: 3, y: -3)
                }
            }
            .scaleEffect(1 - 0.12 * inFlight)
            .shadow(color: AvatarPalette.outline.opacity(0.25 * inFlight), radius: 6 * inFlight, y: 4 * inFlight)
            .position(x: x, y: y)
    }
}

/// A grassy ledge of the village, in the world's own pixels: someone's spot on their tier. The same
/// drawing and inks as the Agents page's ledge (XBotWorld keeps that one private); world art keeps
/// its own inks, never UI tokens.
private struct Ledge: View {
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            let px: CGFloat = 3
            func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
            }
            let w = size.width
            let grass = Color(hex: "6CCB5F"), shade = Color(hex: "4FA84A"), soil = Color(hex: "9A6A43")
            block(0, px, w, px * 4, AvatarPalette.outline)
            block(px, px * 2, w - 2 * px, px * 2, grass)
            block(px, px * 3, w - 2 * px, px, shade)
            block(px * 2, px * 5, w - 4 * px, px * 2, AvatarPalette.outline)
            block(px * 3, px * 4, w - 6 * px, px * 2, soil)
            var x = px * 3
            var i = 0
            while x < w - px * 3 {
                if i % 3 == 0 { block(x, 0, px, px, grass) }
                if i % 9 == 4 { block(x, -px, px, px, AvatarPalette.blush) }
                x += px * 2
                i += 1
            }
        }
        .frame(width: width, height: 21)
    }
}

/// A four-pointed pixel sparkle: someone new has joined.
private struct Sparkle: View {
    let progress: Double

    var body: some View {
        let grow = Ease.out(progress)
        let fade = 1 - Ease.in(progress)
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let px: CGFloat = 3
            let reach = Int(2 + grow * 5)
            for k in 0...reach {
                let d = CGFloat(k) * px
                for (dx, dy) in [(d, 0), (-d, 0), (0, d), (0, -d)] {
                    context.fill(Path(CGRect(x: c.x + dx - px / 2, y: c.y + dy - px / 2, width: px, height: px)),
                                 with: .color(k == 0 ? AvatarPalette.white : AvatarPalette.gold))
                }
            }
        }
        .frame(width: 60, height: 60)
        .opacity(fade)
        .scaleEffect(0.6 + 0.6 * grow)
    }
}

/// Dust from a landing: a few pixel puffs thrown out to the sides.
private struct Dust: View {
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let px: CGFloat = 3
            let out = CGFloat(Ease.out(progress)) * 34
            let rise = CGFloat(Ease.hop(progress)) * 8
            for (side, lift) in [(-1.0, 0.0), (1.0, 0.0), (-0.6, 1.0), (0.6, 1.0)] {
                let x = size.width / 2 + CGFloat(side) * out
                let y = size.height / 2 - rise * CGFloat(1 + lift)
                context.fill(Path(CGRect(x: x, y: y, width: px * 2, height: px * 2)),
                             with: .color(AvatarPalette.white.opacity(0.85)))
            }
        }
        .frame(width: 100, height: 30)
        .opacity(1 - progress)
    }
}
