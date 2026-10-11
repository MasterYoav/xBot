import SwiftUI

/// A moonlit clearing. All clocks come from the caller, including its Reduce Motion clock.
struct EnchantedForestScenery: View {
    let date: Date
    let width: CGFloat
    var front = false

    var body: some View {
        Canvas { context, size in
            let bounds = CGSize(width: min(max(width, 1), size.width), height: size.height)
            let time = date.timeIntervalSinceReferenceDate
            if front {
                ForestPixels.foreground(context, bounds, time)
            } else {
                ForestPixels.woods(context, bounds, time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The deck's surface is at y=14: ten points above this 180×48 mount's centre.
/// Its central landing stays clear for the character and the caller's HoloScreen.
struct EnchantedForestMount: View {
    let moving: Bool
    let facing: CGFloat
    let date: Date

    var body: some View {
        Canvas { context, size in
            ForestPixels.workstation(context, size, date.timeIntervalSinceReferenceDate, moving, facing)
        }
        .frame(width: 180, height: 48)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Original sprite-art colours, distinct from the semantic colours of the surrounding UI.
private enum ForestPixels {
    static let night = rgb(10, 22, 35)
    static let mist = rgb(28, 65, 69)
    static let distant = rgb(25, 53, 61)
    static let outline = rgb(12, 30, 31)
    static let bark = rgb(63, 51, 44)
    static let barkLight = rgb(91, 73, 52)
    static let wood = rgb(141, 98, 53)
    static let honeyWood = rgb(190, 142, 76)
    static let leafDark = rgb(16, 57, 45)
    static let leaf = rgb(32, 88, 59)
    static let leafLight = rgb(62, 127, 75)
    static let moss = rgb(105, 158, 91)
    static let moon = rgb(216, 239, 211)
    static let gold = rgb(255, 211, 111)
    static let cyan = rgb(105, 227, 209)
    static let lavender = rgb(186, 154, 232)

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    static func block(_ c: GraphicsContext, _ x: CGFloat, _ y: CGFloat,
                      _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        c.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)), with: .color(color))
    }

    /// Scanline ellipses retain stepped edges without thousands of individual pixel fills.
    static func oval(_ c: GraphicsContext, _ x: CGFloat, _ y: CGFloat,
                     _ rx: CGFloat, _ ry: CGFloat, _ color: Color, pixel: CGFloat = 4) {
        guard rx > 0, ry > 0 else { return }
        let rows = Int(ceil(ry / pixel))
        for row in -rows...rows {
            let yy = CGFloat(row) * pixel
            let normalized = yy / ry
            guard abs(normalized) <= 1 else { continue }
            let half = floor(rx * sqrt(max(0, 1 - normalized * normalized)) / pixel) * pixel
            block(c, x - half, y + yy, half * 2 + pixel, pixel, color)
        }
    }

    static func sprite(_ c: GraphicsContext, _ rows: [String], x: CGFloat, y: CGFloat,
                       pixel: CGFloat, palette: [Character: Color]) {
        for (r, row) in rows.enumerated() {
            for (column, character) in row.enumerated() {
                if let color = palette[character] {
                    block(c, x + CGFloat(column) * pixel, y + CGFloat(r) * pixel, pixel, pixel, color)
                }
            }
        }
    }

    static func woods(_ c: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        c.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [night, mist, rgb(36, 79, 61)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // The moon sits in a canopy opening; layered block halos rather than blur filters.
        let mx = w * 0.56

        // Depth comes from narrow distant trees, low mist, then massive near trunks.
        for i in 0..<Int(w / 44) + 2 {
            let x = CGFloat(i) * 44 - 16
            let y = CGFloat((i * 17) % 48)
            block(c, x, y, CGFloat(8 + i % 3 * 4), h - y, distant)
            for branch in 0..<3 {
                let by = y + CGFloat(branch * 40)
                block(c, x - 12, by, 28, 4, distant)
                block(c, x - 12, by - 12, 4, 12, distant)
            }
            oval(c, x, y + 16, 36, 28, distant)
        }
        // Keep the opening legible instead of letting procedural far branches cut up the moon.
        oval(c, mx, 52, 47, 47, moon.opacity(0.035))
        oval(c, mx, 52, 35, 35, moon.opacity(0.07))
        oval(c, mx, 52, 23, 23, moon)
        oval(c, mx + 8, 44, 5, 3, moss.opacity(0.35))
        block(c, mx - 12, 56, 8, 4, moss.opacity(0.28))
        block(c, mx + 4, 64, 4, 4, moss.opacity(0.2))
        for ray in 0..<3 {
            let start = mx + CGFloat(ray * 36 - 40)
            for step in 0..<45 {
                let y = CGFloat(step * 4 + 72)
                let x = start - CGFloat(step * 2)
                block(c, x, y, CGFloat(12 + step / 3 * 4), 4, moon.opacity(0.038 - Double(step) * 0.00065))
            }
        }
        for i in 0..<4 {
            oval(c, w * CGFloat(i) / 3, h - 92, w / 3, 16, cyan.opacity(0.025))
        }
        ancientTree(c, x: 24, ground: h - 32, breadth: 64, seed: 1)
        ancientTree(c, x: w - 64, ground: h - 30, breadth: 76, seed: 3)
        if w > 760 { ancientTree(c, x: w * 0.33, ground: h - 56, breadth: 36, seed: 5) }

        // Treehouses live high in the branches, leaving the agent band (y=165…220) open.
        house(c, x: 60, y: 86, t: t, seed: 0)
        house(c, x: w - 134, y: 106, t: t, seed: 2)
        if w > 820 { house(c, x: w * 0.33 - 12, y: 68, t: t, seed: 4) }

        // Overlapping scalloped leaf clusters form a vaulted canopy, not a flat green bar.
        for i in 0..<Int(w / 64) + 2 {
            let x = CGFloat(i * 64 - 20)
            let opening = abs(x - mx) < 110
            let y: CGFloat = opening ? -12 : 12 + CGFloat(i % 3 * 8)
            oval(c, x, y + 8, 60, 36, outline)
            oval(c, x - 4, y, 56, 32, leafDark)
            oval(c, x - 16, y - 8, 36, 24, leaf)
            for leafIndex in 0..<8 {
                let lx = x - 40 + CGFloat((leafIndex * 19 + i * 7) % 88)
                let ly = y - 8 + CGFloat((leafIndex * 13) % 32)
                block(c, lx, ly, 8, 4, leafLight.opacity(0.5))
            }
            if !opening {
                for vine in 0..<2 {
                    let vx = x + CGFloat(vine * 20)
                    let length = 24 + i % 4 * 8
                    block(c, vx, y + 28, 4, CGFloat(length), leafDark)
                    for v in 0..<length / 12 {
                        block(c, vx - 4, y + 36 + CGFloat(v * 12), 12, 4, leaf)
                    }
                }
            }
        }

        // Ground and a luminous, stepped pond stay beneath the hovering crew.
        block(c, 0, h - 56, w, 56, rgb(20, 49, 39))
        for i in 0..<Int(w / 12) + 1 {
            let x = CGFloat(i * 12)
            block(c, x, h - 60 + CGFloat(i % 3 * 4), 12, 8, leafDark)
            block(c, x + 4, h - 48 + CGFloat((i * 11) % 36), 4, 4, leaf.opacity(0.65))
        }
        let pondX = w * 0.56, pondY = h - 29
        oval(c, pondX, pondY, min(114, w * 0.19), 25, outline)
        oval(c, pondX, pondY - 2, min(106, w * 0.18), 20, rgb(30, 99, 94))
        oval(c, pondX, pondY - 4, min(92, w * 0.16), 14, rgb(40, 123, 113))
        for i in 0..<9 {
            let shimmer = 0.2 + 0.2 * sin(t * 1.4 + Double(i))
            block(c, pondX - 68 + CGFloat((i * 29) % 136), pondY - 12 + CGFloat(i % 5 * 4),
                  CGFloat(12 + i % 3 * 8), 2, moon.opacity(shimmer))
        }
        block(c, pondX + 46, pondY - 6, 20, 4, leafLight)
        block(c, pondX + 50, pondY - 10, 12, 4, moss)
        block(c, pondX + 54, pondY - 14, 4, 4, lavender)
        mushrooms(c, x: w * 0.17, y: h - 18, scale: 1)
        mushrooms(c, x: w * 0.81, y: h - 30, scale: 0.75)
        creatures(c, w: w, h: h, t: t)
        fireflies(c, size, t, near: false)
    }

    static func ancientTree(_ c: GraphicsContext, x: CGFloat, ground: CGFloat, breadth: CGFloat, seed: Int) {
        block(c, x - 8, 0, breadth + 16, ground, outline)
        block(c, x, 0, breadth, ground, bark)
        block(c, x + 8, 0, 8, ground - 16, barkLight)
        block(c, x + breadth - 12, 0, 12, ground, outline.opacity(0.55))
        for i in 0..<18 {
            let bx = x + CGFloat((i * 13 + seed * 7) % max(1, Int(breadth - 8)))
            let by = CGFloat(i * 17)
            block(c, bx, by, 4, CGFloat(12 + i % 3 * 4), i % 4 == 0 ? leafDark : outline.opacity(0.45))
        }
        for side in [-1, 1] {
            for i in 0..<5 {
                let bx = side < 0 ? x - CGFloat(i * 12) : x + breadth + CGFloat(i * 12)
                block(c, bx, 60 - CGFloat(i * 8), 16, 12, bark)
                block(c, bx, 60 - CGFloat(i * 8), 16, 4, barkLight)
                block(c, bx, ground - 16 + CGFloat(i * 4), 16, 12, bark)
            }
        }
        for i in 0..<8 {
            block(c, x - 4, 32 + CGFloat(i * 28), 12, 8, leaf)
            block(c, x, 28 + CGFloat(i * 28), 4, 4, moss.opacity(0.7))
        }
    }

    static func house(_ c: GraphicsContext, x: CGFloat, y: CGFloat, t: Double, seed: Int) {
        // Tapered leaf-shingle roof, timber walls, porch and rope ladder.
        block(c, x - 8, y + 48, 84, 8, outline)
        block(c, x - 4, y + 48, 76, 4, honeyWood)
        block(c, x, y + 8, 64, 40, bark)
        block(c, x + 4, y + 12, 56, 36, wood)
        for row in 0..<4 { block(c, x + 4, y + 16 + CGFloat(row * 8), 56, 2, barkLight) }
        for row in 0..<6 {
            block(c, x + 24 - CGFloat(row * 8), y - 16 + CGFloat(row * 4),
                  CGFloat(16 + row * 16), 4, row % 2 == 0 ? leaf : leafLight)
        }
        block(c, x + 4, y + 12, 4, 36, honeyWood)
        block(c, x + 56, y + 12, 4, 36, barkLight)
        for dx in [CGFloat(16), CGFloat(40)] {
            block(c, x + dx - 4, y + 20, 20, 20, outline)
            block(c, x + dx, y + 24, 12, 12, gold)
            block(c, x + dx + 4, y + 24, 2, 12, wood)
            block(c, x + dx, y + 28, 12, 2, wood)
            oval(c, x + dx + 6, y + 28, 18, 16, gold.opacity(0.055 + 0.015 * sin(t + Double(seed))))
        }
        block(c, x + 26, y + 38, 12, 10, bark)
        block(c, x + 34, y + 42, 2, 2, gold)
        block(c, x + 6, y + 56, 2, 40, honeyWood.opacity(0.7))
        block(c, x + 20, y + 56, 2, 40, honeyWood.opacity(0.7))
        for rung in 0..<5 { block(c, x + 6, y + 60 + CGFloat(rung * 8), 16, 2, wood) }
    }

    static func mushrooms(_ c: GraphicsContext, x: CGFloat, y: CGFloat, scale: CGFloat) {
        for i in 0..<3 {
            let xx = x + CGFloat(i * 20), yy = y - CGFloat(i % 2 * 8)
            let cap = i % 2 == 0 ? cyan : lavender
            oval(c, xx, yy - 8, 20 * scale, 16 * scale, cap.opacity(0.06))
            block(c, xx - 2, yy - 8, 4, 12, moon)
            block(c, xx - 10 * scale, yy - 12, 20 * scale, 4, cap)
            block(c, xx - 6 * scale, yy - 16, 12 * scale, 4, cap)
            block(c, xx - 6 * scale, yy - 12, 4, 2, moon)
        }
    }

    static func creatures(_ c: GraphicsContext, w: CGFloat, h: CGFloat, t: Double) {
        let blink = sin(t * 0.6) > 0.995
        sprite(c, [
            "B.....B", "BBBBBBB", "BLBBBLB", "BWBBBWB", "BBBGBBB",
            "BBBBBBB", ".BBBBB.", "..BBB..", ".G...G."
        ], x: 100, y: 51, pixel: 3, palette: [
            "B": barkLight, "L": honeyWood, "W": blink ? bark : moon, "G": gold
        ])
        // Long ears and cotton tail distinguish the rabbit even at this small scale.
        sprite(c, [
            "..W.W.....", "..WPW.....", "..WWW.....", "..WKWW....", "...WWWWW..",
            ".WWWWWWWW.", "WWWWWWWWW.", ".WWWWWWWW.", "..WW..WW.."
        ], x: w * 0.27, y: h - 38, pixel: 3, palette: [
            "W": rgb(194, 208, 180), "P": rgb(214, 160, 152), "K": outline
        ])
        sprite(c, [
            ".........A.A..", "........AAAA..", "..........A...", ".........BBB..", ".........BKB..",
            "........BBBBB.", "..BBBBBBBBB...", ".BBBBLBBLBB...", "BBBBBBBBBBB...",
            "..BBBBBBBB....", "..B.B..B.B....", "..B.B..B.B....", "..K.K..K.K...."
        ], x: w - 112, y: h - 53, pixel: 3, palette: [
            "B": rgb(156, 112, 70), "L": honeyWood, "K": outline, "A": rgb(205, 180, 132)
        ])
    }

    static func fireflies(_ c: GraphicsContext, _ size: CGSize, _ t: Double, near: Bool) {
        let count = near ? 10 : 28
        for i in 0..<count {
            let x = CGFloat((i * 97 + 41) % max(1, Int(size.width))) + CGFloat(sin(t * 0.45 + Double(i))) * 8
            let y = near ? size.height - 20 + CGFloat(i % 3 * 4)
                : 86 + CGFloat((i * 47) % max(1, Int(size.height - 124))) + CGFloat(cos(t * 0.6 + Double(i))) * 5
            let glow = 0.4 + 0.3 * sin(t * 1.7 + Double(i) * 2)
            block(c, x - 4, y - 4, 12, 12, gold.opacity(glow * 0.08))
            block(c, x, y, 3, 3, gold.opacity(glow + 0.25))
        }
    }

    static func foreground(_ c: GraphicsContext, _ size: CGSize, _ t: Double) {
        // This pass never reaches the agents: only the bottom 24 points have solid leaves.
        for i in 0..<Int(size.width / 28) + 1 {
            let x = CGFloat(i * 28), y = size.height - CGFloat(8 + i % 3 * 4)
            block(c, x, y, 4, 20, outline)
            for leafIndex in 0..<3 {
                let yy = y + CGFloat(leafIndex * 4)
                block(c, x - CGFloat(12 - leafIndex * 4), yy, CGFloat(12 - leafIndex * 4), 4, leafDark)
                block(c, x + 4, yy, CGFloat(12 - leafIndex * 4), 4, leaf)
            }
        }
        fireflies(c, size, t, near: true)
    }

    static func workstation(_ c: GraphicsContext, _ size: CGSize, _ t: Double, _ moving: Bool, _ facing: CGFloat) {
        let x = size.width / 2
        // A moss-topped porch with visible plank seams and a rooted timber underside.
        block(c, x - 60, 14, 120, 16, outline)
        block(c, x - 56, 14, 112, 4, moss)
        block(c, x - 56, 18, 112, 8, wood)
        block(c, x - 52, 18, 104, 3, honeyWood)
        block(c, x - 52, 26, 104, 4, barkLight)
        for plank in 0..<7 { block(c, x - 48 + CGFloat(plank * 16), 18, 2, 8, bark) }
        for side in [-1, 1] {
            let sx = x + CGFloat(side * 36)
            block(c, sx - 4, 30, 8, 12, bark)
            block(c, sx - 4, 30, 4, 8, barkLight)
            block(c, sx - 12, 38, 24, 4, leafDark)
            block(c, sx - 8, 34, 16, 4, leaf)
            block(c, sx - 4, 30, 8, 4, leafLight)
        }
        block(c, x - 20, 30, 40, 4, bark)
        block(c, x - 12, 34, 24, 4, leafDark)
        block(c, x - 4, 38, 8, 8, leaf)
        // Side planter and hanging porch lantern: neither covers the character's feet.
        block(c, x - 54, 6, 12, 8, barkLight)
        block(c, x - 50, 2, 4, 8, leafLight)
        block(c, x - 58, 2, 8, 4, leaf)
        block(c, x - 46, 0, 8, 4, moss)
        block(c, x + 48, 26, 2, 6, honeyWood)
        block(c, x + 44, 32, 10, 12, outline)
        block(c, x + 46, 34, 6, 6, gold)
        block(c, x + 44, 42, 10, 2, honeyWood)
        oval(c, x + 48, 37, 12, 10, gold.opacity(0.08 + 0.025 * sin(t * 2)))
        if moving {
            // Enchanted leaves, not a second cloud: deterministic trailing leaf motes.
            let direction: CGFloat = facing < 0 ? -1 : 1
            for i in 0..<5 {
                let xx = x - direction * CGFloat(64 + i * 5)
                let yy = 24 + CGFloat(i % 3 * 4) + CGFloat(sin(t * 4 + Double(i))) * 2
                block(c, xx, yy, 6, 3, (i % 2 == 0 ? moss : gold).opacity(0.7 - Double(i) * 0.1))
            }
        }
    }
}
