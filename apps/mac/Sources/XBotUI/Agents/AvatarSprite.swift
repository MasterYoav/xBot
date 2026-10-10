import SwiftUI
import XBotCore

/// An agent's original pixel-art chibi, in the MapleStory Classic manner: a big head, a small body,
/// a dark outline. Built from a template per part on a 16×24 grid, then outlined. Faces right; the
/// world mirrors it to face left.
struct AvatarSprite: View {
    struct Frame: Hashable {
        var breathe = false
        var blink = false
        var legs = Legs.stand
        var talk = false
        /// Typing at a desk: which hand is down.
        var typing = 0
        /// Just the head and hair, for faces.
        var headOnly = false
    }

    enum Legs: Hashable { case stand, stride, sit }

    let avatar: AgentAvatar
    var frame = Frame()
    /// Points per sprite pixel.
    var pixel: CGFloat = 3

    var body: some View {
        let map = PixelMap.make(avatar, frame)
        Canvas { context, _ in
            for (point, color) in map.pixels {
                context.fill(Path(CGRect(x: CGFloat(point.x - map.minX) * pixel, y: CGFloat(point.y - map.minY) * pixel,
                                         width: pixel, height: pixel)), with: .color(color))
            }
        }
        .frame(width: CGFloat(map.width) * pixel, height: CGFloat(map.height) * pixel)
        .accessibilityHidden(true)
    }
}

/// The sprite on its own clock: blinking now and then, breathing, walking if asked.
struct LivingAvatar: View {
    let avatar: AgentAvatar
    var pixel: CGFloat = 3
    var legs = AvatarSprite.Legs.stand
    var talking = false
    var headOnly = false
    /// Keeps neighbours from blinking in step.
    var seed = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
            AvatarSprite(avatar: avatar, frame: Self.frame(at: context.date, seed: seed, legs: legs,
                                                           talking: talking, headOnly: headOnly), pixel: pixel)
        }
    }

    static func frame(at date: Date, seed: Int, legs: AvatarSprite.Legs, talking: Bool, headOnly: Bool) -> AvatarSprite.Frame {
        let t = date.timeIntervalSinceReferenceDate + Double(abs(seed % 997)) * 0.37
        var frame = AvatarSprite.Frame(headOnly: headOnly)
        // Blink for ~0.15 s every 3–6 s, sometimes twice.
        let period = 3.0 + Double(abs(seed % 5)) * 0.7
        let phase = t.truncatingRemainder(dividingBy: period)
        frame.blink = phase < 0.14 || (seed % 3 == 0 && (0.28..<0.4).contains(phase))
        switch legs {
        case .stride:
            let step = Int(t * 7) % 4
            frame.legs = step % 2 == 0 ? .stride : .stand
            frame.breathe = step == 1 || step == 3
        case .sit:
            frame.legs = .sit
            frame.typing = Int(t * 6) % 2
            frame.breathe = Int(t * 1.5) % 2 == 0
        case .stand:
            frame.breathe = Int(t * 1.6) % 2 == 0
        }
        frame.talk = talking && Int(t * 5) % 2 == 0
        return frame
    }
}

/// The sidebar's face: the head in a round tile, alive.
struct AgentFace: View {
    let agent: Agent
    var size: CGFloat = 30
    var status: AgentStatus = .idle

    var body: some View {
        ZStack {
            Circle().fill(AvatarPalette.tile(agent.avatar))
            LivingAvatar(avatar: agent.avatar, pixel: size / 17, talking: status.isWorking, headOnly: true,
                         seed: agent.id.hashValue)
                .offset(y: -size * 0.12)
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .overlay {
            switch status {
            case .working: WorkingRing(size: size)
            case .done: Circle().strokeBorder(Palette.success, lineWidth: max(1.5, size / 16))
            case .idle: Circle().strokeBorder(Palette.hairline)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(agent.name)
    }
}

/// A turning arc: this one is busy.
private struct WorkingRing: View {
    let size: CGFloat
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4 * 360
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: max(1.5, size / 14), lineCap: .round))
                .rotationEffect(.degrees(angle))
                .padding(max(0.75, size / 28))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Colours

enum AvatarPalette {
    static let skin = ["FFE3C9", "F7CBA4", "E8B08A", "C98B60", "8F5B3C", "5E3B27"].map(Color.init(hex:))
    static let hair = ["2C2B36", "5B3A26", "A3622F", "EBC46A", "F497BC", "6DB6FF", "9C7CFF", "5FCB91", "EEF0F5", "E5553E"]
        .map(Color.init(hex:))
    static let outfit = ["4C7DFF", "E5553E", "F2A43B", "3CB274", "8F6DF0", "343B48", "F2F3F6", "6A4AC6", "F06495", "FFD551"]
        .map(Color.init(hex:))
    static let outline = Color(hex: "1D1922")
    static let white = Color(hex: "FFFFFF")
    static let mouth = Color(hex: "B8505F")
    static let blush = Color(hex: "FF9EAD")
    static let gold = Color(hex: "FFC83D")
    static let shoe = Color(hex: "4A3426")
    static let denim = Color(hex: "3F5A8C")

    static func tile(_ avatar: AgentAvatar) -> Color {
        outfit[avatar.outfitColor % outfit.count].mix(with: .white, by: 0.72)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Building the sprite

private struct Point: Hashable { var x: Int; var y: Int }

private struct PixelMap {
    var pixels: [Point: Color] = [:]
    var minX = 0, minY = 0, width = 18, height = 26

    @MainActor private static var cache: [CacheKey: PixelMap] = [:]
    private struct CacheKey: Hashable { let avatar: AgentAvatar; let frame: AvatarSprite.Frame }

    @MainActor static func make(_ avatar: AgentAvatar, _ frame: AvatarSprite.Frame) -> PixelMap {
        let key = CacheKey(avatar: avatar, frame: frame)
        if let hit = cache[key] { return hit }
        var map = build(avatar, frame)
        map.minX = -1
        map.minY = -3
        map.width = 18
        map.height = frame.headOnly ? 19 : 27
        if cache.count > 4000 { cache.removeAll() }
        cache[key] = map
        return map
    }

    private static func build(_ a: AgentAvatar, _ f: AvatarSprite.Frame) -> PixelMap {
        var fills: [Point: Color] = [:]
        let skin = AvatarPalette.skin[a.skin % AvatarPalette.skin.count]
        let hair = AvatarPalette.hair[a.hairColor % AvatarPalette.hair.count]
        let cloth = AvatarPalette.outfit[a.outfitColor % AvatarPalette.outfit.count]
        let bob = f.breathe ? 1 : 0

        func paint(_ rows: [String], top: Int, _ colors: [Character: Color], dy: Int = 0, dx: Int = 0) {
            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() {
                    if let color = colors[ch] { fills[Point(x: c + dx, y: top + r + dy)] = color }
                }
            }
        }

        let style = HairStyle.all[a.hair % HairStyle.all.count]
        // Back hair, behind everything.
        paint(style.rows, top: 0, ["B": hair.mix(with: .black, by: 0.18)], dy: bob)

        if !f.headOnly {
            let outfit = Outfit.all[a.outfit % Outfit.all.count]
            let legs: [String]
            switch f.legs {
            case .stand: legs = outfit.longRobe ? ["....OOOOOOOO....", "....OOOOOOOO....", "....FFF..FFF...."]
                                                : [".....LL..LL.....", ".....LL..LL.....", "....FFF..FFF...."]
            case .stride: legs = outfit.longRobe ? ["....OOOOOOOO....", "...OOOOOOOOOO...", "..FFF......FFF.."]
                                                 : ["....LL....LL....", "...LL......LL...", "..FFF......FFF.."]
            case .sit: legs = outfit.longRobe ? ["....OOOOOOOOOO..", "............OO..", "............FFF."]
                                              : ["....LLLLLLLLLL..", "............LL..", "............FFF."]
            }
            let legColor: Color = switch outfit.legs {
            case .denim: AvatarPalette.denim
            case .outfit: cloth
            case .dark: cloth.mix(with: .black, by: 0.45)
            case .skin: skin
            }
            paint(legs, top: 20, ["L": legColor, "O": cloth, "F": AvatarPalette.shoe])
            var torso = outfit.rows
            // Typing: one hand up on the keys, then the other.
            if f.legs == .sit {
                torso[3] = f.typing == 0 ? "...OOOOOOOOOOS.." : "...OOOOOOOOOO..."
                torso[2] = f.typing == 0 ? torso[2] : String(torso[2].prefix(13)) + "S.."
            }
            paint(torso, top: 15, [
                "O": cloth, "D": cloth.mix(with: .black, by: 0.3), "L": cloth.mix(with: .white, by: 0.4),
                "S": skin, "W": AvatarPalette.white, "R": AvatarPalette.outline.mix(with: Color(hex: "E5553E"), by: 0.8),
                "P": legColor, "Y": AvatarPalette.gold,
            ], dy: bob)
        }

        // Head.
        paint(Self.head, top: 2, ["S": skin], dy: bob)
        // Face: eyes, blush, mouth. Facing right, so the eyes sit right of centre.
        let eyeY = 9 + bob
        for x in [6, 10] {
            for (dx, dy, kind) in Self.eye(a.eyes, blink: f.blink) {
                fills[Point(x: x + dx, y: eyeY + dy)] = switch kind {
                case 0: AvatarPalette.outline
                case 1: AvatarPalette.white
                default: (a.eyes == 4 ? Color(hex: "3E7BFF") : Color(hex: "6B4630"))
                }
            }
        }
        fills[Point(x: 5, y: 12 + bob)] = AvatarPalette.blush
        fills[Point(x: 12, y: 12 + bob)] = AvatarPalette.blush
        fills[Point(x: 9, y: 13 + bob)] = AvatarPalette.mouth
        if f.talk { fills[Point(x: 9, y: 14 + bob)] = AvatarPalette.mouth; fills[Point(x: 10, y: 13 + bob)] = AvatarPalette.mouth }

        // Front hair, and its shine.
        paint(style.rows, top: 0, ["H": hair], dy: bob)
        for (x, y) in style.shine where fills[Point(x: x, y: y + bob)] != nil {
            fills[Point(x: x, y: y + bob)] = hair.mix(with: .white, by: 0.35)
        }

        // Accessory, on top.
        let accessory = Self.accessory(a.accessory)
        paint(accessory.rows, top: accessory.top, [
            "A": cloth, "a": cloth.mix(with: .black, by: 0.3), "G": AvatarPalette.gold, "K": AvatarPalette.outline,
            "W": AvatarPalette.white.opacity(0.55), "P": Color(hex: "FF8FB1"), "Y": Color(hex: "FFE066"),
            "V": Color(hex: "5FCB91"), "v": Color(hex: "3C9A68"),
        ], dy: bob)

        // Outline: every empty pixel touching the figure.
        if f.headOnly { fills = fills.filter { $0.key.y <= 14 + bob } }
        var outlined = fills
        for point in fills.keys {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = Point(x: point.x + dx, y: point.y + dy)
                if fills[n] == nil { outlined[n] = AvatarPalette.outline }
            }
        }
        var map = PixelMap()
        map.pixels = outlined
        return map
    }

    static let head = [
        ".....SSSSSS.....",
        "...SSSSSSSSSS...",
        "..SSSSSSSSSSSS..",
        "..SSSSSSSSSSSS..",
        "..SSSSSSSSSSSS..",
        "..SSSSSSSSSSSS..",
        "..SSSSSSSSSSSS..",
        "..SSSSSSSSSSSS..",
        "..SSSSSSSSSSSS..",
        "..SSSSSSSSSSSS..",
        "..SSSSSSSSSSSS..",
        "...SSSSSSSSSS...",
        ".....SSSSSS.....",
    ]

    /// (dx, dy, kind): 0 dark, 1 shine, 2 iris. Two pixels wide, three tall.
    static func eye(_ style: Int, blink: Bool) -> [(Int, Int, Int)] {
        if blink { return [(0, 2, 0), (1, 2, 0)] }
        switch style % 6 {
        case 0: return [(0, 0, 0), (1, 0, 0), (0, 1, 1), (1, 1, 0), (0, 2, 2), (1, 2, 2)]
        case 1: return [(1, 1, 0), (1, 2, 0)]
        case 2: return [(0, 2, 0), (1, 1, 0)]
        case 3: return [(0, 1, 0), (1, 1, 0), (0, 2, 0), (1, 2, 2)]
        case 4: return [(0, 0, 0), (1, 0, 0), (0, 1, 1), (1, 1, 2), (0, 2, 2), (1, 2, 1)]
        default: return [(0, 2, 0), (1, 2, 0), (1, 1, 0)]
        }
    }

    static func accessory(_ index: Int) -> (rows: [String], top: Int) {
        switch index % 8 {
        case 1: // Glasses.
            return ([
                ".....KKKK.KKKK..",
                ".....KWWKKKWWK..",
                ".....KKKK.KKKK..",
            ], 9)
        case 2: // Headband.
            return ([".AAAAAAAAAAAAAA.", "..............aa", "..............a."], 5)
        case 3: // Cap with a brim.
            return ([
                "....AAAAAAA.....",
                "..AAAAAAAAAAA...",
                ".AAAAAAAAAAAAA..",
                ".aaaaaaaaaaaaaaa",
            ], 1)
        case 4: // Crown.
            return ([
                "....G..G..G.....",
                "....GG.GG.GG....",
                "....GGGGGGGG....",
                "....GYGGGGYG....",
            ], -2)
        case 5: // Headphones.
            return ([
                "...KKKKKKKKKK...",
                "..K..........K..",
                ".K............K.",
                ".K............K.",
                ".K............K.",
                ".K............K.",
                "AA............AA",
                "AA............AA",
                "AA............AA",
            ], 0)
        case 6: // Flower.
            return ([
                "............P.P.",
                "............YPY.",
                "............P.P.",
            ], 2)
        case 7: // A sprout.
            return ([
                ".......VV.......",
                "......Vv.vV.....",
                "........v.......",
            ], -2)
        default: return ([], 0)
        }
    }
}

private struct HairStyle {
    var rows: [String]
    var shine: [(Int, Int)] = [(5, 2), (6, 2), (4, 3)]

    static let all: [HairStyle] = [
        // Short.
        HairStyle(rows: [
            "................",
            "....HHHHHHH.....",
            "..HHHHHHHHHHH...",
            ".HHHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHHH.HHHH.HHHH.",
            ".HHH....H...HHH.",
            ".HH..........HH.",
            ".HH..........H..",
            ".H..............",
        ]),
        // Spiky.
        HairStyle(rows: [
            "..H...H...H.....",
            "..HH.HHH.HHH.H..",
            ".HHHHHHHHHHHHHH.",
            "HHHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHHH",
            ".HHHHHHHHHHHHHH.",
            "HHHH.HH.HHH.HHH.",
            ".HH...H...H..HH.",
            ".HH...........H.",
            ".H..............",
        ], shine: [(5, 2), (6, 1), (4, 3)]),
        // Bob.
        HairStyle(rows: [
            "................",
            "....HHHHHHHH....",
            "..HHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHH.........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HHH........HHH.",
            "..HH........HH..",
        ]),
        // Long.
        HairStyle(rows: [
            "................",
            "....HHHHHHHH....",
            "..HHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHHHH.HHHHHHHH.",
            ".HHH.....H...HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".BB..........BB.",
            ".BB..........BB.",
            ".BBB........BBB.",
            ".BBB........BBB.",
            ".BBB........BBB.",
            "..BB........BB..",
        ]),
        // Ponytail.
        HairStyle(rows: [
            "................",
            "....HHHHHHH.....",
            "..HHHHHHHHHHH...",
            ".HHHHHHHHHHHHH..",
            "HHHHHHHHHHHHHHH.",
            "HHHHHHHHHHHHHHH.",
            "BHHHH.HHHH.HHHH.",
            "BHH.....H...HHH.",
            "BBH..........HH.",
            "BB...........H..",
            "BB..............",
            "BB..............",
            "BB..............",
            ".B..............",
        ]),
        // Side swoop.
        HairStyle(rows: [
            "................",
            "...HHHHHHHH.....",
            "..HHHHHHHHHHH...",
            ".HHHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHH.HHH.",
            ".HHHHHHH.....HH.",
            ".HHHH........HH.",
            ".HH..........H..",
            ".H..............",
        ]),
        // The sage: long and flowing, with a beard.
        HairStyle(rows: [
            "................",
            "....HHHHHHHH....",
            "..HHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHHH.HHHHH.HHH.",
            ".HHH.........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HH..........HH.",
            ".HH...HHHHH..HH.",
            ".BB..HHHHHHH.BB.",
            ".BB..HHHHHHH.BB.",
            ".BBB..HHHHH.BBB.",
            "..BB...HHH..BB..",
            "........H.......",
        ]),
        // Twin buns.
        HairStyle(rows: [
            ".HHH.......HHH..",
            "HHHHHHHHHHHHHHH.",
            "HHHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HHH.HHHHHH.HHH.",
            ".HH....H.....HH.",
            ".HH..........HH.",
            ".H...........H..",
        ], shine: [(2, 0), (12, 0), (5, 2)]),
        // Messy crest.
        HairStyle(rows: [
            "......HHH.......",
            ".....HHHHH......",
            "...HHHHHHHHH....",
            "..HHHHHHHHHHH...",
            ".HHHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHHHHHHHHHHHH.",
            ".HH.H.HH.H.HHHH.",
            ".H...........HH.",
            "..............H.",
        ], shine: [(7, 0), (6, 1), (5, 3)]),
    ]
}

private struct Outfit {
    enum Legs { case denim, outfit, dark, skin }
    var rows: [String]
    var legs: Legs
    var longRobe = false

    static let all: [Outfit] = [
        // Tee.
        Outfit(rows: [
            "....OOOOOOOO....",
            "...OOOOOOOOOO...",
            "...OOOOOOOOOO...",
            "...SDDDDDDDDS...",
            "....PPPPPPPP....",
        ], legs: .denim),
        // Hoodie.
        Outfit(rows: [
            "...DOOOOOOOOD...",
            "...OOOLLOOOOO...",
            "...OOOOOOOOOO...",
            "...SOOOLLLOOS...",
            "....PPPPPPPP....",
        ], legs: .denim),
        // Overalls.
        Outfit(rows: [
            "....LLOOOOLL....",
            "...LLOOOOOOLL...",
            "...LOOOYYOOOL...",
            "...SOOOOOOOOS...",
            "....OOOOOOOO....",
        ], legs: .outfit),
        // Suit and tie.
        Outfit(rows: [
            "....OOWRWOOO....",
            "...OOOWRWOOOO...",
            "...OOOORROOOO...",
            "...SOOOOOOOOS...",
            "....DDDDDDDD....",
        ], legs: .dark),
        // Dress.
        Outfit(rows: [
            "....OOOOOOOO....",
            "...LOOOOOOOOL...",
            "...LOOOOOOOOL...",
            "...SOOOOOOOOS...",
            "...OOOOOOOOOO...",
        ], legs: .skin),
        // Robe.
        Outfit(rows: [
            "....OOLLLOOO....",
            "...OOOOLOOOOO...",
            "...OOOOLOOOOO...",
            "...SYYYYYYYYS...",
            "...OOOOLOOOOO...",
        ], legs: .outfit, longRobe: true),
        // Armour.
        Outfit(rows: [
            "....LLLLLLLL....",
            "...LDDDDDDDDL...",
            "...ODDLLDDDDO...",
            "...SDDDDDDDDS...",
            "....PPPPPPPP....",
        ], legs: .denim),
    ]
}
