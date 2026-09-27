import Foundation
import Testing
@testable import XBotOnboarding

/**
 The promises the first run makes, checked against what v1 actually does.

 Since ADR-0008, conversations are kept by the engine's own local history (`LocalThreadRunner`)
 rather than CopilotKit Intelligence, so "no account" and "everything stays on this Mac" are true
 again — for the conversation. They are still not true for a message's content: whatever a person
 sends still goes to whichever model they picked, unless that model runs on this Mac too. "No cloud"
 stays unsaid because it would claim the model call as local as well, which it is not.

 These are string tests, which is unusual and deliberate. The claim is the feature: an app whose
 pitch is local control must not be vague about the part that is not local, and a copy edit is
 exactly how that protection would be lost.
 */
@MainActor
@Suite
struct OnboardingDisclosureTests {
    @Test func theWelcomeScreenDoesNotPromiseNoCloud() {
        let bullets = WelcomeStep.bulletsForTesting.joined(separator: " ").lowercased()
        #expect(!bullets.contains("no cloud"))
        #expect(!bullets.contains("no account"))
        // What is still true, and worth saying.
        #expect(bullets.contains("stay on this mac"))
    }

    @Test func theKeyStepSaysWhereConversationsAreKept() {
        let disclosure = ConnectModelStep.transcriptDisclosureText.lowercased()
        // What is local, named rather than implied…
        #expect(disclosure.contains("conversations stay on this mac"))
        // …and what is not: whatever is sent still goes to the model that was picked.
        #expect(disclosure.contains("goes to the model"))
    }
}
