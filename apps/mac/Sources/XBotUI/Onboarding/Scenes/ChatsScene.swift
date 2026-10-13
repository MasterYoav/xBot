import SwiftUI
import XBotCore

/// Step 3, Projects and chats: a stylised xBot window. A folder drops into the sidebar and
/// becomes a project, a chat tab opens, a request goes in, the agent's tool calls run and fold into
/// one line, and the reply streams in word by word.
struct ChatsScene: View {
    init() {}

    /// The choreography, in beats.
    private enum Script {
        static let loop = 24.0
        static let folderAppears = 1.0
        static let folderFalls = 1.6
        static let folderLands = 3.0
        static let tabOpens = 3.8
        static let ask = 4.8
        static let tools = [5.8, 6.6, 7.4]
        static let toolTakes = 0.9
        static let fold = 9.2
        static let reply = 10.2
        /// Words a beat, about what a fast agent streams.
        static let wordsPerBeat = 4.0
        static let finalFrame = 21.0
    }

    /// The sidebar's rows: fixed so the falling folder knows where it lands.
    private enum Rows {
        static let height: CGFloat = 24
        static let gap: CGFloat = 2
        static let top: CGFloat = Space.m
        /// Home, Agents, the PROJECTS label, website, notes-app: the new project is the sixth row.
        static func centre(of index: Int) -> CGFloat {
            Metrics.titleBar + 1 + top + CGFloat(index) * (height + gap) + height / 2
        }
    }

    private let reply = String(localized: "Found it: the session expired before the redirect. I now refresh the token first, and added a test that signs in after an hour.")

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat) { time in
            SceneStage { size in
                ZStack {
                    AmbientLight()
                    window(time)
                        .overlay(alignment: .topLeading) { fallingFolder(time) }
                        .opacity(time.seam)
                        .offset(y: Ease.lerp(SceneMotion.rise, 0, Ease.out(time.seam)))
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    // MARK: The window

    private func window(_ time: SceneTime) -> some View {
        MockWindow {
            tabs(time)
        } content: {
            HStack(spacing: 0) {
                sidebar(time)
                    .frame(width: SceneMetrics.mockSidebar)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Palette.sidebar)
                Rectangle().fill(Palette.hairline).frame(width: 1)
                transcript(time)
            }
        }
    }

    private func tabs(_ time: SceneTime) -> some View {
        let open = Ease.spring(time.beat(Script.tabOpens, 1.4))
        return HStack(spacing: Space.xs) {
            tab(String(localized: "Release notes"), selected: !time.after(Script.tabOpens), dot: Palette.agent(.codex))
            tab(String(localized: "Fix sign-in"), selected: time.after(Script.tabOpens), dot: Palette.agent(.claude))
                // The tab opens like a drawer: its edge travels out, the label doesn't stretch.
                .mask(alignment: .leading) { Rectangle().scaleEffect(x: open, y: 1, anchor: .leading) }
                .opacity(Ease.out(time.beat(Script.tabOpens, 0.8)))
        }
        .padding(.leading, SceneMetrics.mockSidebar - 3 * SceneMetrics.trafficLight - 4 * Space.s - Space.m)
    }

    private func tab(_ title: String, selected: Bool, dot: Color) -> some View {
        HStack(spacing: Space.xs + 1) {
            Circle().fill(dot).frame(width: Metrics.dot, height: Metrics.dot)
            Text(title).font(Typography.chip).lineLimit(1)
        }
        .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
        .padding(.horizontal, Space.s + 2)
        .frame(height: Metrics.chipHeight - 4)
        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .fill(selected ? Palette.raised : .clear))
        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .strokeBorder(selected ? Palette.hairline : .clear))
    }

    // MARK: Sidebar

    private func sidebar(_ time: SceneTime) -> some View {
        let landed = time.after(Script.folderLands)
        let settle = time.beat(Script.folderLands, 1)
        return VStack(alignment: .leading, spacing: Rows.gap) {
            row(symbol: "house", String(localized: "Home"))
            row(symbol: "person.2", String(localized: "Agents"))
            Text(String(localized: "Projects"))
                .labelText()
                .foregroundStyle(Palette.textTertiary)
                .frame(height: Rows.height, alignment: .bottomLeading)
                .padding(.leading, Space.s)
            row(symbol: "folder", "website")
            row(symbol: "folder", "notes-app")
            row(symbol: "folder.fill", "my-app", tint: landed ? Palette.accent : .clear, selected: landed ? settle : 0)
                .opacity(landed ? 1 : 0)
        }
        .padding(.top, Rows.top)
        .padding(.horizontal, Space.s)
    }

    private func row(symbol: String, _ title: String, tint: Color? = nil, selected: Double = 0) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(Typography.caption)
                .foregroundStyle(tint ?? Palette.textSecondary)
                .frame(width: Space.l)
            Text(verbatim: title).font(Typography.body).foregroundStyle(Palette.textPrimary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s)
        .frame(height: Rows.height)
        .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .fill(Palette.raised.opacity(selected)))
        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .strokeBorder(Palette.hairline.opacity(selected)))
    }

    /// The folder, from above the window into its row: it falls, lands with a little squash, and
    /// the row takes its place with a ripple of the accent.
    private func fallingFolder(_ time: SceneTime) -> some View {
        let appear = time.beat(Script.folderAppears, 0.6)
        let fall = Ease.in(time.beat(Script.folderFalls, Script.folderLands - Script.folderFalls))
        let landX = Space.s + Space.s + Space.l / 2
        let landY = Rows.centre(of: 5)
        let startY: CGFloat = -46
        let y = Ease.lerp(startY, landY, fall)
        let size = Ease.lerp(44, 14, fall)
        let ripple = time.beat(Script.folderLands, 1.4)
        return ZStack {
            if !time.after(Script.folderLands) && time.after(Script.folderAppears) {
                Image(systemName: "folder.fill")
                    .font(.system(size: size))
                    .foregroundStyle(ScenePalette.folder)
                    .shadow(color: SceneShadow.ink.opacity(0.18), radius: 6 * (1 - fall), y: 6 * (1 - fall))
                    .rotationEffect(.degrees(-8 * (1 - fall)))
                    .opacity(Ease.out(appear))
                    .position(x: landX + Ease.lerp(70, 0, fall), y: y)
            }
            if time.after(Script.folderLands) && ripple < 1 {
                Circle()
                    .strokeBorder(Palette.accent, lineWidth: 1.5)
                    .frame(width: Ease.lerp(10, 60, Ease.out(ripple)), height: Ease.lerp(10, 60, Ease.out(ripple)))
                    .opacity(1 - ripple)
                    .position(x: landX, y: landY)
            }
        }
        .frame(width: SceneMetrics.mockWindow.width, height: SceneMetrics.mockWindow.height, alignment: .topLeading)
    }

    // MARK: Transcript

    private func transcript(_ time: SceneTime) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if time.after(Script.ask) {
                Text(String(localized: "Signing in fails after an hour. Can you fix it?"))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).fill(Palette.raised))
                    .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.hairline))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .modifier(Arrive(progress: time.beat(Script.ask, 1)))
            }
            if time.after(Script.tools[0]) { toolBlock(time) }
            if time.after(Script.reply) {
                let count = Int((time.t / SceneMotion.beat - Script.reply) * Script.wordsPerBeat) + 1
                let shown = words(reply, count)
                let done = shown.count >= reply.count
                (Text(shown) + Text(verbatim: done ? "" : " ▍").foregroundStyle(Palette.accent))
                    .readingText()
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if done { changes(time) }
            }
            Spacer(minLength: 0)
            composer
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var toolSteps: [(symbol: String, verb: String, target: String)] {
        [("doc.text.magnifyingglass", String(localized: "Read"), "Session.swift"),
         ("pencil", String(localized: "Edited"), "Session.swift"),
         ("terminal", String(localized: "Ran"), "swift test")]
    }

    /// Three tool rows, each spinning then ticked, that fold into one quiet line.
    private func toolBlock(_ time: SceneTime) -> some View {
        let fold = Ease.inOut(time.beat(Script.fold, 1.2))
        let rowHeight: CGFloat = 22
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.xs + 2) {
                Image(systemName: "chevron.right")
                    .font(SceneType.glyph)
                    .rotationEffect(.degrees(90 * (1 - fold)))
                Text(String(localized: "3 steps"))
                    .font(Typography.chip)
                Text(verbatim: "· " + toolSteps.map(\.verb).joined(separator: ", "))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .opacity(fold)
            }
            .foregroundStyle(Palette.textSecondary)
            .frame(height: rowHeight)
            .opacity(time.beat(Script.tools[0], 0.6))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(toolSteps.indices, id: \.self) { i in
                    if time.after(Script.tools[i]) {
                        toolRow(toolSteps[i], time: time, start: Script.tools[i])
                            .frame(height: rowHeight)
                            .modifier(Arrive(progress: time.beat(Script.tools[i], 0.6)))
                    }
                }
            }
            .padding(.leading, Space.m)
            .frame(height: rowHeight * CGFloat(Script.tools.filter { time.after($0) }.count) * (1 - fold), alignment: .top)
            .clipped()
            .opacity(1 - fold)
        }
    }

    private func toolRow(_ step: (symbol: String, verb: String, target: String), time: SceneTime, start: Double) -> some View {
        let done = time.after(start + Script.toolTakes)
        return HStack(spacing: Space.s) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                        .scaleEffect(Ease.spring(time.beat(start + Script.toolTakes, 0.6), bounce: 0.2))
                } else {
                    Circle().trim(from: 0, to: 0.7)
                        .stroke(Palette.running, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 10, height: 10)
                        .rotationEffect(.degrees(time.t * 400))
                }
            }
            .font(Typography.caption)
            .frame(width: Space.m)
            Image(systemName: step.symbol).font(Typography.caption).foregroundStyle(Palette.textTertiary)
            Text(step.verb).font(Typography.chip).foregroundStyle(Palette.textSecondary)
            Text(verbatim: step.target).font(Typography.mono).foregroundStyle(Palette.textTertiary)
        }
    }

    /// When the reply is in: what it changed, as a quiet chip.
    private func changes(_ time: SceneTime) -> some View {
        let streamed = Script.reply + Double(reply.split(separator: " ").count) / Script.wordsPerBeat
        return HStack(spacing: Space.s) {
            Image(systemName: "doc.badge.plus").foregroundStyle(Palette.textSecondary)
            Text(String(localized: "2 files changed")).foregroundStyle(Palette.textSecondary)
            Text(verbatim: "+16").foregroundStyle(Palette.success)
            Text(verbatim: "−4").foregroundStyle(Palette.failure)
        }
        .font(Typography.chip)
        .padding(.horizontal, Space.s + 2)
        .frame(height: Metrics.chipHeight)
        .background(Capsule().fill(Palette.inset))
        .overlay(Capsule().strokeBorder(Palette.hairline))
        .modifier(Arrive(progress: time.beat(streamed + 0.4, 1)))
    }

    private var composer: some View {
        HStack {
            Text(String(localized: "Ask anything…")).font(Typography.body).foregroundStyle(Palette.textTertiary)
            Spacer()
            Circle().fill(Palette.accent)
                .frame(width: Metrics.sendButton - 6, height: Metrics.sendButton - 6)
                .overlay(Image(systemName: "arrow.up").font(SceneType.sendGlyph).foregroundStyle(Palette.textInverse))
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs + 1)
        .frame(height: Metrics.sendButton + 4)
        .raisedSurface(radius: Radius.large)
        .cardShadow()
    }
}
