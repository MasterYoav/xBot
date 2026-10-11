import Foundation

/// Editing a prompt that was already sent, and sending it again.
extension Workspace {
    /**
     Replaces a person's message, and everything after it, with `text`, and sends it.

     The agent's own session still remembers the turns being replaced: resumed, it would answer the
     edit with the old question and answer in its context. So the edit starts a new session, and
     hands it the conversation before the edited message instead. Files the replaced turns changed
     on disk stay changed; that is the project's history, not the chat's.

     Undoable from the toast, as every destructive action is: Undo stops the new turn and puts back
     the messages and the session as they were. False, with nothing changed, when the chat is busy,
     the text is empty, or the message is not the person's.
     */
    @discardableResult
    public func resend(_ messageID: UUID, as text: String, in id: UUID) -> Bool {
        let edited = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = messages(in: id)
        guard !edited.isEmpty, !isRunning(id), let chat = chat(id), brains[chat.harness] != nil,
              let index = transcript.firstIndex(where: { $0.id == messageID }),
              transcript[index].role == .user
        else { return false }

        let removed = Array(transcript[index...])
        let earlier = Array(transcript[..<index])
        let session = chat.sessionID
        attempt { try store.deleteMessages(removed.map(\.id)) }
        transcripts[id] = earlier
        update(id) { $0.sessionID = nil }

        guard send(edited, in: id, earlier: Self.carriedOver(earlier)) else {
            // Nothing was sent: put it all back rather than lose the conversation.
            restore(removed, session: session, in: id)
            return false
        }
        toasts.show(
            String(localized: "Message edited"), systemImage: "pencil",
            action: .init(title: String(localized: "Undo")) { [weak self] in
                self?.undoEdit(restoring: removed, session: session, in: id, after: earlier.count)
            }
        )
        return true
    }

    /// The conversation before an edited prompt, as the new session's preamble. Text only: tool
    /// calls and their output were the old session's working, and its answers say what came of it.
    static func carriedOver(_ messages: [ChatMessage]) -> String? {
        let turns = messages.compactMap { message -> String? in
            let text = message.parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
            guard !text.isEmpty else { return nil }
            let who = message.role == .user ? "User" : "Assistant"
            return "\(who): \(text)"
        }
        guard !turns.isEmpty else { return nil }
        return "This conversation continues from earlier messages, which follow. "
            + "The last of my messages was edited, so answer the new one below.\n\n"
            + turns.joined(separator: "\n\n")
            + "\n\n---\n\n"
    }

    private func undoEdit(restoring removed: [ChatMessage], session: String?, in id: UUID, after count: Int) {
        stop(id)
        let replacement = Array(messages(in: id).dropFirst(count))
        attempt { try store.deleteMessages(replacement.map(\.id)) }
        transcripts[id] = Array(messages(in: id).prefix(count))
        restore(removed, session: session, in: id)
    }

    private func restore(_ removed: [ChatMessage], session: String?, in id: UUID) {
        attempt { for message in removed { try store.append(message) } }
        transcripts[id, default: []].append(contentsOf: removed)
        update(id) { $0.sessionID = session }
    }
}
