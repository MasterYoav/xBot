import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XBotBrain

/// Agentic Mode's threads: one chat per crew member, flagged `isThread`, started by the first
/// message from the phone and kept going for good. A thread runs in Full access in xBot's Inbox
/// folder (the agent works anywhere on the Mac from there), on the agent's own CLI and model.
/// Threads are ordinary chats otherwise, listed on the Mac under their agent.
extension Workspace {
    /// The member's thread, if they have one.
    public func thread(for memberID: UUID) -> Chat? {
        chats.filter { $0.isThread && $0.agentID == memberID }.max { $0.createdAt < $1.createdAt }
    }

    /// Every thread, newest activity first.
    public var threads: [Chat] { chats.filter(\.isThread) }

    /// Sends `text` and `images` (any format; saved as JPEGs ≤ 1600 px) to the member's thread,
    /// starting it if there's none. False, with nothing kept, when the member isn't on the crew,
    /// there's nothing to send, no agent CLI is installed, or the thread is still answering.
    @discardableResult
    public func threadSend(_ memberID: UUID, text: String, images: [Data]) -> Bool {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let agent = agent(memberID), !said.isEmpty || !images.isEmpty else { return false }
        if let current = thread(for: memberID), isRunning(current.id) { return false }

        var preamble: String?
        let chat: Chat
        if let current = thread(for: memberID), !needsNewThread(current, agent: agent) {
            chat = current
        } else {
            let earlier = thread(for: memberID)
            guard let started = startThread(with: agent) else { return false }
            if let earlier {
                // Kept as a plain chat with the agent; the new one carries on from its last words.
                update(earlier.id) { $0.isThread = false }
                loadTranscript(earlier.id)
                preamble = Self.continuation(messages(in: earlier.id))
            }
            chat = started
        }

        let folder = directory(for: chat)
        var pictures: [ImagePart] = []
        var attached: [String] = []
        for data in images {
            guard let (picture, attachment) = savePicture(data, attachmentsIn: folder) else { continue }
            pictures.append(picture)
            attached.append(attachment.path(percentEncoded: false))
        }
        guard !said.isEmpty || !pictures.isEmpty else { return false }
        var prompt = said
        if !attached.isEmpty {
            prompt += (prompt.isEmpty ? "" : "\n\n") + "Attached: " + attached.joined(separator: ", ")
        }

        guard send(prompt, in: chat.id, earlier: preamble) else {
            for picture in pictures { try? FileManager.default.removeItem(atPath: picture.path) }
            for path in attached { try? FileManager.default.removeItem(atPath: path) }
            return false
        }
        // The person's message shows what they said and the pictures, not the paths the agent was given.
        if var question = transcripts[chat.id]?.last(where: { $0.role == .user }) {
            question.parts = (said.isEmpty ? [] : [.text(said)]) + pictures.map(Part.image)
            attempt { try store.replace(question) }
            if let index = transcripts[chat.id]?.lastIndex(where: { $0.id == question.id }) {
                transcripts[chat.id]?[index] = question
            }
        }
        return true
    }

    /// Puts an approval card in a chat, or updates the one with the same id in place (the
    /// approval center's `post` and `update`).
    public func showApproval(_ approval: ApprovalPart, in chatID: UUID) {
        loadTranscript(chatID)
        if let index = transcripts[chatID]?.lastIndex(where: { message in
            message.parts.contains { if case .approval(let a) = $0 { a.id == approval.id } else { false } }
        }), var message = transcripts[chatID]?[index] {
            message.parts = message.parts.map { part in
                if case .approval(let a) = part, a.id == approval.id { .approval(approval) } else { part }
            }
            attempt { try store.replace(message) }
            transcripts[chatID]?[index] = message
        } else {
            save(ChatMessage(chatID: chatID, role: .assistant, parts: [.approval(approval)]))
        }
        touch(chatID)
    }

    /// The member's thread, started if there's none (no turn runs).
    func ensureThread(for memberID: UUID) -> Chat? {
        guard let agent = agent(memberID) else { return nil }
        return thread(for: memberID) ?? startThread(with: agent)
    }

    /// Something was added to a chat without a turn: it moves up the lists.
    func touch(_ chatID: UUID) { update(chatID) { $0.updatedAt = .now } }

    // MARK: Private

    private func startThread(with agent: Agent) -> Chat? {
        let harness = brains[agent.harness] == nil ? availableHarnesses.first : agent.harness
        guard let harness else { return nil }
        var chat = Chat(projectID: nil, title: agent.name, harness: harness,
                        model: harness == agent.harness ? agent.model : nil, mode: .fullAccess, agentID: agent.id)
        chat.isThread = true
        attempt { try store.save(chat) }
        chats.insert(chat, at: 0)
        transcripts[chat.id] = []
        return chat
    }

    /// A thread whose session can't go on: the agent moved to another CLI, or the CLI said it
    /// couldn't find or fit the session.
    private func needsNewThread(_ chat: Chat, agent: Agent) -> Bool {
        if chat.harness != agent.harness, brains[agent.harness] != nil { return true }
        loadTranscript(chat.id)
        guard let last = messages(in: chat.id).last(where: { $0.role == .assistant }) else { return false }
        return last.parts.contains { part in
            guard case .failure(let reason) = part else { return false }
            let lower = reason.lowercased()
            return Self.lostSession.contains { lower.contains($0) }
        }
    }

    private static let lostSession = [
        "no conversation found", "session not found", "thread not found", "could not resume", "couldn't resume",
        "failed to resume", "prompt is too long", "context length", "context window",
    ]

    /// The last few things said in an earlier thread, as the new session's preamble.
    static func continuation(_ messages: [ChatMessage]) -> String? {
        let turns = messages.suffix(12).compactMap { message -> String? in
            let text = message.parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let clipped = text.count > 600 ? String(text.prefix(600)) + "…" : text
            return "\(message.role == .user ? "User" : "You"): \(clipped)"
        }
        guard !turns.isEmpty else { return nil }
        return "This conversation continues from an earlier session that can't be resumed. Its last messages:\n\n"
            + turns.joined(separator: "\n\n") + "\n\n---\n\n"
    }

    /// Where pictures are kept: `Images/` beside the library (the Inbox's parent).
    var imagesFolder: URL { inbox.deletingLastPathComponent().appending(path: "Images", directoryHint: .isDirectory) }

    /// Saves a picture as a JPEG ≤ 1600 px in `Images/` and a copy in the chat's folder for the agent.
    private func savePicture(_ data: Data, attachmentsIn folder: URL) -> (ImagePart, URL)? {
        guard let (jpeg, width, height) = Pictures.jpeg(from: data) else { return nil }
        let id = UUID()
        let file = imagesFolder.appending(path: "\(id.uuidString).jpg")
        let attachments = folder.appending(path: "Attachments", directoryHint: .isDirectory)
        let attachment = attachments.appending(path: "\(id.uuidString).jpg")
        do {
            try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
            try jpeg.write(to: file, options: .atomic)
            try jpeg.write(to: attachment, options: .atomic)
        } catch {
            problem = String(localized: "xBot couldn't save a picture: \(error.localizedDescription)")
            return nil
        }
        return (ImagePart(id: id, path: file.path(percentEncoded: false), width: width, height: height), attachment)
    }
}

/// Pictures for the conversation: any format in, a JPEG no bigger than `maxPixel` out.
public enum Pictures {
    public static func jpeg(from data: Data, maxPixel: Int = 1600, quality: Double = 0.7) -> (Data, Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (out as Data, image.width, image.height)
    }
}
