import SwiftUI
import XBotCore

/// A quiet lunar outpost. The supplied clock is the only animation source, so a
/// frozen date freezes every orbit, meteor and thruster for Reduce Motion.
struct MoonbaseScenery: View {
    let date: Date
    let width: CGFloat
    var front = false

    var body: some View {
        Canvas { context, size in
            let time = date.timeIntervalSinceReferenceDate
            let span = min(max(width, 1), size.width)
            if front {
                MoonPixels.foreground(context, width: span, height: size.height, time: time)
            } else {
                MoonPixels.space(context, width: span, height: size.height, time: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Feet sit at y=14: ten points above the centre of the 180 × 48 mount.
/// Solar outriggers and a recessed docking deck make this an orbital workstation,
/// rather than another cloud with a different colour.
struct MoonbaseMount: View {
    let moving: Bool
    let facing: CGFloat
    let date: Date

    var body: some View {
        Canvas { context, _ in
            let time = date.timeIntervalSinceReferenceDate
            MoonPixels.workstation(context, moving: moving, facing: facing, time: time)
        }
        .frame(width: 180, height: 48)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Scene-local illustration inks, not interface colours. All silhouettes are
/// assembled from snapped four-point cells, including the planet and dome rims.
private enum MoonPixels {
    static let pixel: CGFloat = 4
    static let void = Color(hex: "080D21")
    static let haze = Color(hex: "121B35")
    static let stone = Color(hex: "777E95")
    static let pale = Color(hex: "B8C6D8")
    static let shade = Color(hex: "424B66")
    static let ink = Color(hex: "202A43")
    static let cyan = Color(hex: "7DE9F5")
    static let gold = Color(hex: "FFE7A0")
    static let panel = Color(hex: "244F81")

    static func block(_ context: GraphicsContext, _ x: CGFloat, _ y: CGFloat,
                      _ width: CGFloat, _ height: CGFloat, _ color: Color) {
        let rect = CGRect(x: (x / pixel).rounded() * pixel,
                          y: (y / pixel).rounded() * pixel,
                          width: width, height: height)
        context.fill(Path(rect), with: .color(color))
    }

    static func phase(_ time: Double, period: Double) -> Double {
        let value = time.truncatingRemainder(dividingBy: period) / period
        return value < 0 ? value + 1 : value
    }

    static func space(_ context: GraphicsContext, width: CGFloat, height: CGFloat, time: Double) {
        context.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)), with: .color(void))
        // A faint broken Milky Way, never a gradient washing out the crew.
        for i in 0..<86 {
            let x = CGFloat(i * 37 % 997) / 997 * width
            let y = CGFloat(12 + i * 19 % 65)
            block(context, x, y, i % 3 == 0 ? 8 : 4, 4, haze.opacity(0.65))
        }
        for i in 0..<105 {
            let x = CGFloat((i * 83 + 17) % 1021) / 1021 * width
            let y = CGFloat((i * 47 + 11) % 235)
            let twinkle = 0.48 + 0.28 * sin(time * 1.3 + Double(i) * 2.7)
            let color = i % 7 == 0 ? gold : pale
            block(context, x, y, 4, 4, color.opacity(twinkle))
            if i % 23 == 0, y < 100 {
                block(context, x - 4, y, 12, 4, color.opacity(twinkle * 0.65))
                block(context, x, y - 4, 4, 12, color.opacity(twinkle * 0.65))
            }
        }
        earth(context, x: width * 0.72, y: 48, time: time)
        meteors(context, width: width, time: time)
        terrain(context, width: width, height: height, time: time)
    }

    static func earth(_ context: GraphicsContext, x: CGFloat, y: CGFloat, time: Double) {
        let radius = 9
        // Longitude travels across a projected sphere: continents rotate while
        // the atmosphere and upper-left sunlight remain anchored in space.
        for row in -radius...radius {
            for col in -radius...radius {
                let distance = col * col + row * row
                guard distance <= radius * radius else { continue }
                let nx = Double(col) / Double(radius)
                let ny = Double(row) / Double(radius)
                let longitude = asin(max(-1, min(1, nx))) + time * 0.045
                let latitude = asin(max(-1, min(1, ny)))
                let continent = sin(longitude * 2.4 + latitude * 1.6)
                    + 0.62 * cos(longitude * 4.8 - latitude * 3.2)
                    + 0.32 * sin(longitude * 8 + latitude * 5)
                let cloud = sin(longitude * 6 + latitude * 9 + time * 0.012) > 0.86
                var color = Color(hex: "287BC8")
                if continent > 0.68 { color = Color(hex: "70B998") }
                if continent > 1.25 { color = Color(hex: "D3C38F") }
                if cloud || abs(ny) > 0.88 { color = Color(hex: "E6F6FA") }
                if distance > 66 { color = cyan.opacity(0.85) }
                let darkness = max(0, (nx + ny * 0.35 + 0.25) * 0.62)
                color = color.mix(with: void, by: min(0.78, darkness))
                block(context, x + CGFloat(col) * 4, y + CGFloat(row) * 4, 4, 4, color)
            }
        }
        let angle = time * 0.14
        let sx = x + CGFloat(cos(angle)) * 70
        let sy = y + CGFloat(sin(angle)) * 28
        // Solar wings, striped cells, a gold instrument and a tiny telemetry lamp.
        block(context, sx - 20, sy - 4, 16, 12, ink)
        block(context, sx + 8, sy - 4, 16, 12, ink)
        for offset in [CGFloat(-16), -8, 12, 20] {
            block(context, sx + offset, sy, 4, 4, panel)
        }
        block(context, sx - 4, sy, 12, 4, pale)
        block(context, sx, sy - 4, 4, 12, gold)
        block(context, sx, sy - 8, 4, 4, cyan.opacity(0.65 + 0.3 * sin(time * 3)))
    }

    static func meteors(_ context: GraphicsContext, width: CGFloat, time: Double) {
        for i in 0..<3 {
            let p = phase(time + Double(i) * 0.72, period: 13)
            guard p < 0.12 else { continue }
            let progress = CGFloat(p / 0.12)
            let x = width * (0.12 + CGFloat(i) * 0.19) + progress * 124
            let y = 8 + CGFloat(i) * 12 + progress * 56
            for tail in (0..<9).reversed() {
                let alpha = (1 - Double(tail) / 9) * min(1, (0.12 - p) * 35)
                block(context, x - CGFloat(tail) * 8, y - CGFloat(tail) * 4,
                      8, 4, (tail < 2 ? gold : cyan).opacity(alpha))
            }
            block(context, x, y, 4, 4, .white)
        }
    }

    static func terrain(_ context: GraphicsContext, width: CGFloat, height: CGFloat, time: Double) {
        let horizon = height - 72
        var x: CGFloat = 0
        while x < width {
            let ridge = CGFloat(sin(Double(x) * 0.017) * 8 + cos(Double(x) * 0.043) * 4)
            let top = horizon + ridge
            block(context, x, top, 4, height - top + 4, shade)
            block(context, x, top + 8, 4, height - top, stone)
            block(context, x, top, 4, 4, pale.opacity(0.7))
            x += 4
        }
        // Impact basins have terraced bright rims and a dark inner bowl.
        crater(context, x: width * 0.12, y: height - 28, radius: 32)
        crater(context, x: width * 0.53, y: height - 18, radius: 44)
        crater(context, x: width * 0.85, y: height - 44, radius: 20)
        for i in 0..<50 {
            let dx = CGFloat((i * 71 + 19) % 997) / 997 * width
            let dy = height - 56 + CGFloat(i * 13 % 52)
            block(context, dx, dy, i % 4 == 0 ? 8 : 4, 4,
                  (i % 2 == 0 ? pale : shade).opacity(0.4))
        }
        dome(context, x: width * 0.30, base: height - 36, radius: 32, time: time)
        dome(context, x: width * 0.68, base: height - 44, radius: 24, time: time + 2)
        radar(context, x: width * 0.92, base: height - 32, time: time)
        // A greenhouse tunnel, landing lamps and an abandoned sample rover.
        block(context, width * 0.30 + 28, height - 44, 36, 8, ink)
        block(context, width * 0.30 + 32, height - 44, 28, 4, pale)
        for i in 0..<3 {
            block(context, width * 0.30 + 36 + CGFloat(i) * 8, height - 40, 4, 4, cyan)
        }
        rover(context, x: width * 0.48, y: height - 48)
        for i in 0..<5 {
            let lx = width * 0.72 + CGFloat(i) * 12
            block(context, lx, height - 12, 4, 8, ink)
            block(context, lx, height - 16, 4, 4, gold.opacity(0.7 + 0.2 * sin(time * 2 + Double(i))))
        }
    }

    static func crater(_ context: GraphicsContext, x: CGFloat, y: CGFloat, radius: Int) {
        let columns = radius / 4
        for row in -3...3 {
            for col in -columns...columns {
                let nx = Double(col) / Double(columns)
                let ny = Double(row) / 3
                let d = nx * nx + ny * ny
                guard d <= 1 else { continue }
                let color: Color
                if d > 0.58 { color = row <= 0 ? pale : shade }
                else { color = row < 1 ? ink : shade }
                block(context, x + CGFloat(col) * 4, y + CGFloat(row) * 4, 4, 4, color)
            }
        }
        block(context, x - 8, y + 4, 16, 4, stone)
    }

    static func dome(_ context: GraphicsContext, x: CGFloat, base: CGFloat, radius: Int, time: Double) {
        let cells = radius / 4
        for row in -cells...0 {
            for col in -cells...cells where col * col + row * row <= cells * cells {
                let rim = col * col + row * row > (cells - 1) * (cells - 1)
                let rib = col == 0 || abs(col) == cells / 2
                var color = Color(hex: "28485F")
                if col < 0 { color = Color(hex: "37687B") }
                if rib { color = shade }
                if rim { color = row < -2 ? pale : stone }
                block(context, x + CGFloat(col) * 4, base + CGFloat(row) * 4, 4, 4, color)
            }
        }
        block(context, x - CGFloat(radius) - 4, base + 4, CGFloat(radius * 2 + 12), 8, ink)
        block(context, x - CGFloat(radius), base + 4, CGFloat(radius * 2 + 4), 4, pale)
        for i in -2...2 {
            block(context, x + CGFloat(i) * 8, base - 8, 4, 8,
                  i == 1 ? cyan : gold.opacity(0.9))
        }
        block(context, x - 4, base, 12, 12, ink)
        block(context, x, base + 4, 4, 4, cyan)
        // Roof beacon and a small botanical silhouette behind the glass.
        block(context, x, base - CGFloat(radius) - 8, 4, 8, pale)
        block(context, x, base - CGFloat(radius) - 12, 4, 4,
              Color(hex: "FF897D").opacity(0.55 + 0.4 * sin(time * 2)))
        block(context, x - 16, base - 16, 4, 8, Color(hex: "71C7AA"))
        block(context, x - 20, base - 20, 12, 4, Color(hex: "71C7AA"))
    }

    static func radar(_ context: GraphicsContext, x: CGFloat, base: CGFloat, time: Double) {
        block(context, x - 12, base, 28, 8, ink)
        block(context, x, base - 24, 4, 24, pale)
        let sweep = CGFloat(sin(time * 0.7)) * 8
        for i in -3...3 {
            let dy = CGFloat(abs(i)) * 4
            block(context, x + CGFloat(i) * 4 + sweep, base - 32 + dy, 4, 4, pale)
        }
        block(context, x + sweep, base - 28, 4, 12, shade)
        block(context, x + sweep, base - 36, 4, 4, cyan)
        // Mast with three interrupted telemetry bars, not a smooth radar arc.
        for i in 0..<3 {
            let alpha = 0.12 + 0.3 * phase(time - Double(i) * 0.8, period: 3)
            block(context, x + 12 + CGFloat(i) * 8, base - 40 - CGFloat(i) * 4,
                  4, 8, cyan.opacity(alpha))
        }
    }

    static func rover(_ context: GraphicsContext, x: CGFloat, y: CGFloat) {
        block(context, x - 8, y + 8, 8, 8, ink)
        block(context, x + 12, y + 8, 8, 8, ink)
        block(context, x - 8, y, 28, 8, pale)
        block(context, x, y - 8, 12, 8, gold)
        block(context, x + 16, y - 16, 4, 16, shade)
        block(context, x + 12, y - 16, 8, 4, cyan)
    }

    static func foreground(_ context: GraphicsContext, width: CGFloat, height: CGFloat, time: Double) {
        // Only the lowest sixteen points overlap the crew layer.
        for i in 0..<Int(width / 4) + 1 {
            let x = CGFloat(i) * 4
            let rise: CGFloat = i % 13 < 4 ? 12 : 8
            block(context, x, height - rise, 4, rise, shade)
            if i % 9 == 0 { block(context, x, height - rise, 4, 4, pale.opacity(0.65)) }
        }
        for i in 0..<18 {
            let p = phase(time + Double(i) * 1.4, period: 24)
            let x = CGFloat((i * 137 + 41) % 997) / 997 * width + CGFloat(p) * 20
            let y = height - 4 - CGFloat(sin(p * .pi)) * 12
            block(context, x, y, 4, 4, pale.opacity(0.18 * sin(p * .pi)))
        }
    }

    static func workstation(_ originalContext: GraphicsContext, moving: Bool, facing: CGFloat, time: Double) {
        // The mount's pixel grid starts two points above the canvas grid, placing
        // the snapped deck at exactly y=14 rather than rounding it down to y=16.
        var context = originalContext
        context.translateBy(x: 0, y: -2)
        // Deck y=14 aligns with the avatar's feet. Side consoles never occupy
        // the middle silhouette; the parent's shared HoloScreen sits above it.
        block(context, 46, 14, 88, 4, pale)
        block(context, 42, 18, 96, 8, ink)
        block(context, 50, 18, 80, 4, stone)
        block(context, 58, 26, 64, 8, shade)
        block(context, 70, 30, 40, 4, ink)
        for x in [CGFloat(22), 138] {
            block(context, x, 18, 20, 12, ink)
            for c in 0..<4 {
                block(context, x + CGFloat(c) * 4, 18, 4, 4, c % 2 == 0 ? panel : cyan.opacity(0.55))
                block(context, x + CGFloat(c) * 4, 26, 4, 4, panel)
            }
        }
        block(context, 38, 22, 16, 4, pale)
        block(context, 126, 22, 16, 4, pale)
        for x in [CGFloat(50), 126] {
            block(context, x, 6, 4, 12, pale)
            block(context, x - 4, 2, 12, 8, ink)
            block(context, x, 2, 4, 4, cyan)
        }
        for x in [CGFloat(62), 110] {
            block(context, x, 30, 8, 8, ink)
            let length: CGFloat = moving ? 8 + CGFloat(Int(time * 10) & 1) * 4 : 4
            block(context, x, 38, 8, length, panel.opacity(0.65))
            block(context, x, 38, 8, 4, cyan)
        }
        for i in 0..<5 {
            let active = Int(time * 3) % 5 == i
            block(context, 74 + CGFloat(i) * 8, 22, 4, 4, active ? gold : cyan.opacity(0.45))
        }
        if moving {
            let direction: CGFloat = facing < 0 ? -1 : 1
            for i in 0..<5 {
                let x = 90 - direction * (52 + CGFloat(i) * 8)
                block(context, x, 34 + CGFloat(i % 2) * 4, 4, 4,
                      cyan.opacity(0.6 - Double(i) * 0.1))
            }
        }
    }
}
