import SwiftUI
import XBotWorld

/// Step 1, Welcome: the village at dawn. HeadMaster, Forge, Hawk and Quill walk in one by one,
/// turn to the middle and wave; then the xBot mark settles in the sky above them.
struct WelcomeScene: View {
    var setting: WorkplaceSetting = .village

    init(setting: WorkplaceSetting = .village) { self.setting = setting }

    /// The choreography, in beats.
    private enum Script {
        static let loop = 24.0
        /// Who comes in when, from which side, and where they stop (slot −1.5…1.5 around the middle).
        static let entrances: [(member: SceneCrew.Member, start: Double, fromLeft: Bool, slot: Double)] = [
            (SceneCrew.headMaster, 1, true, -0.5),
            (SceneCrew.forge, 2.8, false, 0.5),
            (SceneCrew.hawk, 4.6, true, -1.5),
            (SceneCrew.quill, 6.4, false, 1.5),
        ]
        static let walk = 4.0
        static let wave = 3.0
        static let mark = 11.0
        static let finalFrame = 20.0
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
        let date = setting == .village ? time.worldDate(hour: 6.8) : time.date
        let floor = size.height - 74
        let feet = floor + 18
        let spacing: CGFloat = 104
        return ZStack(alignment: .topLeading) {
            WorldScenery(setting: setting, date: date, width: size.width)
                .frame(width: size.width, height: size.height)

            // The first light: a warm haze over the horizon, behind the crew.
            RadialGradient(colors: [ScenePalette.glow, .clear], center: UnitPoint(x: 0.5, y: 0.78),
                           startRadius: 0, endRadius: size.width * 0.42)
                .opacity(0.6 * time.beat(0, 8))
                .blendMode(.plusLighter)

            mark(time, size: size, above: feet - 200)

            ForEach(Script.entrances.indices, id: \.self) { i in
                let entrance = Script.entrances[i]
                person(time, entrance: entrance, size: size, feet: feet, spacing: spacing, date: date)
            }
            .opacity(time.seam)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func person(_ time: SceneTime, entrance: (member: SceneCrew.Member, start: Double, fromLeft: Bool, slot: Double),
                        size: CGSize, feet: CGFloat, spacing: CGFloat, date: Date) -> some View {
        let home = size.width / 2 + CGFloat(entrance.slot) * spacing
        let offstage: CGFloat = entrance.fromLeft ? -60 : size.width + 60
        let walk = time.beat(entrance.start, Script.walk)
        // Walk in at an even pace, slowing over the last steps.
        let x = Ease.lerp(offstage, home, walk < 0.75 ? walk / 0.75 * 0.85 : 0.85 + Ease.out((walk - 0.75) / 0.25) * 0.15)
        let arrived = walk >= 1
        // Facing the way they walk, then turning to the middle.
        let facing: Double = arrived ? (entrance.slot < 0 ? 1 : -1) : (entrance.fromLeft ? 1 : -1)
        let waveStart = entrance.start + Script.walk + 0.4
        let waving = time.after(waveStart) && !time.after(waveStart + Script.wave)
        let hop = time.still ? 0 : Ease.hop(time.beat(entrance.start + Script.walk, 0.8)) * 6
        let pixel = SceneMetrics.crewPixel
        return ScenePerson(member: entrance.member, date: date, legs: arrived ? .stand : .stride, facing: facing)
            .overlay(alignment: .top) {
                if waving {
                    SceneBubble(text: "👋 " + greeting(entrance.member))
                        .scaleEffect(Ease.spring(time.beat(waveStart, 0.8), bounce: 0.15), anchor: .bottom)
                        .offset(y: -2 * pixel)
                }
            }
            .offset(y: -hop)
            .standing(at: x, feet: feet)
    }

    private func greeting(_ member: SceneCrew.Member) -> String {
        switch member.seed {
        case SceneCrew.headMaster.seed: String(localized: "Welcome!")
        case SceneCrew.forge.seed: String(localized: "Hi!")
        case SceneCrew.hawk.seed: String(localized: "Hello!")
        default: String(localized: "Morning!")
        }
    }

    private func mark(_ time: SceneTime, size: CGSize, above y: CGFloat) -> some View {
        let p = time.beat(Script.mark, 3)
        let settle = Ease.spring(p)
        let markSize: CGFloat = 92
        return ZStack {
            // A halo of morning light around it.
            Circle()
                .fill(RadialGradient(colors: [ScenePalette.glow, .clear], center: .center, startRadius: 0,
                                     endRadius: markSize * 1.1))
                .frame(width: markSize * 2.4, height: markSize * 2.4)
                .opacity(Ease.out(p))
            AppMarkView(size: markSize)
                .shadow(color: AvatarPalette.outline.opacity(0.25), radius: 14, y: 8)
                .scaleEffect(Ease.lerp(1.18, 1, settle))
                .offset(y: Ease.lerp(-36, 0, settle))
                .opacity(Ease.out(p * 1.6))
        }
        .opacity(time.seam)
        .position(x: size.width / 2, y: max(size.height * 0.26, y - markSize / 2))
    }
}
