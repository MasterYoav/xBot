import SwiftUI

/// Step 5, Changes, files and a terminal: the inspector slides in beside a finished chat with the
/// files the agent changed; a diff line is written and turns green; a terminal types `swift test`
/// and prints a green line; the pull request's checks pass.
struct InspectorScene: View {
    init() {}

    private enum Script {
        static let loop = 32.0
        static let toggle = 0.8
        static let slide = 1.4
        static let files = [2.8, 3.2, 3.6]
        static let diff = 4.4
        static let typeLine = 5.2
        static let typeTakes = 2.2
        static let green = 7.8
        static let terminal = 9.0
        static let command = 10.0
        static let commandTakes = 1.6
        static let building = 12.0
        static let passed = 13.6
        static let pullRequest = 15.0
        static let checksPass = 17.6
        static let finalFrame = 29.0
    }

    private enum Layout {
        static let inspector: CGFloat = 262
        static let terminal = CGSize(width: 300, height: 112)
    }

    private let added = "if token.expiresSoon {"

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat) { time in
            SceneStage { size in
                ZStack {
                    AmbientLight()
                    window(time)
                        .opacity(time.seam)
                        .offset(y: Ease.lerp(SceneMotion.rise, 0, Ease.out(time.seam)))
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    private func window(_ time: SceneTime) -> some View {
        let slide = Ease.spring(time.beat(Script.slide, 1.6))
        return MockWindow {
            HStack(spacing: Space.s) {
                Text(String(localized: "Fix sign-in")).font(Typography.chip).foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "sidebar.right")
                    .font(Typography.body)
                    .foregroundStyle(time.after(Script.toggle) ? Palette.accent : Palette.textSecondary)
                    .frame(width: Metrics.iconButton - 6, height: Metrics.iconButton - 6)
                    .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Palette.hover.opacity(time.after(Script.toggle) ? 1 : 0)))
            }
        } content: {
            ZStack(alignment: .topLeading) {
                chat(time)
                    .frame(width: SceneMetrics.mockWindow.width - Layout.inspector * CGFloat(slide))
                terminal(time)
                    .position(x: Space.l + Layout.terminal.width / 2,
                              y: SceneMetrics.mockWindow.height - Metrics.titleBar - Space.l - Layout.terminal.height / 2)
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.hairline).frame(width: 1)
                    inspector(time)
                }
                .frame(width: Layout.inspector)
                .background(Palette.sidebar)
                .offset(x: SceneMetrics.mockWindow.width - Layout.inspector * CGFloat(slide))
            }
            .clipped()
        }
    }

    /// The finished conversation, quietly: a request and the start of a reply.
    private func chat(_ time: SceneTime) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Spacer(minLength: 0)
                GhostLine(width: 150, color: Palette.raised, height: Space.xl + 2)
                    .overlay(Capsule().strokeBorder(Palette.hairline))
            }
            HStack(spacing: Space.xs + 2) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                Text(String(localized: "Fixed, with a test")).font(Typography.chip).foregroundStyle(Palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                GhostLine(width: 240)
                GhostLine(width: 280)
                GhostLine(width: 180)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: The inspector

    private var files: [(badge: String, name: String, plus: Int, minus: Int)] {
        [("M", "Session.swift", 12, 3), ("M", "SignInView.swift", 4, 1), ("A", "SessionTests.swift", 28, 0)]
    }

    private func inspector(_ time: SceneTime) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(String(localized: "Changes")).labelText().foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
                Text(verbatim: "+44").font(Typography.label).foregroundStyle(Palette.success)
                Text(verbatim: "−4").font(Typography.label).foregroundStyle(Palette.failure)
            }
            .padding(.horizontal, Space.xs)
            VStack(spacing: Space.xxs) {
                ForEach(files.indices, id: \.self) { i in
                    fileRow(files[i], selected: i == 0 && time.after(Script.diff))
                        .modifier(Arrive(progress: time.beat(Script.files[i], 0.8)))
                }
            }
            diff(time)
                .modifier(Arrive(progress: time.beat(Script.diff, 1)))
            pullRequest(time)
                .modifier(Arrive(progress: time.beat(Script.pullRequest, 1)))
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fileRow(_ file: (badge: String, name: String, plus: Int, minus: Int), selected: Bool) -> some View {
        HStack(spacing: Space.s) {
            Text(verbatim: file.badge)
                .font(Typography.label)
                .foregroundStyle(file.badge == "A" ? Palette.success : Palette.warning)
                .frame(width: Space.l, height: Space.l)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(file.badge == "A" ? Palette.successTint : Palette.warningTint))
            Text(verbatim: file.name).font(Typography.caption).foregroundStyle(Palette.textPrimary).lineLimit(1)
            Spacer(minLength: 0)
            Text(verbatim: "+\(file.plus)").font(Typography.label).foregroundStyle(Palette.success)
            if file.minus > 0 {
                Text(verbatim: "−\(file.minus)").font(Typography.label).foregroundStyle(Palette.failure)
            }
        }
        .padding(.horizontal, Space.xs + 2)
        .frame(height: Metrics.row - 4)
        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .fill(selected ? Palette.raised : .clear))
    }

    /// Four lines of Session.swift: a line removed, its replacement typed in, then accepted.
    private func diff(_ time: SceneTime) -> some View {
        let typed = Int(Double(added.count) * time.beat(Script.typeLine, Script.typeTakes))
        let green = Ease.out(time.beat(Script.green, 1))
        return VStack(alignment: .leading, spacing: 0) {
            diffLine(" 14", "  let token = session.token", sign: " ")
            diffLine(" 15", "  if token.expiry < .now {", sign: "−", tint: ScenePalette.diffRemoved, ink: Palette.failure)
            diffLine(" 15", "  " + String(added.prefix(typed)) + (typed < added.count && time.after(Script.typeLine) ? "▍" : ""),
                     sign: "+", tint: Palette.successTint.opacity(green), ink: Palette.success.opacity(0.35 + 0.65 * green))
            diffLine(" 16", "    try await refresh()", sign: " ")
        }
        .padding(.vertical, Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Palette.terminalBackground))
        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).strokeBorder(Palette.hairline))
    }

    private func diffLine(_ number: String, _ code: String, sign: String, tint: Color = .clear, ink: Color = Palette.textTertiary) -> some View {
        HStack(spacing: Space.xs) {
            Text(verbatim: number).foregroundStyle(Palette.textTertiary.opacity(0.7))
            Text(verbatim: sign).foregroundStyle(ink)
            Text(verbatim: code).foregroundStyle(Palette.textPrimary.opacity(sign == " " ? 0.55 : 0.9)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(SceneType.diff)
        .padding(.horizontal, Space.xs + 2)
        .frame(height: 16)
        .background(tint)
    }

    private func pullRequest(_ time: SceneTime) -> some View {
        let passed = time.after(Script.checksPass)
        let pop = Ease.spring(time.beat(Script.checksPass, 0.8), bounce: 0.2)
        return VStack(alignment: .leading, spacing: Space.xs + 2) {
            Text(String(localized: "Pull request #42")).labelText().foregroundStyle(Palette.textTertiary)
            HStack(spacing: Space.s) {
                ZStack {
                    if passed {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.success).scaleEffect(pop)
                    } else {
                        Circle().trim(from: 0, to: 0.7)
                            .stroke(Palette.running, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .frame(width: 11, height: 11)
                            .rotationEffect(.degrees(time.t * 400))
                    }
                }
                .font(Typography.body)
                .frame(width: Space.l)
                Text(passed ? String(localized: "All checks passed") : String(localized: "Running checks…"))
                    .font(Typography.chip)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                HStack(spacing: Space.xs) {
                    Circle().fill(passed ? Palette.success : Palette.running).frame(width: Metrics.dot, height: Metrics.dot)
                    Text(passed ? String(localized: "Passed") : String(localized: "Running")).labelText()
                }
                .foregroundStyle(passed ? Palette.success : Palette.running)
                .padding(.horizontal, Space.s)
                .frame(height: Space.l + 2)
                .background(Capsule().fill(passed ? Palette.successTint : Palette.runningTint))
            }
            .padding(.horizontal, Space.s)
            .frame(height: Metrics.row + 6)
            .raisedSurface(radius: Radius.medium)
        }
    }

    // MARK: The terminal

    private func terminal(_ time: SceneTime) -> some View {
        let command = "swift test"
        let typed = Int(Double(command.count) * time.beat(Script.command, Script.commandTakes))
        let typing = time.after(Script.command) && typed < command.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "terminal").font(SceneType.glyph)
                    Text(verbatim: "zsh").font(Typography.caption)
                }
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Space.s)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: Radius.small - 1, style: .continuous).fill(Palette.raised))
                Image(systemName: "plus").font(SceneType.glyph).foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s)
            .frame(height: Metrics.terminalTitleBar - 6)
            .background(Palette.inset)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text(verbatim: "my-app % ").foregroundStyle(Palette.accent)
                    Text(verbatim: String(command.prefix(typed))).foregroundStyle(Palette.textPrimary)
                    if typing || !time.after(Script.building) {
                        Text(verbatim: "▍").foregroundStyle(Palette.textSecondary)
                            .opacity(typing || Int(time.t * 2.4) % 2 == 0 ? 1 : 0)
                    }
                }
                if time.after(Script.building) {
                    Text(String(localized: "Building for debugging…")).foregroundStyle(Palette.textTertiary)
                }
                if time.after(Script.passed) {
                    Text(String(localized: "✔ 48 tests passed in 2.1 seconds"))
                        .foregroundStyle(Palette.success)
                        .modifier(Arrive(progress: time.beat(Script.passed, 0.6)))
                }
            }
            .font(SceneType.terminal)
            .padding(Space.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.terminalBackground)
        }
        .frame(width: Layout.terminal.width, height: Layout.terminal.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline))
        .floatingShadow()
        .scaleEffect(Ease.lerp(0.94, 1, Ease.spring(time.beat(Script.terminal, 1.2))), anchor: .bottomLeading)
        .opacity(Ease.out(time.beat(Script.terminal, 0.8)))
    }
}
