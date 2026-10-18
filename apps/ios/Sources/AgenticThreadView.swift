import SwiftUI
import XBotRemote
import XBotWorld

/// One crew member's thread, like a chat in Messages or Telegram: your bubbles on the right in the
/// accent, theirs on the left, cards for screenshots, approvals and hand-offs, one activity line
/// while they work, and a composer with dictation and photos.
struct AgenticThreadView: View {
    let client: RemoteClient
    let memberID: UUID
    let openMember: (UUID) -> Void
    @State private var text = ""
    @State private var photos: [PendingPhoto] = []
    @State private var editing: RemoteMessage?
    @State private var viewing: RemoteImage?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resident: RemoteResident? { client.world?.residents.first { $0.id == memberID } }
    private var thread: RemoteChat? { client.thread(for: memberID) }
    private var name: String { resident?.name ?? thread?.crewName ?? "" }
    private var messages: [RemoteMessage] {
        guard let thread else { return [] }
        return Array((client.transcripts[thread.id] ?? []).suffix(RemoteClient.threadMemory))
    }
    private var live: [RemotePart] { thread.flatMap { client.live[$0.id] } ?? [] }
    private var running: Bool { thread?.isRunning == true }
    private var items: [ThreadItem] { messages.flatMap(ThreadItem.items) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if thread == nil || (messages.isEmpty && client.transcripts[thread?.id ?? UUID()] != nil && !running) {
                        intro
                    }
                    ForEach(items) { item in
                        ThreadItemView(client: client, chatID: thread?.id, item: item, running: running, residents: client.world?.residents ?? [],
                                       edit: { editing = $0 }, view: { viewing = $0 }, openMember: openMember)
                            .id(item.id)
                            .transition(insertion)
                    }
                    if running || !live.isEmpty {
                        LiveReply(client: client, chatID: thread?.id, parts: live, residents: client.world?.residents ?? [],
                                  view: { viewing = $0 }, openMember: openMember)
                            .id("live")
                            .transition(insertion)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.38, bounce: 0.18), value: items.count)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3), value: running)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .background(Color(.systemGroupedBackground))
            .onChange(of: items.count) { proxy.scrollTo("end", anchor: .bottom) }
            // A turn starting or a new card or tool row: back to the bottom. (Words streaming into the
            // last bubble keep it there through the size-change anchor.)
            .onChange(of: running) { withAnimation(.smooth) { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: live.count) { withAnimation(.smooth) { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: focused) { if focused { withAnimation(.smooth) { proxy.scrollTo("end", anchor: .bottom) } } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AgenticComposer(client: client, memberID: memberID, name: name, running: running, chatID: thread?.id,
                            text: $text, photos: $photos, focused: $focused)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(name).font(.headline).lineLimit(1)
                    Text(running ? String(localized: "typing…") : (resident?.role ?? ""))
                        .font(.caption).foregroundStyle(running ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)).lineLimit(1)
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let resident { AgentFace(avatar: resident.avatar.look, size: 34) }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear { if let id = thread?.id { client.open(id); client.markSeen(id) } }
        .onChange(of: thread?.id) { _, id in if let id { client.open(id); client.markSeen(id) } }
        .onChange(of: thread?.updatedAt) { if let id = thread?.id { client.markSeen(id) } }
        .onDisappear { if let id = thread?.id { client.markSeen(id); client.close(id) } }
        .sheet(item: $editing) { message in
            EditSheet(original: message.text) { edited in
                guard let id = thread?.id else { return }
                Task { await client.edit(message.id, to: edited, in: id) }
            }
        }
        .fullScreenCover(item: $viewing) { image in ImageViewer(image: image) }
    }

    private var insertion: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
    }

    /// Before the first message: who this is, and a few things to ask.
    private var intro: some View {
        VStack(spacing: 10) {
            if let resident { AgentFace(avatar: resident.avatar.look, size: 84) }
            Text(name).font(.title2.weight(.bold))
            Text(resident?.isHeadMaster == true
                 ? String(localized: "Ask me anything. I can use your Mac like you do, and hand work to the crew.")
                 : (resident?.role ?? ""))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if resident?.isHeadMaster == true {
                VStack(spacing: 8) {
                    ForEach(Self.starters, id: \.self) { starter in
                        Button { text = starter; focused = true } label: {
                            Text(starter).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    private static let starters = [
        String(localized: "What's on my screen right now?"),
        String(localized: "Tidy up my Desktop"),
        String(localized: "What changed in my projects today?"),
    ]
}

// MARK: - What a thread shows

/// A message, cut into what the thread draws: your bubble, or theirs as text, tool rows, cards
/// and notes, in order.
enum ThreadItem: Identifiable {
    case mine(RemoteMessage)
    case text(String, RemoteMessage, String)
    case tools(String, [RemoteTool])
    case image(String, RemoteImage)
    case approval(String, RemoteApproval)
    case note(String, AgenticDigest.Note?, String)
    /// The CLI's own warnings (config, hooks), folded into one quiet line.
    case notices(String, [String])
    case lesson(String, String)
    case failure(String, RemoteMessage, String)

    var id: String {
        switch self {
        case .mine(let message): message.id.uuidString
        case .text(let id, _, _), .tools(let id, _), .image(let id, _), .approval(let id, _), .note(let id, _, _),
             .notices(let id, _), .lesson(let id, _), .failure(let id, _, _): id
        }
    }

    static func items(_ message: RemoteMessage) -> [ThreadItem] {
        if message.role == "user" { return [.mine(message)] }
        return items(message.parts, key: message.id.uuidString, message: message)
    }

    static func items(_ parts: [RemotePart], key: String, message: RemoteMessage?) -> [ThreadItem] {
        var out: [ThreadItem] = []
        let tools = AgenticDigest.tools(in: parts)
        if !tools.isEmpty, message != nil { out.append(.tools("\(key)-tools", tools)) }
        var text: [String] = []
        var notices: [String] = []
        func flush(_ index: Int) {
            let joined = text.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            // "t": the part that ends the text (`index`) keeps its own id for its card.
            if !joined.isEmpty, let message { out.append(.text("\(key)-t\(index)", message, joined)) }
            text = []
        }
        for (index, part) in parts.enumerated() {
            switch part {
            case .text(let t): text.append(t)
            // Words either side of a tool are separate thoughts: a paragraph break, not run together.
            case .tool: if let last = text.last, !last.hasSuffix("\n\n") { text.append("\n\n") }
            case .image(let image): flush(index); out.append(.image("\(key)-\(index)", image))
            case .approval(let approval): flush(index); out.append(.approval("\(key)-\(index)", approval))
            case .notice(let notice):
                if let note = AgenticDigest.handoff(notice) {
                    flush(index)
                    out.append(.note("\(key)-\(index)", note, notice))
                } else {
                    notices.append(notice)
                }
            case .lesson(let lesson): flush(index); out.append(.lesson("\(key)-\(index)", lesson))
            case .failure(let reason):
                flush(index)
                if let message { out.append(.failure("\(key)-\(index)", message, reason)) }
            case .plan(let plan): flush(index); out.append(.note("\(key)-\(index)", nil, plan.summary))
            case .unknown: continue
            }
        }
        flush(parts.count)
        if !notices.isEmpty { out.append(.notices("\(key)-notices", notices)) }
        return out
    }
}

private struct ThreadItemView: View {
    let client: RemoteClient
    let chatID: UUID?
    let item: ThreadItem
    let running: Bool
    let residents: [RemoteResident]
    let edit: (RemoteMessage) -> Void
    let view: (RemoteImage) -> Void
    let openMember: (UUID) -> Void

    var body: some View {
        switch item {
        case .mine(let message):
            MyBubble(message: message, view: view)
                .contextMenu {
                    Button { UIPasteboard.general.string = message.text } label: { Label(String(localized: "Copy"), systemImage: "doc.on.doc") }
                    Button { edit(message) } label: { Label(String(localized: "Edit and resend"), systemImage: "pencil") }
                        .disabled(running)
                }
        case .text(_, let message, let text):
            TheirBubble { BubbleMarkdown(text: text) }
                .contextMenu {
                    Button { UIPasteboard.general.string = text } label: { Label(String(localized: "Copy"), systemImage: "doc.on.doc") }
                    retry
                    ShareLink(item: message.text) { Label(String(localized: "Share"), systemImage: "square.and.arrow.up") }
                }
        case .tools(_, let tools): DidThings(tools: tools)
        case .image(_, let image): ScreenshotCard(image: image, open: { view(image) })
        case .approval(_, let approval): ApprovalCard(client: client, approval: approval)
        case .note(_, let note, let text): NoteRow(note: note, text: text, residents: residents, openMember: openMember)
        case .notices(_, let lines): AgentNotices(lines: lines)
        case .lesson(_, let lesson): LessonRow(text: lesson)
        case .failure(_, _, let reason):
            TheirBubble(tint: .red) {
                Label(reason, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
            }
            .contextMenu { retry }
        }
    }

    private var retry: some View {
        Button { if let chatID { Task { await client.retry(chatID) } } } label: { Label(String(localized: "Retry"), systemImage: "arrow.clockwise") }
            .disabled(running || chatID == nil)
    }
}

/// The reply being written: what they're doing in one line, then the words as they come, or the
/// typing dots until there are some.
private struct LiveReply: View {
    let client: RemoteClient
    let chatID: UUID?
    let parts: [RemotePart]
    let residents: [RemoteResident]
    let view: (RemoteImage) -> Void
    let openMember: (UUID) -> Void

    var body: some View {
        let cards = ThreadItem.items(parts.filter { if case .text = $0 { false } else { true } }, key: "live", message: nil)
        let text = parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 6) {
            if let activity = AgenticDigest.activity(in: parts) { ActivityLine(text: activity) }
            ForEach(cards) { item in
                ThreadItemView(client: client, chatID: chatID, item: item, running: true, residents: residents,
                               edit: { _ in }, view: view, openMember: openMember)
            }
            if text.isEmpty {
                TheirBubble { TypingDots() }
            } else {
                TheirBubble { BubbleMarkdown(text: text) }
            }
        }
    }
}

// MARK: - Bubbles

private struct MyBubble: View {
    let message: RemoteMessage
    let view: (RemoteImage) -> Void

    private var images: [RemoteImage] { message.parts.compactMap { if case .image(let i) = $0 { i } else { nil } } }

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(images) { image in
                    Thumbnail(image: image, maxWidth: 220)
                        .onTapGesture { view(image) }
                }
                if !message.text.isEmpty {
                    Text(MarkdownBlock.attributed(message.text))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.accent.gradient, in: .rect(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("my-bubble")
    }
}

struct TheirBubble<Content: View>: View {
    var tint: Color?
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            content
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(tint.map { AnyShapeStyle($0.opacity(0.12)) } ?? AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                            in: .rect(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 40)
        }
    }
}

/// Markdown in a bubble, code blocks in their own well.
private struct BubbleMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.blocks(text).enumerated()), id: \.offset) { _, block in
                if block.code {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.text).font(.footnote.monospaced()).padding(10)
                    }
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10, style: .continuous))
                } else {
                    Text(MarkdownBlock.attributed(block.text))
                }
            }
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("their-bubble")
    }
}

/// Three dots, as Messages draws them; still under Reduce Motion.
private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                dots(lit: -1)
            } else {
                PhaseAnimator([0, 1, 2]) { phase in dots(lit: phase) } animation: { _ in .easeInOut(duration: 0.32) }
            }
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Typing"))
        .accessibilityIdentifier("typing")
    }

    private func dots(lit: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(lit == index ? 0.9 : 0.35)
                    .offset(y: lit == index ? -2 : 0)
            }
        }
    }
}

/// What they're doing right now, in one line that changes in place.
private struct ActivityLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "gearshape.2").font(.caption).foregroundStyle(Theme.accent)
            Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: text)
        }
        .padding(.leading, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activity-line")
    }
}

/// "Did 7 things ›": the tools a reply used, folded; tap to see them.
private struct DidThings: View {
    let tools: [RemoteTool]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle").font(.caption)
                    Text(tools.count == 1 ? String(localized: "Did 1 thing") : String(localized: "Did \(tools.count) things"))
                    Image(systemName: "chevron.right").font(.caption2.bold()).rotationEffect(.degrees(open ? 90 : 0))
                }
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.leading, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("did-things")
            if open {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                        HStack(spacing: 7) {
                            Image(systemName: tool.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(tool.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                            Text(tool.label).font(.footnote.weight(.medium))
                            Text(tool.summary).font(.footnote.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: 320, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Notes

/// A crew note: a hand-off (tap for their thread), someone finishing, or a quiet line.
private struct NoteRow: View {
    let note: AgenticDigest.Note?
    let text: String
    let residents: [RemoteResident]
    let openMember: (UUID) -> Void

    var body: some View {
        switch note {
        case .handed(let name, let task):
            let member = residents.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            Button { if let member { openMember(member.id) } } label: {
                HStack(spacing: 10) {
                    if let member { AgentFace(avatar: member.avatar.look, size: 36) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Handed to \(name)")).font(.subheadline.weight(.semibold))
                        Text(task).font(.footnote).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(maxWidth: 320, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("handoff-card")
        case .finished(let name, let gist):
            pill(symbol: "checkmark.circle.fill", tint: .green, text: String(localized: "\(name) finished: \(gist)"))
        case nil:
            pill(symbol: "info.circle", tint: .secondary, text: text)
        }
    }

    private func pill(symbol: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).foregroundStyle(.secondary).lineLimit(3)
        }
        .font(.footnote)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.7), in: .capsule)
        .frame(maxWidth: .infinity)
    }
}

/// The agent CLI's own warnings, one quiet line; open for the details.
private struct AgentNotices: View {
    let lines: [String]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle").font(.caption)
                    Text(lines.count == 1 ? String(localized: "1 note from the agent") : String(localized: "\(lines.count) notes from the agent"))
                    Image(systemName: "chevron.right").font(.caption2.bold()).rotationEffect(.degrees(open ? 90 : 0))
                }
                .font(.footnote).foregroundStyle(.tertiary)
                .padding(.leading, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.leading, 6)
                }
                .transition(.opacity)
            }
        }
    }
}

/// "Learnt: …", small and quiet; edited or forgotten on the Mac.
private struct LessonRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
            Text(String(localized: "Learnt: \(text)")).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.leading, 8)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lesson")
    }
}
