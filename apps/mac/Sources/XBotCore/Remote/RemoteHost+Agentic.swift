import CoreGraphics
import Foundation
import ImageIO
import XBotRemote

/// Agentic Mode from a phone: a message in a crew member's thread (with photos), and the answer
/// to an approval card. Approvals reach the phone as messages in the thread (the card is a part),
/// so they need no messages of their own.
extension RemoteHost {
    func handleAgentic(_ message: ClientMessage, link: any RemoteLink) {
        let out: HostMessage
        switch message {
        case .threadSend(let request, let memberID, let text, let images):
            out = threadSend(request, memberID: memberID, text: text, images: images)
        case .answerApproval(let request, let approvalID, let allow):
            let device = link.deviceName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "iPhone")
            out = workspace.approvals.answer(approvalID, allow: allow, by: device)
                ? .reply(requestID: request, ok: true, reason: nil, chatID: nil)
                : .reply(requestID: request, ok: false, reason: String(localized: "That was already answered, or it ran out of time."), chatID: nil)
        default:
            return
        }
        link.send([out])
    }

    private func threadSend(_ request: UUID, memberID: UUID, text: String, images: [Data]) -> HostMessage {
        func refuse(_ reason: String) -> HostMessage { .reply(requestID: request, ok: false, reason: reason, chatID: nil) }
        guard let agent = workspace.agent(memberID) else { return refuse(String(localized: "They aren't on the Mac any more.")) }
        if let thread = workspace.thread(for: memberID), workspace.isRunning(thread.id) {
            return refuse(String(localized: "It's still answering."))
        }
        if workspace.availableHarnesses.isEmpty {
            return refuse(workspace.isDiscovering ? String(localized: "The Mac is still looking for its agents.")
                                                  : String(localized: "No agent is installed on the Mac."))
        }
        guard images.count <= 6 else { return refuse(String(localized: "Send at most 6 photos at a time.")) }
        #if DEBUG
        if let demo = demo(request, text, agent: agent) { return demo }
        #endif
        guard workspace.threadSend(memberID, text: text, images: images), let thread = workspace.thread(for: memberID) else {
            return refuse(String(localized: "The Mac couldn't send that to \(agent.name)."))
        }
        return .reply(requestID: request, ok: true, reason: nil, chatID: thread.id)

    }

    #if DEBUG
    /// `XBOT_AGENTIC_DEMO=1` (debug builds only): "/demo approval" and "/demo screenshot" put a
    /// sample card in the thread without a turn, to look at the phone's cards.
    private func demo(_ request: UUID, _ text: String, agent: Agent) -> HostMessage? {
        guard ProcessInfo.processInfo.environment["XBOT_AGENTIC_DEMO"] == "1", text.hasPrefix("/demo "),
              let thread = workspace.ensureThread(for: agent.id) else { return nil }
        workspace.save(ChatMessage(chatID: thread.id, role: .user, parts: [.text(text)]))
        switch text {
        case "/demo approval":
            workspace.approvals.post = { [weak workspace] approval, chat in workspace?.showApproval(approval, in: chat) }
            workspace.approvals.update = { [weak workspace] approval, chat in workspace?.showApproval(approval, in: chat) }
            let approval = ApprovalPart(agent: agent.name, summary: String(localized: "Delete 3 files in ~/Projects/old"),
                                        detail: "rm ~/Projects/old/a.txt ~/Projects/old/b.txt ~/Projects/old/c.txt", risk: "delete")
            Task { @MainActor [weak workspace] in _ = await workspace?.approvals.ask(approval, in: thread.id) }
        case "/demo screenshot":
            if let png = Self.demoScreen(), let (data, width, height) = Pictures.jpeg(from: png) {
                let id = UUID()
                let file = workspace.imagesFolder.appending(path: "\(id.uuidString).jpg")
                try? FileManager.default.createDirectory(at: workspace.imagesFolder, withIntermediateDirectories: true)
                try? data.write(to: file)
                workspace.save(ChatMessage(chatID: thread.id, role: .assistant, parts: [
                    .text(String(localized: "Here's your screen right now.")),
                    .image(ImagePart(id: id, path: file.path(percentEncoded: false), width: width, height: height, caption: "Safari")),
                    .notice("Handed to Forge: tidy up the old projects folder"),
                    .lesson(String(localized: "When Xcode asks to trust a package, choose Trust and Enable")),
                ]))
            }
        default: break
        }
        workspace.touch(thread.id)
        return .reply(requestID: request, ok: true, reason: nil, chatID: thread.id)
    }
    #endif

    /// A thread's last message, in a line, for the phone's list. Pictures aren't read for it.
    func threadPreview(_ chatID: UUID) -> String? {
        workspace.loadTranscript(chatID)
        guard let last = workspace.messages(in: chatID).last else { return nil }
        let parts = last.parts.map { part -> RemotePart in
            if case .image(let image) = part {
                return .image(RemoteImage(id: image.id, jpeg: nil, width: image.width, height: image.height, caption: image.caption))
            }
            return Self.remote(part)
        }
        let preview = AgenticDigest.preview(of: RemoteMessage(id: last.id, role: last.role.rawValue, parts: parts, createdAt: last.createdAt))
        return preview.isEmpty ? nil : preview
    }

    #if DEBUG
    /// A made-up desktop (a wallpaper and two windows), so the demo needs no screen recording.
    static func demoScreen() -> Data? {
        let width = 2880, height = 1800
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [CGColor(red: 0.18, green: 0.2, blue: 0.55, alpha: 1),
                                                 CGColor(red: 0.85, green: 0.4, blue: 0.55, alpha: 1)] as CFArray,
                                        locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        for (frame, alpha) in [(CGRect(x: 260, y: 300, width: 1500, height: 1100), 0.96), (CGRect(x: 1500, y: 180, width: 1100, height: 800), 0.9)] {
            context.setFillColor(CGColor(gray: 1, alpha: alpha))
            context.addPath(CGPath(roundedRect: frame, cornerWidth: 36, cornerHeight: 36, transform: nil))
            context.fillPath()
            context.setFillColor(CGColor(gray: 0.9, alpha: 1))
            context.fill(CGRect(x: frame.minX, y: frame.maxY - 90, width: frame.width, height: 54))
            for (index, color) in [(0, CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1)), (1, CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1)),
                                   (2, CGColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1))] {
                context.setFillColor(color)
                context.fillEllipse(in: CGRect(x: frame.minX + 34 + CGFloat(index) * 44, y: frame.maxY - 66, width: 26, height: 26))
            }
            context.setFillColor(CGColor(gray: 0.82, alpha: 1))
            for line in 0..<8 {
                context.fill(CGRect(x: frame.minX + 60, y: frame.maxY - 190 - CGFloat(line) * 90, width: frame.width * (line % 3 == 2 ? 0.45 : 0.8), height: 34))
            }
        }
        guard let image = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
    #endif
}
