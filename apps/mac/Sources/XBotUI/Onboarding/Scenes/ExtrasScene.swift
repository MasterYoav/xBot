import SwiftUI

/// Step 7, Notes, abilities and automations: three cards flip in. A Markdown note writes its next
/// line; connectors switch on one by one; an automation's steps snap into place under a clock.
struct ExtrasScene: View {
    init() {}

    private enum Script {
        static let loop = 26.0
        static let flips = [0.6, 1.4, 2.2]
        static let flipTakes = 1.8
        static let typing = 4.4
        static let typingTakes = 4.0
        static let toggles = [4.0, 5.0, 6.0, 7.0]
        static let steps = [4.6, 5.6, 6.6]
        static let armed = 8.2
        static let finalFrame = 22.0
    }

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat) { time in
            SceneStage { size in
                ZStack {
                    AmbientLight()
                    HStack(alignment: .top, spacing: Space.xl) {
                        flipping(0, time) { note(time) }
                        flipping(1, time) { connectors(time) }
                        flipping(2, time) { automation(time) }
                    }
                    .opacity(time.seam)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    /// A card turning over from its edge, like a page, and settling.
    private func flipping<Content: View>(_ i: Int, _ time: SceneTime, @ViewBuilder content: () -> Content) -> some View {
        let p = time.beat(Script.flips[i], Script.flipTakes)
        let turn = Ease.spring(p, bounce: 0.12)
        return content()
            .padding(Space.l)
            .frame(width: SceneMetrics.extraCard.width, height: SceneMetrics.extraCard.height, alignment: .topLeading)
            .raisedSurface()
            .floatingShadow()
            .rotation3DEffect(.degrees(Ease.lerp(-92, 0, turn)), axis: (x: 0, y: 1, z: 0), anchor: .leading,
                              perspective: 0.55)
            .opacity(p > 0 ? 1 : 0)
            .offset(y: Ease.lerp(SceneMotion.rise, 0, Ease.out(p)))
    }

    private func cardHeader(_ symbol: String, _ title: String, _ tint: Color, _ tintFill: Color) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(Typography.chip)
                .foregroundStyle(tint)
                .frame(width: Space.xl, height: Space.xl)
                .background(RoundedRectangle(cornerRadius: Radius.small + 1, style: .continuous).fill(tintFill))
            Text(title).titleText().foregroundStyle(Palette.textPrimary)
        }
    }

    // MARK: A note

    private func note(_ time: SceneTime) -> some View {
        let line = String(localized: "Your crew, in a world")
        let typed = Int(Double(line.count) * time.beat(Script.typing, Script.typingTakes))
        let caret = time.still || Int(time.t * 2.4) % 2 == 0 || typed < line.count
        return VStack(alignment: .leading, spacing: Space.s) {
            cardHeader("doc.text", String(localized: "Notes"), Palette.accent, Palette.accentTint)
            Text(verbatim: "release-notes.md").font(Typography.label).foregroundStyle(Palette.textTertiary)
                .padding(.bottom, Space.xs)
            Text(String(localized: "What’s new")).font(Typography.emphasis).foregroundStyle(Palette.textPrimary)
            bullet(String(localized: "Sign-in that stays put"))
            bullet(String(localized: "Plans you can edit"))
            HStack(spacing: 0) {
                bullet(String(line.prefix(typed)))
                Text(verbatim: "▍").font(Typography.caption).foregroundStyle(Palette.accent).opacity(caret ? 1 : 0)
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.xs) {
                Image(systemName: "text.badge.checkmark")
                Text(String(localized: "Markdown"))
                Spacer(minLength: 0)
                Text(String(localized: "Saved"))
            }
            .foregroundStyle(Palette.textTertiary)
            .font(Typography.label)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs + 2) {
            Text(verbatim: "•").foregroundStyle(Palette.accent)
            Text(text).foregroundStyle(Palette.textSecondary).lineLimit(1)
        }
        .font(Typography.caption)
    }

    // MARK: Connectors

    private var apps: [(symbol: String, name: String)] {
        [("chevron.left.forwardslash.chevron.right", "GitHub"), ("calendar", String(localized: "Calendar")),
         ("number", "Slack"), ("paintpalette", "Figma")]
    }

    private func connectors(_ time: SceneTime) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            cardHeader("puzzlepiece.extension", String(localized: "Abilities"), Palette.running, Palette.runningTint)
            Text(String(localized: "Connectors")).labelText().foregroundStyle(Palette.textTertiary)
                .padding(.bottom, Space.xs)
            ForEach(apps.indices, id: \.self) { i in
                HStack(spacing: Space.s) {
                    Image(systemName: apps[i].symbol)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: Space.xl - 2, height: Space.xl - 2)
                        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Palette.inset))
                    Text(verbatim: apps[i].name).font(Typography.caption).foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                    SceneSwitch(on: Ease.spring(time.beat(Script.toggles[i], 0.8), bounce: 0.1))
                }
                .frame(height: Space.xl + 2)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: An automation

    private var steps: [(symbol: String, text: String)] {
        [("clock", String(localized: "Weekdays at 9:00")),
         ("eye", String(localized: "Hawk reviews open PRs")),
         ("bubble.left", String(localized: "Post a summary"))]
    }

    private func automation(_ time: SceneTime) -> some View {
        let armed = Ease.out(time.beat(Script.armed, 0.8))
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center) {
                cardHeader("bolt", String(localized: "Automations"), Palette.warning, Palette.warningTint)
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s) {
                ClockFace(hours: time.still ? 9 : 9 + time.t / 6)
                    .frame(width: Space.xl, height: Space.xl)
                Text(String(localized: "Daily review")).font(Typography.emphasis).foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.bottom, Space.xxs)
            ZStack(alignment: .topLeading) {
                // The thread the steps hang on, drawn as they arrive.
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 1.5, height: 2 * 34 * CGFloat(time.beat(Script.steps[0], Script.steps[2] - Script.steps[0])))
                    .offset(x: 11, y: 14)
                VStack(alignment: .leading, spacing: Space.s + 2) {
                    ForEach(steps.indices, id: \.self) { i in
                        stepRow(steps[i], progress: time.beat(Script.steps[i], 1.2))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.xs) {
                Circle().fill(Palette.success).frame(width: Metrics.dot, height: Metrics.dot)
                Text(String(localized: "On")).labelText()
            }
            .foregroundStyle(Palette.success)
            .padding(.horizontal, Space.s)
            .frame(height: Space.l + 2)
            .background(Capsule().fill(Palette.successTint))
            .opacity(armed)
            .scaleEffect(Ease.lerp(0.8, 1, Ease.spring(time.beat(Script.armed, 0.8), bounce: 0.2)), anchor: .leading)
        }
    }

    /// A step snapping into place: in from the right, a little tilted, then square with a small bounce.
    private func stepRow(_ step: (symbol: String, text: String), progress: Double) -> some View {
        let snap = Ease.spring(progress, bounce: 0.22)
        return HStack(spacing: Space.s) {
            Image(systemName: step.symbol)
                .font(SceneType.stepGlyph)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Space.xl - 2, height: Space.xl - 2)
                .background(Circle().fill(Palette.inset))
                .overlay(Circle().strokeBorder(Palette.hairline))
            Text(step.text).font(Typography.caption).foregroundStyle(Palette.textPrimary).lineLimit(1)
        }
        .offset(x: Ease.lerp(46, 0, snap))
        .rotationEffect(.degrees(Ease.lerp(6, 0, snap)), anchor: .leading)
        .opacity(Ease.out(progress * 2))
    }
}

/// A switch, drawn: the knob slides and the track fills with the accent as it turns on.
private struct SceneSwitch: View {
    /// 0 off, 1 on.
    let on: Double

    var body: some View {
        Capsule()
            .fill(Palette.hover)
            .overlay(Capsule().fill(Palette.accent).opacity(min(1, on)))
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: SceneShadow.ink.opacity(0.18), radius: 1, y: 0.5)
                    .padding(2)
                    .offset(x: Ease.lerp(0, 12, on))
            }
            .frame(width: 28, height: 16)
    }
}

/// A small clock with moving hands.
struct ClockFace: View {
    /// Hours past midnight; fractional hours move both hands.
    let hours: Double

    var body: some View {
        ZStack {
            Circle().fill(Palette.inset)
            Circle().strokeBorder(Palette.textTertiary, lineWidth: 1.2)
            hand(length: 0.26, angle: hours / 12 * 360, width: 1.8)
            hand(length: 0.36, angle: hours.truncatingRemainder(dividingBy: 1) * 360, width: 1.2)
            Circle().fill(Palette.warning).frame(width: 3, height: 3)
        }
    }

    private func hand(length: CGFloat, angle: Double, width: CGFloat) -> some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            Capsule()
                .fill(Palette.textPrimary)
                .frame(width: width, height: side * length)
                .offset(y: -side * length / 2)
                .rotationEffect(.degrees(angle))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}
