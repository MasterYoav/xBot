import SwiftUI
import XBotCore

/// One message: the person's on the right as they typed it, the agent's on the left, rendered.
struct MessageView: View {
    let role: Role
    let parts: [Part]
    var isLive = false

    var body: some View {
        if role == .user {
            Text(userText)
                .bodyText()
                .textSelection(.enabled)
                .foregroundStyle(Palette.bubbleOutgoingText)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Palette.bubbleOutgoing, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let text): ReplyText(text: text)
                    case .tool(let tool): ToolRow(tool: tool)
                    case .notice(let text):
                        Text(text).captionText().foregroundStyle(Palette.textTertiary)
                    case .failure(let reason):
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .captionText()
                            .foregroundStyle(Palette.stateFailed)
                            .textSelection(.enabled)
                    }
                }
                if isLive { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var userText: String {
        parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
    }
}

private struct ReplyText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(MessageMarkdown.blocks(of: text)) { block in
                switch block {
                case .prose(let prose):
                    Text(MessageMarkdown.inline(prose)).bodyText().textSelection(.enabled)
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
        .foregroundStyle(Palette.textPrimary)
    }
}

/// A tool call, one line; its output on request.
private struct ToolRow: View {
    let tool: ToolPart
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button { expanded.toggle() } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: icon).foregroundStyle(tool.isError ? Palette.stateFailed : Palette.textSecondary)
                    Text(tool.name).captionText().bold()
                    Text(tool.summary).captionText().foregroundStyle(Palette.textSecondary).lineLimit(1)
                    if tool.output == nil { ProgressView().controlSize(.mini) }
                }
            }
            .buttonStyle(.plain)
            .disabled((tool.output ?? "").isEmpty)
            if expanded, let output = tool.output, !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(Typography.mono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Metrics.toolOutputMaxHeight)
                .padding(Space.s)
                .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
        }
        .motion(Motion.quick, value: expanded)
    }

    private var icon: String {
        if tool.isError { return "exclamationmark.circle" }
        return tool.output == nil ? "circle.dotted" : "checkmark.circle"
    }
}
