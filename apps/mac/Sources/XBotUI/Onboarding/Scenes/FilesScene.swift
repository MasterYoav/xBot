import SwiftUI

/// Step 8, Let your agents into your files: Desktop, Documents and Downloads, each locked; one
/// after another is asked about, its lock turns into a check and the folder is allowed.
struct FilesScene: View {
    init() {}

    private enum Script {
        static let loop = 24.0
        static let appear = [0.4, 0.8, 1.2]
        /// When each folder is asked about; it's allowed a beat and a half later.
        static let asks = [3.0, 6.0, 9.0]
        static let askTakes = 1.5
        static let finalFrame = 20.0
    }

    private var folders: [(glyph: String, name: String)] {
        [("menubar.dock.rectangle", String(localized: "Desktop")),
         ("doc", String(localized: "Documents")),
         ("arrow.down.circle", String(localized: "Downloads"))]
    }

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat) { time in
            SceneStage { size in
                ZStack {
                    AmbientLight()
                    HStack(spacing: Space.xxl + Space.xl) {
                        ForEach(folders.indices, id: \.self) { i in
                            folder(i, time)
                        }
                    }
                    .opacity(time.seam)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    private func folder(_ i: Int, _ time: SceneTime) -> some View {
        let appear = Ease.spring(time.beat(Script.appear[i], 1.2), bounce: 0.15)
        let ask = Script.asks[i]
        let asking = time.after(ask) && !time.after(ask + Script.askTakes)
        let allowed = time.after(ask + Script.askTakes)
        let attention = Ease.hop(time.beat(ask, Script.askTakes))
        let morph = time.beat(ask + Script.askTakes, 1.2)
        let size = SceneMetrics.folder
        return VStack(spacing: Space.m) {
            ZStack {
                // The light it's allowed in: a soft green pool and a ring that spreads once.
                Circle()
                    .fill(RadialGradient(colors: [Palette.successTint, .clear], center: .center, startRadius: 0,
                                         endRadius: size * 0.8))
                    .frame(width: size * 1.8, height: size * 1.8)
                    .opacity(Ease.out(morph))
                if allowed && morph < 1 {
                    Circle()
                        .strokeBorder(Palette.success, lineWidth: 2)
                        .frame(width: Ease.lerp(size * 0.6, size * 1.7, Ease.out(morph)),
                               height: Ease.lerp(size * 0.6, size * 1.7, Ease.out(morph)))
                        .opacity(1 - morph)
                }
                FolderIcon(glyph: folders[i].glyph, size: size)
                    .scaleEffect(1 + 0.05 * attention)
                    .overlay(alignment: .bottomTrailing) {
                        badge(asking: asking, allowed: allowed, morph: morph,
                              shake: asking ? sin(time.t * 26) * 5 * (1 - time.beat(ask, Script.askTakes)) : 0)
                            .offset(x: Space.xs, y: Space.xs)
                    }
            }
            .frame(width: size * 1.3, height: size * 1.1)
            Text(folders[i].name).titleText().foregroundStyle(Palette.textPrimary)
            status(asking: asking, allowed: allowed)
        }
        .opacity(Ease.out(time.beat(Script.appear[i], 0.8)))
        .offset(y: Ease.lerp(SceneMotion.rise * 1.5, 0, appear))
    }

    /// The lock that becomes a check: the lock tips away and shrinks as the check grows in, and
    /// the disc turns from neutral to green.
    private func badge(asking: Bool, allowed: Bool, morph: Double, shake: Double) -> some View {
        let m = allowed ? Ease.spring(morph, bounce: 0.25) : 0
        return ZStack {
            Circle().fill(Palette.raised)
            Circle().fill(Palette.success).scaleEffect(m)
            Circle().strokeBorder(Palette.hairline)
            Image(systemName: "lock.fill")
                .font(.system(size: SceneMetrics.folderBadge * 0.42, weight: .semibold))
                .foregroundStyle(asking ? Palette.warning : Palette.textSecondary)
                .rotationEffect(.degrees(shake - 40 * min(1, morph * 2)))
                .scaleEffect(1 - min(1, morph * 2.2))
                .opacity(1 - min(1, morph * 2))
            CheckShape()
                .trim(from: 0, to: Ease.out(max(0, morph * 1.6 - 0.3)))
                .stroke(Palette.textInverse, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: SceneMetrics.folderBadge * 0.4, height: SceneMetrics.folderBadge * 0.34)
        }
        .frame(width: SceneMetrics.folderBadge, height: SceneMetrics.folderBadge)
        .shadow(color: SceneShadow.ink.opacity(0.15), radius: 3, y: 1.5)
    }

    private func status(asking: Bool, allowed: Bool) -> some View {
        let (text, ink, fill): (String, Color, Color) =
            allowed ? (String(localized: "Allowed"), Palette.success, Palette.successTint)
            : asking ? (String(localized: "Asking"), Palette.warning, Palette.warningTint)
            : (String(localized: "Not yet"), Palette.textTertiary, Palette.hover)
        return HStack(spacing: Space.xs) {
            Circle().fill(ink).frame(width: Metrics.dot, height: Metrics.dot)
            Text(text).labelText()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, Space.s)
        .frame(height: Space.l + 2)
        .background(Capsule().fill(fill))
    }
}

/// A Finder folder: a back with its tab, a front face a shade lighter, and the folder's glyph
/// pressed into it.
private struct FolderIcon: View {
    let glyph: String
    let size: CGFloat

    var body: some View {
        let w = size, h = size * 0.78
        ZStack(alignment: .bottom) {
            // Back and tab.
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: size * 0.07, bottomLeading: size * 0.08,
                                                      bottomTrailing: size * 0.08, topTrailing: size * 0.07),
                                   style: .continuous)
                .fill(ScenePalette.folderTab)
                .frame(width: w, height: h)
                .overlay(alignment: .topLeading) {
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: size * 0.06, topTrailing: size * 0.06),
                                           style: .continuous)
                        .fill(ScenePalette.folderTab)
                        .frame(width: w * 0.4, height: size * 0.12)
                        .offset(y: -size * 0.08)
                }
            // Front.
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(LinearGradient(colors: [ScenePalette.folder, ScenePalette.folderTab.opacity(0.92)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: h * 0.86)
                .overlay(
                    Image(systemName: glyph)
                        .font(.system(size: size * 0.26, weight: .medium))
                        .foregroundStyle(ScenePalette.folderGlyph.opacity(0.75))
                        .offset(y: size * 0.03)
                )
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.35)).frame(height: 1).padding(.horizontal, size * 0.04)
                }
        }
        .frame(width: w, height: h + size * 0.08, alignment: .bottom)
        .shadow(color: SceneShadow.ink.opacity(0.14), radius: 6, y: 4)
    }
}
