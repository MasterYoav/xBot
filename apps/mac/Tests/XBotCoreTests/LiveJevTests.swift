import Foundation
import Testing
@testable import XBotCore

/// One real call to Jev of each question type, with the key saved in Settings › AI (the login
/// Keychain). Off by default: it needs a key and costs a little. Run with
/// `XBOT_LIVE_JEV=1 swift test --filter LiveJevTests` to see whether Jev's answers still read.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["XBOT_LIVE_JEV"] == "1"))
struct LiveJevTests {
    @Test func oneRealCallOfEachType() async throws {
        let settings = JevSettings(defaults: freshDefaults(), keys: KeychainJevKeyStore())
        let client = try #require(settings.client(timeout: .seconds(20)), "No Jev key in Settings › AI")
        let response = try await client.ask(state: "The build failed: 3 tests in ParserTests are red.", questions: [
            "failing": .noul("Is the build failing?"),
            "next": .choice("What should happen next?", options: [
                .init(key: "fix", description: "Fix the failing tests"),
                .init(key: "ship", description: "Release the build"),
            ]),
            "severity": .score("How severe is this?", levels: ["Trivial", "Minor", "Major", "Critical"]),
        ])
        #expect(!response.model.isEmpty)
        guard case .noul(let p) = response.answers["failing"] else { Issue.record("no noul answer"); return }
        #expect(p > 0.5)
        #expect(response.answers["next"]?.choice == "fix")
        guard case .score(let score, _, _, _) = response.answers["severity"] else { Issue.record("no score answer"); return }
        #expect((0...3).contains(score))
    }
}
