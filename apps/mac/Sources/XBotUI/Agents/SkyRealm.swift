import SwiftUI
import XBotCore

/// The Sky Realm: high above a world seen from the clouds, among planets, stars and rainbows.
/// Everyone rides a golden cloud; a green dragon swims through the cloud sea now and then.
struct SkyScenery: View {
    let date: Date
    let width: CGFloat
    /// Drawn in front of the crew: the near clouds and, when it passes, the dragon.
    var front = false

    var body: some View {
        Canvas { context, size in
            let t = date.timeIntervalSinceReferenceDate
            if front {
                Self.cloudBank(context, size, t, y: size.height - 8, scale: 1.2, speed: 9, seed: 7, alpha: 0.97, spacing: 210)
            } else {
                Self.sky(context, size, t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func block(_ context: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        context.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)), with: .color(color))
    }

    /// A pixelated disc: rows of blocks.
    private static func disc(_ context: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, px: CGFloat,
                             _ color: (Int, Int) -> Color) {
        let n = Int(r / px)
        for row in -n...n {
            let half = Int((Double(n * n - row * row)).squareRoot())
            for col in -half...half {
                block(context, cx + CGFloat(col) * px, cy + CGFloat(row) * px, px, px, color(col, row))
            }
        }
    }

    private static func sky(_ context: GraphicsContext, _ size: CGSize, _ t: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(hex: "0A1A55"), location: 0),
                .init(color: Color(hex: "1F4FC2"), location: 0.35),
                .init(color: Color(hex: "5FB2F5"), location: 0.62),
                .init(color: Color(hex: "BFE8FF"), location: 1),
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        // Stars and sparkles, twinkling, thinning out as the sky brightens.
        for i in 0..<70 {
            let x = CGFloat((i * 7919 + 13) % Int(max(size.width, 1)))
            let y = CGFloat((i * 104_729) % 170)
            let on = (Int(t * 3) + i * 7) % 11 != 0
            let s: CGFloat = i % 9 == 0 ? 3 : 2
            if on { block(context, x, y, s, s, .white.opacity(Double(1 - y / 220))) }
            if i % 13 == 0 {
                let flash = 0.5 + 0.5 * sin(t * 2 + Double(i))
                block(context, x - 4, y + 0.5, 10, 2, .white.opacity(0.7 * flash))
                block(context, x + 0.5, y - 4, 2, 10, .white.opacity(0.7 * flash))
            }
        }
        // A shooting star every so often.
        let streak = (t / 9).truncatingRemainder(dividingBy: 1)
        if streak < 0.12 {
            let p = CGFloat(streak / 0.12)
            let sx = size.width * (0.2 + 0.6 * p), sy = 20 + 70 * p
            for k in 0..<10 { block(context, sx - CGFloat(k) * 6, sy - CGFloat(k) * 2, 4, 2, .white.opacity(1 - Double(k) / 10)) }
        }

        // Rainbows, two arcs fading out.
        let bands = ["FF5A5A", "FFA43B", "FFE14D", "5EDB6B", "4DA6FF", "9A6BFF"].map(Color.init(hex:))
        for (cx, cy, r, alpha) in [(size.width * 0.22, size.height * 0.95, size.height * 0.75, 0.55),
                                   (size.width * 0.78, size.height * 1.05, size.height * 0.62, 0.4)] {
            for (i, band) in bands.enumerated() {
                var arc = Path()
                arc.addArc(center: CGPoint(x: cx, y: cy), radius: r - CGFloat(i) * 5,
                           startAngle: .degrees(198), endAngle: .degrees(322), clockwise: false)
                context.stroke(arc, with: .color(band.opacity(alpha)), lineWidth: 5)
            }
        }

        // Planets: a big blue-and-green world, a ringed one, and small moons.
        let px: CGFloat = 4
        let big = CGPoint(x: size.width * 0.58, y: 62)
        let spin = t * 0.15
        disc(context, cx: big.x, cy: big.y, r: 44, px: px) { col, row in
            let x = Double(col) * 0.42 + spin, y = Double(row) * 0.42
            let landness = sin(x) + cos(y * 1.3 + x * 0.4) + 0.5 * sin(x * 2.1 + y * 1.7)
            let swirl = sin(y * 2.4 + x * 0.6 + 1) > 0.88
            var color = swirl ? Color(hex: "F4FBFF")
                : landness > 0.9 ? Color(hex: landness > 1.6 ? "C9B27A" : "62C27A")
                : Color(hex: landness > 0.5 ? "4FB0E8" : "2F7FD6")
            let light = Double(col + row) / 22   // -1 top-left … +1 bottom-right
            if light > 0.15 { color = color.mix(with: Color(hex: "0A1A55"), by: min(0.55, light * 0.6)) }
            return color
        }
        disc(context, cx: big.x - 16, cy: big.y - 16, r: 7, px: px) { _, _ in .white.opacity(0.3) }
        // The ringed one: the ring's far half behind the planet, its near half in front.
        let ringed = CGPoint(x: size.width * 0.9, y: 54)
        let ringPath = Path(ellipseIn: CGRect(x: ringed.x - 38, y: ringed.y - 8, width: 76, height: 16))
        context.stroke(ringPath, with: .color(Color(hex: "FFD9A0").opacity(0.9)), lineWidth: 3)
        disc(context, cx: ringed.x, cy: ringed.y, r: 18, px: px) { _, row in
            row < 0 ? Color(hex: "F2A65A") : Color(hex: "D9783A")
        }
        var near = context
        near.clip(to: Path(CGRect(x: ringed.x - 40, y: ringed.y + 1, width: 80, height: 10)))
        near.stroke(ringPath, with: .color(Color(hex: "FFE7C2")), lineWidth: 3)
        for (i, color) in ["E8C3FF", "FFB3C7", "BDEBFF"].enumerated() {
            let x = size.width * [0.1, 0.36, 0.73][i], y: CGFloat = [36, 110, 128][i]
            let bob = sin(t * 0.6 + Double(i)) * 2
            disc(context, cx: x, cy: y + bob, r: CGFloat(6 + i * 2), px: 2) { _, _ in Color(hex: color) }
        }
        ground(context, size, t)
    }

    /// The world far below, then patches of cloud drifting over it.
    static func ground(_ context: GraphicsContext, _ size: CGSize, _ t: Double) {
        let top = size.height - 104
        context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: size.height - top)), with: .linearGradient(
            Gradient(colors: [Color(hex: "7FB6E6"), Color(hex: "3E7CC0")]),
            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)))
        let px: CGFloat = 4
        var row = 0
        var y = top + 6
        while y < size.height {
            var x: CGFloat = 0
            var col = 0
            while x < size.width {
                let a = Double(col) * 0.13, b = Double(row) * 0.3
                let h = 1.5 * sin(a * 1.1) * cos(b * 0.9 + 0.7) + 0.7 * sin(a * 2.3 + 1.3) * cos(b * 1.7 + 0.4)
                    + 0.35 * sin(a * 4.1 + 2) * sin(b * 3.3 + 1)
                let color: Color? = h > 1.6 ? Color(hex: "E9F2F7")          // snow caps
                    : h > 1.15 ? Color(hex: "8A8F86")                       // rock
                    : h > 0.55 ? Color(hex: row % 2 == 0 ? "3F8F4E" : "4C9C58") // forest
                    : h > 0.15 ? Color(hex: "7CC06E")                       // fields
                    : h < -1.2 ? Color(hex: "A9DDFF")                       // lakes
                    : nil                                                   // haze
                if let color { block(context, x, y, px, px, color.opacity(0.55 + Double(y - top) / 260)) }
                x += px
                col += 1
            }
            y += px
            row += 1
        }
        cloudBank(context, size, t, y: top + 10, scale: 0.7, speed: 3, seed: 2, alpha: 0.85, spacing: 230)
        cloudBank(context, size, t, y: top + 46, scale: 0.9, speed: 5, seed: 5, alpha: 0.95, spacing: 300)
        dragon(context, size, t)
    }

    /// A drifting row of puffy clouds: overlapping pixel discs, shaded from below.
    static func cloudBank(_ context: GraphicsContext, _ size: CGSize, _ t: Double, y: CGFloat, scale: CGFloat,
                          speed: Double, seed: Int, alpha: Double, spacing: CGFloat = 92) {
        let spacing = spacing * scale
        let shift = CGFloat((t * speed).truncatingRemainder(dividingBy: Double(spacing)))
        var x = -spacing + shift
        var k = seed
        while x < size.width + spacing {
            for (dx, dy, r) in [(0.0, 0.0, 26.0), (-28.0, 8.0, 18.0), (28.0, 6.0, 20.0), (10.0, -12.0, 18.0)] {
                let lift = CGFloat((k * 17) % 9)
                disc(context, cx: x + CGFloat(dx) * scale, cy: y + CGFloat(dy) * scale - lift, r: CGFloat(r) * scale, px: 4) { _, row in
                    (row > 2 ? Color(hex: "D6ECFF") : .white).opacity(alpha)
                }
            }
            x += spacing
            k += 1
        }
    }

    /// The green dragon: a long serpentine body swimming left to right through the clouds every ~50 s,
    /// orange fins along its back, a yellow belly, horns, whiskers and a red eye.
    static func dragon(_ context: GraphicsContext, _ size: CGSize, _ t: Double) {
        let period = 50.0
        let phase = t.truncatingRemainder(dividingBy: period) / 24
        guard phase < 1 else { return }
        let span = Double(size.width) + 900
        let headX = CGFloat(phase * span) - 420
        let baseY = size.height - 74
        func y(at x: CGFloat) -> CGFloat { baseY + CGFloat(sin(Double(x) / 70 - t * 1.8)) * 26 }
        let green = Color(hex: "3FAE55"), light = Color(hex: "66CC72"), dark = Color(hex: "15512A")
        let belly = Color(hex: "F4D560"), fin = Color(hex: "F28A2E"), horn = Color(hex: "EADDB5")
        for i in stride(from: 46, through: 1, by: -1) {
            let x = headX - CGFloat(i) * 8
            let s = max(6, 26 - CGFloat(i) * 0.42)
            let cy = y(at: x)
            block(context, x - s / 2 - 2, cy - s / 2 - 2, s + 4, s + 4, dark)
            block(context, x - s / 2, cy - s / 2, s, s, green)
            block(context, x - s / 2, cy - s / 2, s, max(2, s / 5), light)
            block(context, x - s / 2, cy + s / 5, s, max(3, s / 3.2), belly)
            if i % 2 == 0 { block(context, x - 2, cy - s / 2 - 6, 4, 6, fin) }
            if i == 30 || i == 14 {   // legs
                block(context, x - 3, cy + s / 2, 6, 8, green)
                block(context, x - 5, cy + s / 2 + 7, 10, 3, horn)
            }
        }
        // The tail's tuft.
        let tailX = headX - 47 * 8, tailY = y(at: tailX)
        block(context, tailX - 12, tailY - 6, 12, 12, fin)
        // Head, facing right.
        let hy = y(at: headX) - 4
        block(context, headX - 18, hy - 18, 40, 34, dark)
        block(context, headX - 16, hy - 16, 36, 30, green)
        block(context, headX - 16, hy - 16, 36, 6, light)
        block(context, headX + 18, hy - 6, 22, 18, dark)
        block(context, headX + 18, hy - 4, 20, 14, green)
        block(context, headX + 18, hy + 4, 20, 6, belly)
        block(context, headX + 34, hy - 6, 4, 4, dark)            // nostril
        block(context, headX + 2, hy - 10, 8, 8, .white)
        block(context, headX + 5, hy - 8, 4, 5, Color(hex: "E5333B"))
        block(context, headX + 2, hy - 13, 10, 3, dark)           // brow
        for (dx, h) in [(-12.0, 22.0), (-4.0, 18.0)] {            // horns, swept back
            block(context, headX + CGFloat(dx), hy - 16 - CGFloat(h), 4, CGFloat(h), horn)
            block(context, headX + CGFloat(dx) - 6, hy - 16 - CGFloat(h), 6, 4, horn)
        }
        for k in 0..<10 {                                          // whiskers, trailing back
            let wobble = CGFloat(sin(t * 4 + Double(k) * 0.6)) * 3
            block(context, headX + 30 - CGFloat(k) * 6, hy + 12 + CGFloat(k) * 1.5 + wobble, 5, 2, horn)
            block(context, headX + 30 - CGFloat(k) * 6, hy - 18 - CGFloat(k) * 1.2 - wobble, 5, 2, horn)
        }
    }
}

/// The golden cloud each agent rides, with a trail while it flies.
struct Nimbus: View {
    let moving: Bool
    let facing: CGFloat
    let date: Date

    var body: some View {
        Canvas { context, size in
            let px: CGFloat = 4
            let gold = Color(hex: "FFD34D"), light = Color(hex: "FFF0A8"), deep = Color(hex: "E8A62A")
            let t = date.timeIntervalSinceReferenceDate
            let rows = [
                ".....LLL....LLL.......",
                "...LLLGGL..LGGGL..LL..",
                "..LGGGGGGLLGGGGGLLGGL.",
                ".LGGGGGGGGGGGGGGGGGGGL",
                "LGGGGGGGGGGGGGGGGGGGGL",
                "GGGGGGGGGGGGGGGGGGGGGD",
                ".DGGGGGGGGGGGGGGGGGGD.",
                "..DDGGGDDDGGGGDDDGDD..",
                "....DDD...DDDD..DD....",
            ]
            let ox = size.width / 2 - 11 * px
            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() {
                    let color: Color? = switch ch { case "G": gold; case "L": light; case "D": deep; default: nil }
                    if let color {
                        let wobble = CGFloat(sin(t * 3 + Double(c) * 0.7)) * (r >= 7 ? 1 : 0)
                        context.fill(Path(CGRect(x: ox + CGFloat(c) * px, y: CGFloat(r) * px + 8 + wobble, width: px, height: px)),
                                     with: .color(color))
                    }
                }
            }
            // The trail, streaming out behind.
            if moving {
                for k in 0..<14 {
                    let x = size.width / 2 - facing * (46 + CGFloat(k) * 5)
                    let y = 30 + CGFloat(k) * 0.6 + CGFloat(sin(t * 6 + Double(k))) * 1.5
                    context.fill(Path(CGRect(x: x, y: y, width: 5, height: max(1, 6 - CGFloat(k) * 0.4))),
                                 with: .color(gold.opacity(0.8 - Double(k) / 18)))
                }
            }
        }
        .frame(width: 180, height: 48)
        .accessibilityHidden(true)
    }
}

/// A floating screen in front of an agent working on their cloud.
struct HoloScreen: View {
    let date: Date

    var body: some View {
        Canvas { context, _ in
            let t = date.timeIntervalSinceReferenceDate
            let frame = CGRect(x: 0, y: 0, width: 46, height: 30)
            context.fill(Path(roundedRect: frame, cornerRadius: 3), with: .color(Color(hex: "7FE3FF").opacity(0.28)))
            context.stroke(Path(roundedRect: frame, cornerRadius: 3), with: .color(Color(hex: "BFF4FF")), lineWidth: 1.5)
            let tick = Int(t * 4)
            for line in 0..<4 {
                let w = CGFloat(10 + (tick + line * 5) % 24)
                context.fill(Path(CGRect(x: 5, y: 5 + CGFloat(line) * 6, width: w, height: 2.5)),
                             with: .color([Color(hex: "FFFFFF"), Color(hex: "FFE066"), Color(hex: "9CFFB0"), Color(hex: "FFFFFF")][line].opacity(0.9)))
            }
        }
        .frame(width: 46, height: 30)
        .offset(y: CGFloat(sin(date.timeIntervalSinceReferenceDate * 2)) * 1.5)
        .accessibilityHidden(true)
    }
}
