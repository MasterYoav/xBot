import SwiftUI
import XBotCore

/// A submerged kingdom, with a clear middle-water lane reserved for the crew.
/// Time comes entirely from the scene's clock, so a frozen date freezes every creature.
struct UnderwaterScenery: View {
    let date: Date
    let width: CGFloat
    var front = false

    var body: some View {
        Canvas { context, size in
            let t = date.timeIntervalSinceReferenceDate
            let extent = CGSize(width: max(1, min(width, size.width)), height: size.height)
            if front {
                UnderwaterArt.nearReef(context, extent, t)
            } else {
                UnderwaterArt.water(context, extent, t)
                UnderwaterArt.kingdom(context, extent)
                UnderwaterArt.whale(context, extent, t)
                UnderwaterArt.life(context, extent, t)
                UnderwaterArt.reef(context, extent, t, foreground: false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A pearl-powered bathysphere deck. Its top is y=14: ten points above the frame's centre.
/// The glass habitat is behind the character; the shared HoloScreen supplies their workstation.
struct UnderwaterMount: View {
    let moving: Bool
    let facing: CGFloat
    let date: Date

    var body: some View {
        ZStack {
            Canvas { context, _ in
                let t = date.timeIntervalSinceReferenceDate
                UnderwaterArt.pixelDisc(context, x: 90, y: 66, radius: 48, pixel: 4) { col, row in
                    let edge = col * col + row * row > 121
                    return edge ? UnderwaterArt.pearl.opacity(0.48)
                        : UnderwaterArt.aqua.opacity(row < 0 ? 0.055 : 0.025)
                }
                // Broken highlights preserve the silhouette without washing out the avatar.
                for (x, y, w, h) in [(58.0, 34.0, 4.0, 20.0), (62, 26, 4, 8), (66, 22, 16, 4), (110, 94, 8, 4)] {
                    UnderwaterArt.block(context, x, y, w, h, UnderwaterArt.pearl.opacity(0.62))
                }
                UnderwaterArt.block(context, 122, 46 + sin(t) * 2, 4, 8, UnderwaterArt.aqua.opacity(0.35))
            }
            .frame(width: 180, height: 128)
            .offset(y: -46)

            Canvas { context, _ in
                let t = date.timeIntervalSinceReferenceDate
                let ink = UnderwaterArt.ink
                UnderwaterArt.block(context, 42, 14, 96, 8, ink)
                UnderwaterArt.block(context, 38, 22, 104, 8, ink)
                UnderwaterArt.block(context, 46, 30, 88, 8, ink)
                UnderwaterArt.block(context, 54, 38, 72, 4, ink)
                UnderwaterArt.block(context, 46, 14, 88, 4, UnderwaterArt.pearl)
                UnderwaterArt.block(context, 42, 22, 96, 8, UnderwaterArt.teal)
                UnderwaterArt.block(context, 50, 30, 80, 8, Color(hex: "246883"))
                UnderwaterArt.block(context, 58, 38, 64, 4, Color(hex: "164256"))
                UnderwaterArt.block(context, 54, 18, 72, 4, Color(hex: "F0CB7A"))
                for x in stride(from: 58.0, through: 122.0, by: 16.0) {
                    UnderwaterArt.block(context, x, 26, 8, 4, UnderwaterArt.aqua.opacity(0.75))
                    UnderwaterArt.block(context, x + 2, 30, 4, 4, UnderwaterArt.pearl.opacity(0.85))
                }
                // Two shell outriggers distinguish the craft from the sky realm's cloud.
                for x in [34.0, 138.0] {
                    UnderwaterArt.block(context, x, 18, 8, 16, ink)
                    UnderwaterArt.block(context, x, 22, 8, 8, Color(hex: "EAA5C4"))
                    UnderwaterArt.block(context, x + 2, 18, 4, 4, UnderwaterArt.pearl)
                }
                UnderwaterArt.pixelDisc(context, x: 90, y: 36, radius: 6, pixel: 2) { _, row in
                    row < 0 ? .white : UnderwaterArt.aqua
                }
                for i in 0..<(moving ? 10 : 3) {
                    let phase = UnderwaterArt.wrap(t * (moving ? 23 : 9) + Double(i * 13), 54)
                    let x = moving ? 90 - Double(facing) * (54 + phase) : 68 + Double(i * 22)
                    let y = moving ? 28 + sin(t * 3 + Double(i)) * 5 : 45 - phase * 0.28
                    UnderwaterArt.bubble(context, x: x, y: y, radius: i % 3 == 0 ? 4 : 2,
                                         alpha: 0.65 * (1 - phase / 70))
                }
            }
            .frame(width: 180, height: 48)
        }
        .frame(width: 180, height: 48)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Local art palette and geometry, deliberately separate from app chrome and design tokens.
private enum UnderwaterArt {
    static let ink = Color(hex: "09283F")
    static let teal = Color(hex: "238F9D")
    static let aqua = Color(hex: "74EAD5")
    static let pearl = Color(hex: "D5FFFF")

    static func wrap(_ value: Double, _ period: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: period)
        return remainder < 0 ? remainder + period : remainder
    }

    static func block(_ context: GraphicsContext, _ x: Double, _ y: Double,
                      _ w: Double, _ h: Double, _ color: Color) {
        context.fill(Path(CGRect(x: (x / 2).rounded() * 2, y: (y / 2).rounded() * 2,
                                 width: w, height: h)), with: .color(color))
    }

    static func pixelDisc(_ context: GraphicsContext, x: Double, y: Double, radius: Int, pixel: Int,
                          color: (Int, Int) -> Color) {
        let n = radius / pixel
        for row in -n...n {
            let half = Int(Double(n * n - row * row).squareRoot())
            for col in -half...half {
                block(context, x + Double(col * pixel), y + Double(row * pixel),
                      Double(pixel), Double(pixel), color(col, row))
            }
        }
    }

    static func water(_ context: GraphicsContext, _ size: CGSize, _ t: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [Color(hex: "12687C"), Color(hex: "0B3D63"), Color(hex: "081E3D")]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        // Stepped beams, not a blurred overlay: their edges share the sprites' pixel language.
        for beam in 0..<6 {
            let source = Double(size.width) * Double(beam) / 5 - 80 + sin(t * 0.17 + Double(beam)) * 14
            for row in 0..<35 {
                let y = Double(row * 8)
                let x = source + y * 0.38
                let breadth = 16 + y * 0.19
                let alpha = 0.065 * (1 - Double(row) / 38)
                block(context, x, y, breadth, 8, pearl.opacity(alpha))
                block(context, x + 8, y, max(4, breadth * 0.25), 8, aqua.opacity(alpha * 0.8))
            }
        }
        for i in 0..<46 {
            let x = Double((i * 97 + 31) % max(1, Int(size.width)))
            let y = wrap(Double(i * 47) - t * 2, Double(size.height))
            block(context, x + sin(t * 0.3 + Double(i)) * 3, y, 2, 2, pearl.opacity(0.08 + Double(i % 4) * 0.025))
        }
        for i in 0..<24 {
            let x = Double(i) * Double(size.width) / 23
            block(context, x + sin(t * 0.5 + Double(i)) * 8, Double(i % 3) * 4,
                  20 + Double(i % 4) * 8, 2, aqua.opacity(0.18))
        }
    }

    static func kingdom(_ context: GraphicsContext, _ size: CGSize) {
        let floor = Double(size.height) - 30
        let center = Double(size.width) * 0.59
        let stone = Color(hex: "20556C"), rim = Color(hex: "36778A")
        // A distant stepped citadel: five spires, copper crowns, luminous arched windows.
        for tower in -2...2 {
            let x = center + Double(tower) * 42
            let height = Double(48 + (2 - abs(tower)) * 12)
            let top = floor - height
            block(context, x - 14, top, 28, height, stone)
            block(context, x - 18, top, 36, 4, rim)
            block(context, x - 10, top - 8, 20, 8, rim)
            block(context, x - 6, top - 16, 12, 8, Color(hex: "5C8D8E"))
            block(context, x - 2, top - 26, 4, 10, Color(hex: "B5AE74").opacity(0.8))
            block(context, x - 14, top + 4, 4, height - 4, rim.opacity(0.55))
            for y in stride(from: top + 14, to: floor - 6, by: 18) {
                block(context, x - 4, y, 8, 10, ink)
                block(context, x - 2, y + 2, 4, 6, aqua.opacity(0.38))
            }
            for row in 0..<Int(height / 8) {
                block(context, x + Double(row % 2) * 8 - 8, top + Double(row * 8), 10, 2, ink.opacity(0.18))
            }
        }
        block(context, center - 114, floor - 14, 228, 18, stone)
        for step in 0..<3 {
            block(context, center - 122 - Double(step * 6), floor + Double(step * 4),
                  Double(244 + step * 12), 4, rim.opacity(0.6))
        }
        // A darker gateway and a bioluminescent pearl over its lintel.
        block(context, center - 10, floor - 26, 20, 30, ink)
        block(context, center - 6, floor - 30, 12, 4, ink)
        pixelDisc(context, x: center, y: floor - 38, radius: 4, pixel: 2) { _, _ in aqua.opacity(0.7) }
        // Broken columns at the margins keep the palace from looking like a lone sprite.
        for i in 0..<4 {
            let x = Double(size.width) * (i < 2 ? 0.1 : 0.9) + Double(i % 2) * 24
            let top = floor - Double(22 + i * 5)
            block(context, x, top, 12, floor - top, stone)
            block(context, x - 4, top, 20, 4, rim)
            block(context, x + 4, top + 4, 2, floor - top - 4, rim.opacity(0.6))
        }
    }

    static func fish(_ context: GraphicsContext, x: Double, y: Double, scale: Double, color: Color, facing: Double) {
        var c = context
        c.translateBy(x: x, y: y)
        c.scaleBy(x: scale * facing, y: scale)
        block(c, -6, -2, 12, 4, color)
        block(c, -2, -4, 6, 8, color)
        block(c, -10, -4, 4, 8, color.opacity(0.8))
        block(c, 4, -2, 2, 2, ink)
        block(c, -2, -4, 4, 2, pearl.opacity(0.5))
    }

    static func life(_ context: GraphicsContext, _ size: CGSize, _ t: Double) {
        for school in 0..<3 {
            let span = Double(size.width) + 120
            let facing = school == 1 ? -1.0 : 1.0
            let drift = wrap(t * Double(9 + school * 3) + Double(school * 217), span) - 60
            let lead = facing > 0 ? drift : Double(size.width) - drift
            for i in 0..<9 {
                let x = lead - facing * Double((i % 3) * 18 + (i / 3) * 10)
                let y = Double(36 + school * 25 + (i / 3) * 8) + sin(t * 1.8 + Double(i)) * 2
                fish(context, x: x, y: y, scale: school == 0 ? 0.75 : 1,
                     color: Color(hex: school == 1 ? "F4C877" : "65C4C8").opacity(0.7), facing: facing)
            }
        }
        for i in 0..<4 {
            let x = Double(size.width) * [0.08, 0.34, 0.73, 0.94][i] + sin(t * 0.3 + Double(i)) * 8
            let y = Double(68 + (i % 2) * 24) + sin(t * 0.8 + Double(i) * 2) * 6
            let tint = Color(hex: i % 2 == 0 ? "BFA8F6" : "79DDD7")
            // Translucent pixel bells with scalloped rims and independently swaying tentacles.
            for row in 0..<4 {
                let half = [6.0, 10, 14, 16][row]
                block(context, x - half, y + Double(row * 4), half * 2, 4, tint.opacity(0.18 + Double(row) * 0.06))
            }
            block(context, x - 10, y + 2, 8, 2, pearl.opacity(0.5))
            for strand in 0..<5 {
                let base = x - 12 + Double(strand * 6)
                block(context, base, y + 16, 4, 4, tint.opacity(0.5))
                for segment in 0..<6 {
                    let sway = sin(t * 1.7 + Double(strand) + Double(segment) * 0.7) * Double(segment) * 0.6
                    block(context, base + sway, y + 20 + Double(segment * 4), 2, 4,
                          tint.opacity(0.4 - Double(segment) * 0.04))
                }
            }
        }
    }

    static func whale(_ context: GraphicsContext, _ size: CGSize, _ t: Double) {
        let phase = wrap(t + 14, 76)
        guard phase < 25 else { return }
        let x = (Double(size.width) + 350) * phase / 25 - 230
        let y = 44 + sin(t * 0.4) * 4
        var c = context
        c.translateBy(x: x, y: y)
        let blue = Color(hex: "397C9C"), light = Color(hex: "6CACBB")
        // Broad, blunt head and tapered body; the raised forked fluke is unmistakably a whale.
        for row in 0..<11 {
            let left = [28.0, 12, 4, 0, 0, 0, 4, 12, 28, 44, 64][row]
            let right = [112.0, 132, 144, 152, 152, 148, 140, 128, 116, 100, 84][row]
            block(c, left, Double(row * 4) - 20, right - left, 4, row >= 7 ? light : blue)
        }
        for i in 0..<9 {
            block(c, -Double(i * 8), -2 - Double(i) + sin(t * 1.1 + Double(i) * 0.3) * 2,
                  10, max(4, 16 - Double(i)), blue)
        }
        for i in 0..<5 {
            let tailX = -72 - Double(i * 4)
            block(c, tailX, -12 - Double(i * 4), 8, 8, blue)
            block(c, tailX, -4 + Double(i * 4), 8, 8, blue)
        }
        block(c, 76, 16, 16, 8, blue)
        block(c, 72, 24, 12, 8, blue)
        block(c, 68, 32, 8, 4, blue)
        block(c, 128, -2, 4, 4, ink)
        block(c, 128, -2, 2, 2, pearl)
        block(c, 128, 10, 20, 2, ink.opacity(0.55))
        for i in 0..<6 { block(c, 100 + Double(i * 6), 14, 2, 6, blue.opacity(0.5)) }
        block(c, 104, -20, 6, 2, ink.opacity(0.6))
        // Tiny companions make its scale legible without an intrusive spout underwater.
        for i in 0..<3 {
            fish(context, x: x - 90 - Double(i * 16), y: y + 16 + Double(i * 5),
                 scale: 0.65, color: aqua.opacity(0.45), facing: 1)
        }
    }

    static func coral(_ context: GraphicsContext, x: Double, floor: Double, seed: Int, near: Bool) {
        let colors = [Color(hex: "EE759D"), Color(hex: "B986DE"), Color(hex: "F4A16A")]
        let color = colors[seed % colors.count].opacity(near ? 0.95 : 0.65)
        let height = Double(24 + seed % 4 * 8)
        block(context, x, floor - height, 4, height, color)
        for branch in 0..<3 {
            let y = floor - 10 - Double(branch * 10)
            let direction = branch % 2 == 0 ? -1.0 : 1.0
            for segment in 0..<3 {
                block(context, x + direction * Double(segment * 4), y - Double(segment * 4), 4, 6, color)
            }
            block(context, x + direction * 8, y - 14, 4, 6, pearl.opacity(near ? 0.7 : 0.25))
        }
        block(context, x - 4, floor - 4, 12, 4, color)
    }

    static func reef(_ context: GraphicsContext, _ size: CGSize, _ t: Double, foreground: Bool) {
        let floor = Double(size.height) - (foreground ? 2 : 14)
        let count = Int(size.width / 40) + 2
        for i in 0..<count {
            let x = Double(i * 40) - 12
            let rockTop = floor - Double(8 + (i * 7) % 16)
            block(context, x, rockTop, 44, floor - rockTop + 16,
                  Color(hex: foreground ? "0A3444" : "164553"))
            block(context, x + 4, rockTop - 4, 24, 4, Color(hex: foreground ? "236A69" : "286B70"))
            if i % 2 == 0 { coral(context, x: x + 20, floor: rockTop + 6, seed: i + 1, near: foreground) }
            // Kelp is made of separate leaves rather than a sine-wave stroke.
            if i % 3 == 0 {
                let height = foreground ? 48 : 36
                for segment in 0..<(height / 4) {
                    let y = rockTop - Double(segment * 4)
                    let sway = sin(t * 1.2 + Double(i) + Double(segment) * 0.24) * Double(segment) * 0.45
                    block(context, x + sway, y, 4, 4, teal.opacity(foreground ? 0.9 : 0.5))
                    if segment % 3 == 1 {
                        let side = segment % 2 == 0 ? -1.0 : 1.0
                        block(context, x + sway + side * 4, y - 2, 8, 4, aqua.opacity(foreground ? 0.55 : 0.22))
                    }
                }
            }
            for pebble in 0..<3 {
                block(context, x + Double(pebble * 12), floor - Double(pebble % 2 * 4), 4, 2,
                      Color(hex: "D4C494").opacity(foreground ? 0.5 : 0.25))
            }
        }
    }

    static func bubble(_ context: GraphicsContext, x: Double, y: Double, radius: Double, alpha: Double) {
        let color = pearl.opacity(alpha)
        block(context, x - radius + 2, y - radius, max(2, radius * 2 - 4), 2, color)
        block(context, x - radius, y - radius + 2, 2, max(2, radius * 2 - 4), color.opacity(0.7))
        block(context, x + radius - 2, y - radius + 2, 2, max(2, radius * 2 - 4), color.opacity(0.45))
        block(context, x - radius + 2, y + radius - 2, max(2, radius * 2 - 4), 2, color.opacity(0.4))
    }

    static func nearReef(_ context: GraphicsContext, _ size: CGSize, _ t: Double) {
        // Nothing opaque in the crew lane: the front pass is just the bottom reef and sparse air.
        reef(context, size, t, foreground: true)
        for i in 0..<14 {
            let x = Double((i * 131 + 19) % max(1, Int(size.width))) + sin(t * 0.8 + Double(i)) * 4
            let rise = wrap(t * Double(5 + i % 3) + Double(i * 17), 86)
            bubble(context, x: x, y: Double(size.height) - rise, radius: i % 4 == 0 ? 5 : 3,
                   alpha: 0.18 + 0.18 * (1 - rise / 86))
        }
        // Sea stars and a tiny pearl oyster hide among the near rocks.
        for i in 0..<3 {
            let x = Double(size.width) * [0.18, 0.48, 0.83][i]
            let y = Double(size.height) - 12
            block(context, x - 6, y, 16, 4, Color(hex: "F6B17E"))
            block(context, x, y - 6, 4, 16, Color(hex: "F6B17E"))
            block(context, x - 2, y - 2, 8, 8, Color(hex: "F6CA91"))
        }
        let x = Double(size.width) * 0.32
        block(context, x - 10, Double(size.height) - 14, 24, 8, Color(hex: "B68BBC"))
        pixelDisc(context, x: x + 2, y: Double(size.height) - 14, radius: 4, pixel: 2) { _, row in
            row < 0 ? .white : pearl
        }
    }
}
