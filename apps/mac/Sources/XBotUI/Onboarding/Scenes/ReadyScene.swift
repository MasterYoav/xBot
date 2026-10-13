import SwiftUI
import XBotWorld

/// Step 11, Ready: the crew gathered in the world, HeadMaster in the middle. A warm light rises
/// behind them, they hop once, one after another, and settle; HeadMaster invites the first ask.
struct ReadyScene: View {
    var setting: WorkplaceSetting = .village

    init(setting: WorkplaceSetting = .village) { self.setting = setting }

    private enum Script {
        static let loop = 22.0
        static let glow = 0.4
        static let hops = 2.4
        static let hopGap = 0.28
        static let hopTakes = 0.9
        static let notes = 3.4
        static let invite = 5.4
        static let finalFrame = 18.0
    }

    /// Who stands where (slot from the middle), and the little note each sings after the hop.
    private let crew: [(member: SceneCrew.Member, slot: Double, note: String)] = [
        (SceneCrew.forge, -2, "♪"), (SceneCrew.hawk, -1, "!"), (SceneCrew.headMaster, 0, ""),
        (SceneCrew.cto, 1, "♥"), (SceneCrew.quill, 2, "♪"),
    ]

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat) { time in
            SceneStage { size in
                stage(time, size)
            }
        }
        .modifier(WorldFrame())
    }

    private func stage(_ time: SceneTime, _ size: CGSize) -> some View {
        let date = setting == .village ? time.worldDate(hour: 9.5) : time.date
        let floats = setting != .village
        let feet = size.height - (floats ? 96 : 56)
        let spacing: CGFloat = 96
        let glow = Ease.out(time.beat(Script.glow, 4))
        return ZStack(alignment: .topLeading) {
            WorldScenery(setting: setting, date: date, width: size.width)
                .frame(width: size.width, height: size.height)

            // The light gathering behind them: rises once, then holds (no breathing loop).
            Rectangle()
                .fill(EllipticalGradient(colors: [ScenePalette.glow, .clear], center: .center,
                                         startRadiusFraction: 0, endRadiusFraction: 0.5))
                .frame(width: 600, height: 300)
                .scaleEffect(Ease.lerp(0.7, 1, glow))
                .opacity(glow * time.seam)
                .blendMode(.plusLighter)
                .position(x: size.width / 2, y: feet - 50)

            ForEach(crew.indices, id: \.self) { i in
                person(i, time: time, x: size.width / 2 + CGFloat(crew[i].slot) * spacing, feet: feet, date: date)
            }

            if time.after(Script.invite) {
                SceneBubble(text: String(localized: "Ask me anything!"))
                    .scaleEffect(Ease.spring(time.beat(Script.invite, 0.8), bounce: 0.2), anchor: .bottom)
                    .position(x: size.width / 2, y: feet - ScenePerson.box(SceneMetrics.crewPixel).height - Space.l)
                    .opacity(time.seam)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func person(_ i: Int, time: SceneTime, x: CGFloat, feet: CGFloat, date: Date) -> some View {
        let entry = crew[i]
        let start = Script.hops + Double(i) * Script.hopGap
        let hop = time.still ? 0 : Ease.hop(time.beat(start, Script.hopTakes))
        // A squash as they land, springing back.
        let land = time.beat(start + Script.hopTakes, 0.7)
        let squash = time.still || land <= 0 ? 0 : (1 - Ease.spring(land, bounce: 0.3)) * 0.1
        let noteShown = !entry.note.isEmpty && time.after(Script.notes + Double(i) * Script.hopGap)
            && !time.after(Script.notes + Double(i) * Script.hopGap + 3)
        let noteRise = time.beat(Script.notes + Double(i) * Script.hopGap, 6)
        // Everyone turned a little towards HeadMaster.
        let facing: Double = entry.slot < 0 ? 1 : (entry.slot > 0 ? -1 : 1)
        return ScenePerson(member: entry.member, date: date, facing: facing)
            .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
            .overlay(alignment: .top) {
                if noteShown {
                    Text(verbatim: entry.note)
                        .font(SceneType.song)
                        .foregroundStyle(AvatarPalette.gold)
                        .shadow(color: AvatarPalette.outline.opacity(0.5), radius: 0, x: 1, y: 1)
                        .offset(x: CGFloat(facing) * 18, y: Ease.lerp(18, -14, Ease.out(noteRise)))
                        .opacity(1 - Ease.in(noteRise * 2))
                }
            }
            .offset(y: -CGFloat(hop) * 16)
            .standing(at: x, feet: feet)
    }
}
