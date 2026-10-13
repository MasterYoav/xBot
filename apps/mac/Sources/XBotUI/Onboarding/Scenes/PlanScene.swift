import SwiftUI

/// Step 4, Plans you can edit: a plan card unfolds step by step; the person drags the test step up
/// above the fix (test first); then the steps run and tick off, one after another.
struct PlanScene: View {
    init() {}

    private enum Script {
        static let loop = 28.0
        static let card = 0.6
        static let unfold = 1.6
        static let unfoldGap = 0.55
        static let cursorIn = 4.6
        static let grab = 5.8
        static let drag = 6.2
        static let dragTakes = 1.6
        static let drop = 7.8
        static let cursorOut = 8.6
        /// When each step (in the new order) starts running; it ticks one and a half beats later.
        static let runs = [9.6, 11.4, 13.2, 15.0]
        static let runTakes = 1.5
        static let finalFrame = 25.0
    }

    private enum Layout {
        static let width: CGFloat = 430
        static let row: CGFloat = 44
        static let header: CGFloat = 64
    }

    /// The plan as proposed; the third step is dragged above the second.
    private var steps: [String] {
        [String(localized: "Read how sign-in keeps the session"),
         String(localized: "Refresh the token before it expires"),
         String(localized: "Write a test that signs in after an hour"),
         String(localized: "Run the tests and open a pull request")]
    }

    /// The order they run in, after the drag.
    private let runOrder = [0, 2, 1, 3]

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat) { time in
            SceneStage { size in
                ZStack {
                    AmbientLight()
                    card(time)
                        .opacity(time.seam)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    private func card(_ time: SceneTime) -> some View {
        let appear = Ease.spring(time.beat(Script.card, 1.2))
        let unfolded = (0..<steps.count).map { Ease.out(time.beat(Script.unfold + Double($0) * Script.unfoldGap, 1)) }
        let height = Layout.header + unfolded.reduce(0) { $0 + CGFloat($1) } * Layout.row + Space.s
        let done = Script.runs.filter { time.after($0 + Script.runTakes) }.count
        return ZStack(alignment: .topLeading) {
            header(time, done: done)
            ForEach(steps.indices, id: \.self) { i in
                stepRow(i, time: time)
                    .opacity(unfolded[i])
                    .offset(y: Layout.header + y(of: i, time: time) - Layout.row * CGFloat(1 - unfolded[i]) * 0.5)
                    .zIndex(i == 2 ? 2 : 1)
            }
            cursor(time).zIndex(3)
        }
        .frame(width: Layout.width, height: height, alignment: .topLeading)
        .raisedSurface()
        .floatingShadow()
        .scaleEffect(Ease.lerp(0.96, 1, appear))
        .opacity(Ease.out(time.beat(Script.card, 0.8)))
        .frame(height: Layout.header + CGFloat(steps.count) * Layout.row + Space.s, alignment: .top)
    }

    private func header(_ time: SceneTime, done: Int) -> some View {
        let progress = Double(done) / Double(steps.count)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "list.bullet.clipboard")
                    Text(String(localized: "Plan"))
                }
                .font(Typography.chip)
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, Space.s)
                .frame(height: Metrics.chipHeight - 6)
                .background(Capsule().fill(Palette.accentTint))
                Text(String(localized: "Fix sign-in after an hour"))
                    .titleText()
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Text(String(localized: "\(done) of \(steps.count) done"))
                    .labelText()
                    .foregroundStyle(done == steps.count ? Palette.success : Palette.textTertiary)
                    .monospacedDigit()
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.hover)
                Capsule().fill(Palette.success)
                    .frame(width: (Layout.width - 2 * Space.l) * CGFloat(progress))
            }
            .frame(height: Metrics.progressHeight + 1)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
    }

    /// Where step `i` sits below the header: its slot, or on the way to its new one.
    private func y(of i: Int, time: SceneTime) -> CGFloat {
        let slot = { (k: Int) in CGFloat(k) * Layout.row }
        let drag = Ease.inOut(time.beat(Script.drag, Script.dragTakes))
        switch i {
        case 2:
            // The dragged step follows the pointer, then drops into its slot.
            return Ease.lerp(slot(2), slot(1), drag)
        case 1:
            // Makes way once the dragged step is past half of it.
            let makeWay = Ease.spring(time.beat(Script.drag + Script.dragTakes * 0.45, 1.1))
            return Ease.lerp(slot(1), slot(2), makeWay)
        default:
            return slot(i)
        }
    }

    private func stepRow(_ i: Int, time: SceneTime) -> some View {
        let position = runOrder.firstIndex(of: i) ?? i
        let start = Script.runs[position]
        let running = time.after(start) && !time.after(start + Script.runTakes)
        let tick = time.beat(start + Script.runTakes, 0.8)
        let isDone = time.after(start + Script.runTakes)
        let lifted = i == 2 ? Ease.out(time.beat(Script.grab, 0.6)) * (1 - Ease.out(time.beat(Script.drop, 0.8))) : 0
        return HStack(spacing: Space.m) {
            status(running: running, done: isDone, tick: tick, time: time)
            Text(steps[i])
                .font(Typography.body)
                .foregroundStyle(isDone ? Palette.textSecondary : Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary.opacity(0.6 + 0.4 * lifted))
        }
        .padding(.horizontal, Space.m)
        .frame(width: Layout.width - 2 * Space.s, height: Layout.row - Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
            .fill(Palette.raised.opacity(lifted > 0 ? 1 : 0)))
        .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
            .fill(running ? Palette.runningTint : Palette.inset.opacity(0)))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
            .strokeBorder(Palette.hairline.opacity(lifted * 2)))
        .shadow(color: SceneShadow.ink.opacity(0.16 * lifted), radius: 10 * lifted, y: 6 * lifted)
        .scaleEffect(1 + 0.03 * lifted)
        .padding(.horizontal, Space.s)
    }

    private func status(running: Bool, done: Bool, tick: Double, time: SceneTime) -> some View {
        ZStack {
            Circle().strokeBorder(Palette.textTertiary.opacity(done ? 0 : 0.8), lineWidth: 1.2)
            if running {
                Circle().trim(from: 0, to: 0.7)
                    .stroke(Palette.running, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(time.t * 400))
            }
            if done {
                Circle().fill(Palette.success).scaleEffect(Ease.spring(tick, bounce: 0.2))
                CheckShape()
                    .trim(from: 0, to: Ease.out(tick * 1.4))
                    .stroke(Palette.textInverse, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .padding(4)
            }
        }
        .frame(width: Space.l, height: Space.l)
    }

    /// The pointer: comes in, grabs the third step's handle, drags it up one slot, lets go.
    private func cursor(_ time: SceneTime) -> some View {
        let handle = CGPoint(x: Layout.width - Space.s - Space.m - 6, y: Layout.header + Layout.row * 2 + Layout.row / 2 - 2)
        let enter = Ease.out(time.beat(Script.cursorIn, 1.2))
        let drag = Ease.inOut(time.beat(Script.drag, Script.dragTakes))
        let leave = Ease.inOut(time.beat(Script.cursorOut, 1))
        let x = handle.x + Ease.lerp(70, 0, enter) + Ease.lerp(0, 40, leave)
        let y = handle.y + Ease.lerp(60, 0, enter) - Layout.row * CGFloat(drag) + Ease.lerp(0, 30, leave)
        let grabbing = time.after(Script.grab) && !time.after(Script.drop)
        return Image(systemName: grabbing ? "hand.raised.fill" : "hand.point.up.left.fill")
            .font(SceneType.pointer)
            .foregroundStyle(Palette.textPrimary)
            .shadow(color: Palette.window, radius: 0, x: 1, y: 1)
            .shadow(color: Palette.window, radius: 0, x: -1, y: -1)
            .scaleEffect(grabbing ? 0.92 : 1)
            .opacity(enter * (1 - leave))
            .position(x: x + 6, y: y + 8)
    }
}
