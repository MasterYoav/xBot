import SwiftUI
import XBotRemote

/// One chat, live: the Mac's messages, the reply being written, and the composer.
struct ChatScreen: View {
    let client: RemoteClient
    let chatID: UUID
    @State private var text = ""
    @State private var editing: RemoteMessage?
    @FocusState private var focused: Bool

    private var chat: RemoteChat? { client.chat(chatID) }
    private var messages: [RemoteMessage] { client.transcripts[chatID] ?? [] }
    private var live: [RemotePart] { client.live[chatID] ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if client.transcripts[chatID] == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(messages) { message in
                        MessageRow(client: client, chatID: chatID, message: message, edit: { editing = message })
                            .id(message.id)
                    }
                    if !live.isEmpty || chat?.isRunning == true {
                        AssistantParts(client: client, chatID: chatID, messageID: nil, parts: live, writing: true)
                            .id("live")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: live) { proxy.scrollTo("end", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let chat { Composer(client: client, chat: chat, text: $text, focused: $focused) }
        }
        .navigationTitle(chat?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(chat?.title ?? "").font(.headline).lineLimit(1)
                    if let chat {
                        Text([chat.crewName, chat.agentName, client.project(chat.projectID)?.name].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .onAppear { client.open(chatID) }
        .onDisappear { client.close(chatID) }
        .sheet(item: $editing) { message in
            EditSheet(original: message.text) { edited in
                Task { await client.edit(message.id, to: edited, in: chatID) }
            }
        }
    }
}

extension RemoteMessage {
    var text: String {
        parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
    }
}

private struct MessageRow: View {
    let client: RemoteClient
    let chatID: UUID
    let message: RemoteMessage
    let edit: () -> Void

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.accent))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button { UIPasteboard.general.string = message.text } label: { Label(String(localized: "Copy"), systemImage: "doc.on.doc") }
                        Button(action: edit) { Label(String(localized: "Edit and resend"), systemImage: "pencil") }
                            .disabled(client.chat(chatID)?.isRunning == true)
                    }
            }
        } else {
            AssistantParts(client: client, chatID: chatID, messageID: message.id, parts: message.parts, writing: false)
        }
    }
}

/// An agent's reply: text, tool rows, notices, plans.
struct AssistantParts: View {
    let client: RemoteClient
    let chatID: UUID
    let messageID: UUID?
    let parts: [RemotePart]
    let writing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let notices = parts.compactMap { if case .notice(let t) = $0 { t } else { nil } }
            if !notices.isEmpty { Notices(lines: notices) }
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let text): MarkdownBlock(text: text)
                case .tool(let tool): ToolRow(tool: tool)
                case .notice: EmptyView()
                case .failure(let text):
                    Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(.red.opacity(0.1)))
                case .plan(let plan): PlanCard(client: client, chatID: chatID, messageID: messageID, plan: plan)
                }
            }
            if writing && parts.isEmpty {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(String(localized: "Thinking…")).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The agent's own warnings (config, hooks): one quiet line, open for details.
private struct Notices: View {
    let lines: [String]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(lines.count == 1 ? String(localized: "1 note from the agent") : String(localized: "\(lines.count) notes from the agent"))
                    Image(systemName: "chevron.right").font(.caption2.bold()).rotationEffect(.degrees(open ? 90 : 0))
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if open {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }
}

private struct ToolRow: View {
    let tool: RemoteTool
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if !tool.isDone { ProgressView().controlSize(.mini) }
                else if tool.isError { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                else { Image(systemName: "checkmark.circle").foregroundStyle(.secondary) }
            }
            .frame(width: 16)
            Text(tool.label).font(.footnote.weight(.medium))
            Text(tool.summary).font(.footnote.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if let size = tool.size { Text(size).font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .combine)
    }
}

/// Markdown with fenced code blocks as their own boxes.
private struct MarkdownBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                if block.code {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.text).font(.footnote.monospaced()).textSelection(.enabled).padding(12)
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                } else {
                    Text(Self.attributed(block.text)).textSelection(.enabled)
                }
            }
        }
    }

    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    static func blocks(_ text: String) -> [(code: Bool, text: String)] {
        var out: [(Bool, String)] = []
        var code = false
        var current: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if !current.isEmpty { out.append((code, current.joined(separator: "\n"))) }
                current = []
                code.toggle()
                continue
            }
            current.append(line)
        }
        if !current.isEmpty { out.append((code, current.joined(separator: "\n"))) }
        return out.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// A plan: its steps, and Run / Cancel while it waits for review.
private struct PlanCard: View {
    let client: RemoteClient
    let chatID: UUID
    let messageID: UUID?
    let plan: RemotePlan
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "list.bullet.clipboard").font(.subheadline.weight(.semibold))
                Spacer()
                if plan.status == "drafting" || plan.status == "running" { ProgressView().controlSize(.small) }
            }
            if !plan.summary.isEmpty { Text(plan.summary).font(.callout) }
            ForEach(plan.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol(step.status)).foregroundStyle(step.status == "failed" ? .red : .secondary)
                    Text(step.title).font(.callout).strikethrough(step.status == "stopped")
                }
            }
            if let problem = plan.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            if let closing = plan.closing { Text(closing).font(.callout).foregroundStyle(.secondary) }
            if plan.status == "review", let messageID {
                HStack {
                    Button(String(localized: "Cancel"), role: .cancel) {
                        busy = true
                        Task { await client.cancelPlan(messageID, in: chatID); busy = false }
                    }
                    .buttonStyle(.bordered)
                    Button {
                        busy = true
                        Task { await client.runPlan(messageID, in: chatID); busy = false }
                    } label: { Text(String(localized: "Run plan")).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
                .disabled(busy)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var title: String {
        switch plan.status {
        case "drafting": String(localized: "Making a plan…")
        case "review": String(localized: "Plan ready")
        case "running": String(localized: "Running the plan")
        case "finished": String(localized: "Plan done")
        default: String(localized: "Plan stopped")
        }
    }

    private func symbol(_ status: String) -> String {
        switch status {
        case "done": "checkmark.circle.fill"
        case "running": "circle.dotted"
        case "failed": "xmark.circle.fill"
        case "stopped": "minus.circle"
        default: "circle"
        }
    }
}

private struct EditSheet: View {
    let original: String
    let send: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Message"), text: $text, axis: .vertical).lineLimit(3...12)
            }
            .navigationTitle(String(localized: "Edit and resend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Send")) { send(text); dismiss() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = original }
        }
        .presentationDetents([.medium, .large])
    }
}
