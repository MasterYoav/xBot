import AppKit
import SwiftUI
import XBotCore

/// The person's message: right-aligned, on a raised fill, as typed.
struct UserMessage: View {
    let parts: [Part]
    var sentAt: Date?
    /// Sends the edited text in place of this message. Nil while the chat is busy: an edit would
    /// replace a turn that is still being written.
    var resend: ((String) -> Bool)?
    @State private var hovering = false
    @State private var copied = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var text: String {
        parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.xs) {
            if editing { editor } else { bubble }
            if !editing {
                actions.opacity(hovering ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
        .motion(Motion.quick, value: editing)
    }

    private var bubble: some View {
        Text(text)
            .readingText()
            .textSelection(.enabled)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.m + 2)
            .padding(.vertical, Space.s + 1)
            .raisedSurface()
            .frame(maxWidth: Metrics.readingWidth * 0.8, alignment: .trailing)
    }

    /// The bubble, opened for editing: the same place, the full reading width, and the two choices.
    private var editor: some View {
        VStack(alignment: .trailing, spacing: Space.s) {
            TextField(String(localized: "Edit your message"), text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .readingText()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...12)
                .focused($focused)
                .onSubmit(send)
                .onKeyPress(.escape) { cancel(); return .handled }
            HStack(spacing: Space.s) {
                Button(String(localized: "Cancel"), action: cancel)
                    .buttonStyle(QuietButtonStyle())
                Button(String(localized: "Send"), action: send)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resend == nil)
            }
        }
        .padding(.horizontal, Space.m + 2)
        .padding(.vertical, Space.s + 1)
        .raisedSurface()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var actions: some View {
        HStack(spacing: Space.xs) {
            if let sentAt {
                Text(sentAt, format: .dateTime.hour().minute()).captionText().foregroundStyle(Palette.textTertiary)
            }
            IconButton(copied ? "checkmark" : "doc.on.doc", help: String(localized: "Copy message")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            }
            if resend != nil {
                IconButton("pencil", help: String(localized: "Edit and send again")) {
                    draft = text
                    editing = true
                    focused = true
                }
            }
        }
    }

    private func send() {
        guard let resend, resend(draft) else { return }
        editing = false
    }

    private func cancel() {
        editing = false
        draft = ""
    }
}

/// The agent's reply: "● Claude Code worked for 41s", then text, folded tools, notices, failures.
struct AgentReply: View {
    let harness: HarnessKind
    let parts: [Part]
    var workedFor: TimeInterval?
    var isLive = false
    var sentAt: Date?
    var retry: (() -> Void)?
    /// The crew member this chat is with: the reply is theirs, under their face and name.
    var agent: Agent?
    /// The crew, so hand-off notices show as cards with the member's face; and how to open theirs.
    var crew: [Agent] = []
    var openAgent: ((UUID) -> Void)?
    @State private var hovering = false
    @State private var copied = false

    private var who: String { agent?.name ?? harness.displayName }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // A note on its own (a member reporting back) is not a reply: no "worked for".
            if !parts.allSatisfy({ if case .notice = $0 { true } else { false } }) || isLive { header }
            ForEach(Array(ReplyLayout.segments(parts).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text): MarkdownText(text: agent == nil ? text : Handoff.stripping(text))
                case .tools(let tools): ToolFold(tools: tools, isLive: isLive)
                case .notice(let text): notice(text)
                case .failure(let reason): FailureCallout(reason: reason, retry: isLive ? nil : retry)
                }
            }
            if !isLive {
                actions.opacity(hovering ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
    }

    @ViewBuilder
    private func notice(_ text: String) -> some View {
        if let (member, handed, rest) = handoff(text) {
            Button { openAgent?(member.id) } label: {
                HStack(spacing: Space.s) {
                    AgentFace(agent: member, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(handed ? String(localized: "Handed to \(member.name)") : String(localized: "\(member.name) finished"))
                            .emphasisText().foregroundStyle(Palette.textPrimary)
                        Text(rest).captionText().foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: Space.s)
                    Text(String(localized: "Open")).captionText().foregroundStyle(Palette.textTertiary)
                    Image(systemName: "arrow.up.right").imageScale(.small).foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .frame(maxWidth: 460, alignment: .leading)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(
                    handed ? Palette.hairline : Palette.success.opacity(0.5)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(openAgent == nil)
        } else {
            Text(text).captionText().foregroundStyle(Palette.textTertiary)
        }
    }

    private func handoff(_ text: String) -> (Agent, Bool, String)? {
        for member in crew {
            if text.hasPrefix(Handoff.handedPrefix(member.name)) {
                return (member, true, String(text.dropFirst(Handoff.handedPrefix(member.name).count)))
            }
            if text.hasPrefix(Handoff.finishedPrefix(member.name)) {
                return (member, false, String(text.dropFirst(Handoff.finishedPrefix(member.name).count)))
            }
        }
        return nil
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            if let agent {
                AgentFace(agent: agent, size: 20, status: isLive ? .working(activity: nil, since: .now) : .idle)
            } else {
                Circle().fill(Palette.agent(harness)).frame(width: Metrics.dot + 1, height: Metrics.dot + 1)
            }
            if isLive {
                Text(String(localized: "\(who) is working…"))
                if agent == nil { ProgressView().controlSize(.mini) }
            } else if let workedFor {
                Text(String(localized: "\(who) worked for \(Elapsed.format(workedFor))"))
            } else {
                Text(who)
            }
        }
        .captionText()
        .foregroundStyle(Palette.textTertiary)
    }

    private var actions: some View {
        HStack(spacing: Space.xs) {
            IconButton(copied ? "checkmark" : "doc.on.doc", help: String(localized: "Copy reply")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plainText, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            }
            if let sentAt {
                Text(sentAt, format: .dateTime.hour().minute()).captionText().foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var plainText: String {
        parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n\n")
    }
}

/// A run of tools as one line — "Read 3 files, ran a command" — that opens to every tool.
private struct ToolFold: View {
    let tools: [ToolPart]
    let isLive: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button { open.toggle() } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(Palette.textTertiary)
                    Text(ToolLabel.summary(of: tools)).captionText().foregroundStyle(Palette.textSecondary)
                    Image(systemName: open ? "chevron.up" : "chevron.down").imageScale(.small)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)
            if open {
                ForEach(tools, id: \.id) { ToolLine(tool: $0) }.padding(.leading, Metrics.stepIndent)
            } else if isLive, let running = tools.last(where: { $0.output == nil }) {
                ToolLine(tool: running).padding(.leading, Metrics.stepIndent)
            }
        }
        .motion(Motion.quick, value: open)
    }
}

private struct FailureCallout: View {
    let reason: String
    let retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.failure)
            Text(reason).bodyText().foregroundStyle(Palette.textPrimary).textSelection(.enabled)
            Spacer(minLength: Space.s)
            if let retry {
                Button(String(localized: "Retry"), action: retry).buttonStyle(QuietButtonStyle())
            }
        }
        .padding(Space.m)
        .background(Palette.failureTint, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}
