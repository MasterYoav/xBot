import SwiftUI
import XBotWorld

/// Step 10, Make it yours: the five worlds as small living postcards (their clouds drift, fish
/// swim, stars twinkle), dealt out one by one and floating gently, each with someone from the crew.
struct WorldsScene: View {
    init() {}

    private enum Script {
        static let loop = 24.0
        static let deal = 0.4
        static let dealGap = 0.35
        static let finalFrame = 20.0
    }

    /// Each postcard: its world, who's in it, how it's tilted, where it sits (in a 3 + 2 spread).
    private let cards: [(setting: WorkplaceSetting, member: SceneCrew.Member, tilt: Double, slot: CGPoint)] = [
        (.village, SceneCrew.forge, -3, CGPoint(x: -228, y: -78)),
        (.skyRealm, SceneCrew.headMaster, 1.5, CGPoint(x: 0, y: -92)),
        (.underwater, SceneCrew.quill, 3, CGPoint(x: 228, y: -74)),
        (.moonbase, SceneCrew.hawk, -2, CGPoint(x: -114, y: 92)),
        (.enchantedForest, SceneCrew.cto, 2.5, CGPoint(x: 114, y: 96)),
    ]

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat,
                   interval: SceneMotion.ambientInterval) { time in
            SceneStage { size in
                ZStack {
                    AmbientLight()
                    ForEach(cards.indices, id: \.self) { i in
                        postcard(i, time)
                            .position(x: size.width / 2 + cards[i].slot.x, y: size.height / 2 + cards[i].slot.y)
                    }
                }
                .frame(width: size.width, height: size.height)
                .opacity(time.seam)
            }
        }
    }

    private func postcard(_ i: Int, _ time: SceneTime) -> some View {
        let card = cards[i]
        let deal = time.beat(Script.deal + Double(i) * Script.dealGap, 1.6)
        let land = Ease.spring(deal, bounce: 0.15)
        // Floating: a slow bob and sway, out of step with the neighbours. Kept small, and well away
        // from the 0.2 Hz the design system asks looping motion to avoid.
        let phase = time.t * 2.2 + Double(i) * 1.3
        let bob = time.still ? 0 : sin(phase) * 3
        let sway = time.still ? 0 : sin(phase * 0.8 + 0.6) * 0.8
        let picture = CGSize(width: SceneMetrics.postcard.width - 2 * SceneMetrics.postcardBorder,
                             height: SceneMetrics.postcard.height - 2 * SceneMetrics.postcardBorder)
        return VStack(spacing: Space.xs + 2) {
            world(card, time: time, size: picture)
                .frame(width: picture.width, height: picture.height)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .padding(SceneMetrics.postcardBorder)
                .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.raised))
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline))
                .floatingShadow()
            HStack(spacing: Space.xs) {
                Image(systemName: card.setting.symbol)
                Text(card.setting.title)
            }
            .font(Typography.chip)
            .foregroundStyle(Palette.textSecondary)
        }
        .rotationEffect(.degrees(card.tilt + sway))
        .offset(y: CGFloat(bob) + Ease.lerp(40, 0, land))
        .scaleEffect(Ease.lerp(0.9, 1, land))
        .opacity(Ease.out(deal * 1.5))
    }

    /// The world's own art, drawn at its reference height and scaled down into the postcard, with
    /// one of the crew standing (or floating) in it.
    private func world(_ card: (setting: WorkplaceSetting, member: SceneCrew.Member, tilt: Double, slot: CGPoint),
                       time: SceneTime, size: CGSize) -> some View {
        let reference = WorldStage.height
        let scale = size.height / reference
        let artWidth = size.width / scale
        let floats = card.setting != .village
        let bob = floats && !time.still ? sin(time.t * 2.6 + Double(card.member.seed)) * 2 : 0
        let pixel = SceneMetrics.postcardPixel
        return ZStack(alignment: .topLeading) {
            WorldScenery(setting: card.setting, date: card.setting == .village ? time.worldDate(hour: 10) : time.date,
                         width: artWidth)
                .frame(width: artWidth, height: reference)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            ScenePerson(member: card.member, date: time.date, facing: card.tilt < 0 ? 1 : -1, pixel: pixel, nameTag: false)
                .offset(y: CGFloat(bob))
                .standing(at: size.width * 0.3, feet: size.height - (floats ? 26 : 74 * scale - 4 * pixel), pixel: pixel)
        }
    }
}
