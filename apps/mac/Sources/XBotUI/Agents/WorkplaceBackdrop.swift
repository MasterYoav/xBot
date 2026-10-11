import SwiftUI
import XBotCore

/// The Agents tab's single environment, extending behind its header, crew and cards.
/// The stage's measured bottom keeps the terrain aligned with the interactive crew.
struct WorkplaceBackdrop: View {
    let setting: WorkplaceSetting
    let stageBottom: CGFloat
    @State private var stillDate = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let sceneHeight = WorkplaceBackdropLayout.sceneHeight(
                stageBottom: stageBottom, viewportHeight: geometry.size.height
            )
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { clock in
                let date = reduceMotion ? stillDate : clock.date
                ZStack(alignment: .topLeading) {
                    WorldGround(setting: setting, horizon: sceneHeight, date: date)
                    WorldScenery(setting: setting, date: date, width: geometry.size.width)
                        .frame(height: sceneHeight)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum WorkplaceBackdropLayout {
    static func sceneHeight(stageBottom: CGFloat, viewportHeight _: CGFloat) -> CGFloat {
        // Keep the scenery in the crew's measured coordinates; the view clips to
        // the viewport separately. Use only a one-point safe minimum for its frame.
        max(1, stageBottom)
    }
}

private struct WorldScenery: View {
    let setting: WorkplaceSetting
    let date: Date
    let width: CGFloat

    var body: some View {
        ZStack {
            switch setting {
            case .village: Scenery(date: date, width: width)
            case .skyRealm:
                SkyScenery(date: date, width: width)
                SkyScenery(date: date, width: width, front: true)
            case .underwater:
                UnderwaterScenery(date: date, width: width)
                UnderwaterScenery(date: date, width: width, front: true)
            case .moonbase:
                MoonbaseScenery(date: date, width: width)
                MoonbaseScenery(date: date, width: width, front: true)
            case .enchantedForest:
                EnchantedForestScenery(date: date, width: width)
                EnchantedForestScenery(date: date, width: width, front: true)
            }
        }
    }
}

/// Continue the same world below the crew instead of falling back to the user's photo.
/// This lower terrain also gives the status cards a calmer place to sit.
private struct WorldGround: View {
    let setting: WorkplaceSetting
    let horizon: CGFloat
    let date: Date

    var body: some View {
        Canvas { context, size in
            let base = WorldInks.floor(setting)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            let remaining = max(1, size.height - horizon)
            for i in 0..<Int(size.width / 12) + 24 {
                let x = CGFloat((i * 97 + 19) % max(1, Int(size.width)))
                let y = horizon + CGFloat((i * 43 + 7) % Int(remaining))
                let tile = CGRect(x: x, y: y, width: i % 4 == 0 ? 8 : 4, height: 4)
                context.fill(Path(tile), with: .color(WorldInks.detail(setting).opacity(0.18)))
                if setting == .underwater, i % 5 == 0 {
                    let lift = CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20))
                    let bubble = CGRect(x: x, y: y - lift, width: 6, height: 6)
                    context.stroke(Path(ellipseIn: bubble), with: .color(WorldInks.detail(setting).opacity(0.16)), lineWidth: 1)
                }
            }
        }
    }
}

/// Illustration inks are kept separate from app chrome and its semantic palette.
private enum WorldInks {
    static func floor(_ setting: WorkplaceSetting) -> Color {
        switch setting {
        case .village: Color(hex: "9A6A43")
        case .skyRealm: Color(hex: "3E7CC0")
        case .underwater: Color(hex: "081E3D")
        case .moonbase: Color(hex: "777E95")
        case .enchantedForest: Color(red: 20.0 / 255, green: 49.0 / 255, blue: 39.0 / 255)
        }
    }

    static func detail(_ setting: WorkplaceSetting) -> Color {
        switch setting {
        case .village: Color(hex: "7D5434")
        case .skyRealm: Color(hex: "A9DDFF")
        case .underwater: Color(hex: "74EAD5")
        case .moonbase: Color(hex: "B8C6D8")
        case .enchantedForest: Color(hex: "20603B")
        }
    }
}
