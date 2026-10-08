import AppKit
import SwiftUI
import XBotCore

/// The person's message: right-aligned, on a raised fill, as typed.
struct UserMessage: View {
    let parts: [Part]

    var body: some View {
        Text(parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n"))
            .readingText()
            .textSelection(.enabled)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.m + 2)
            .padding(.vertical, Space.s + 1)
            .raisedSurface()
            .frame(maxWidth: Metrics.readingWidth * 0.8, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
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
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header
            ForEach(Array(ReplyLayout.segments(parts).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text): MarkdownText(text: text)
                case .tools(let tools): ToolFold(tools: tools, isLive: isLive)
                case .notice(let text): Text(text).captionText().foregroundStyle(Palette.textTertiary)
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

    private var header: some View {
        HStack(spacing: Space.xs) {
            Circle().fill(Palette.agent(harness)).frame(width: Metrics.dot + 1, height: Metrics.dot + 1)
            if isLive {
                Text(String(localized: "\(harness.displayName) is working…"))
                ProgressView().controlSize(.mini)
            } else if let workedFor {
                Text(String(localized: "\(harness.displayName) worked for \(Elapsed.format(workedFor))"))
            } else {
                Text(harness.displayName)
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
