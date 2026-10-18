import Foundation
import Testing
@testable import XBotRemote

@Suite struct AgenticWireTests {
    @Test func picturesApprovalsAndLessonsSurviveTheWire() throws {
        let parts: [RemotePart] = [
            .image(RemoteImage(id: UUID(), jpeg: Data([0xFF, 0xD8, 0xFF]), width: 1600, height: 1000, caption: "Safari")),
            .approval(RemoteApproval(id: UUID(), agent: "Forge", summary: "Delete 3 files", detail: "rm a b c",
                                     risk: "delete", state: "pending", answeredBy: nil)),
            .lesson("When Xcode asks to trust a package, choose Trust and Enable"),
        ]
        let message = RemoteMessage(id: UUID(), role: "assistant", parts: parts, createdAt: Date(timeIntervalSince1970: 1000))
        let data = try Wire.encoder.encode(message)
        #expect(try Wire.decoder.decode(RemoteMessage.self, from: data) == message)
    }

    /// A newer Mac may send a part this phone doesn't know: it becomes nothing, and the message's
    /// other parts still arrive.
    @Test func anUnknownPartDoesntLoseTheMessage() throws {
        let json = #"{"id":"6F1C9C65-6C0C-4F09-8C1F-2D1B7E0B0A11","role":"assistant","createdAt":1000,"parts":[{"text":{"_0":"hi"}},{"hologram":{"_0":"x"}}]}"#
        let message = try Wire.decoder.decode(RemoteMessage.self, from: Data(json.utf8))
        #expect(message.parts == [.text("hi"), .unknown])
    }
}
