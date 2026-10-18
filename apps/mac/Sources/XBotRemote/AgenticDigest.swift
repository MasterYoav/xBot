import Foundation

/// What Agentic Mode's screens read off the wire: each crew member's thread, the one-line activity
/// while an agent works, "Did N things", hand-off notes and the chat list's previews. Pure, so the
/// Mac's package tests cover what the phone shows.
public enum AgenticDigest {
    /// Each crew member's thread, by member: the newest chat flagged as one.
    public static func threads(in chats: [RemoteChat]) -> [UUID: RemoteChat] {
        var out: [UUID: RemoteChat] = [:]
        for chat in chats where chat.isThread {
            guard let agent = chat.agentID else { continue }
            if let known = out[agent], known.updatedAt >= chat.updatedAt { continue }
            out[agent] = chat
        }
        return out
    }

    /// The tool rows in a reply, in order.
    public static func tools(in parts: [RemotePart]) -> [RemoteTool] {
        parts.compactMap { if case .tool(let tool) = $0 { tool } else { nil } }
    }

    /// While an agent works: what it's doing now, from its latest tool row ("Running swift test…").
    /// Nil until it uses a tool.
    public static func activity(in parts: [RemotePart], limit: Int = 64) -> String? {
        guard let tool = tools(in: parts).last else { return nil }
        let ellipsis = tool.isDone ? "" : "…"
        let summary = tool.summary.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        var line = summary.isEmpty ? tool.label : "\(tool.label) \(summary)"
        if line.count + ellipsis.count > limit {
            line = String(line.prefix(limit - 1 - ellipsis.count)).trimmingCharacters(in: .whitespaces) + "…"
            return line
        }
        return line + ellipsis
    }

    /// A note from the Mac about the crew (`Handoff.handedPrefix` / `finishedPrefix` on the Mac).
    public enum Note: Equatable, Sendable {
        case handed(name: String, task: String)
        case finished(name: String, gist: String)
    }

    public static func handoff(_ notice: String) -> Note? {
        if notice.hasPrefix("Handed to "), let colon = notice.range(of: ": ") {
            let name = notice[notice.index(notice.startIndex, offsetBy: "Handed to ".count)..<colon.lowerBound]
            guard !name.isEmpty, name.count < 40 else { return nil }
            return .handed(name: String(name), task: String(notice[colon.upperBound...]))
        }
        if let range = notice.range(of: " finished: ") {
            let name = notice[..<range.lowerBound]
            guard !name.isEmpty, name.count < 40 else { return nil }
            return .finished(name: String(name), gist: String(notice[range.upperBound...]))
        }
        return nil
    }

    /// The chat list's line under a name: the last message, flattened to one line.
    public static func preview(of message: RemoteMessage, limit: Int = 120) -> String {
        let you = message.role == "user"
        func cut(_ text: String) -> String {
            let flat = flatten(text)
            return flat.count > limit ? String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : flat
        }
        let text = message.parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
        if you {
            if !flatten(text).isEmpty { return "You: " + cut(text) }
            if message.parts.contains(where: { if case .image = $0 { true } else { false } }) { return "You: Photo" }
            return "You: …"
        }
        for part in message.parts {
            if case .approval(let approval) = part, approval.state == "pending" { return cut("Needs your OK: " + approval.summary) }
        }
        if !flatten(text).isEmpty { return cut(text) }
        for part in message.parts.reversed() {
            switch part {
            case .image(let image): return image.caption.map(cut) ?? "Screenshot"
            case .failure(let reason): return cut(reason)
            case .lesson(let lesson): return cut("Learnt: " + lesson)
            case .notice(let notice): return cut(notice)
            case .approval(let approval): return cut(approval.summary)
            default: continue
            }
        }
        let count = tools(in: message.parts).count
        return count == 0 ? "" : (count == 1 ? "Did 1 thing" : "Did \(count) things")
    }

    /// Markdown to one plain line: no emphasis marks, headings, quotes, bullets or fences.
    static func flatten(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).compactMap { raw -> String? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { return nil }
            while let first = line.first, "#>".contains(first) { line.removeFirst() }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line.removeFirst(2) }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
            line = line.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : line
        }
        return lines.joined(separator: " ")
    }
}
