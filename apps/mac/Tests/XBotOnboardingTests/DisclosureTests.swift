import Foundation
import Testing
@testable import XBotOnboarding

/**
 The promises the first run makes, checked against what v1 actually does.

 ADR-0007 keeps CopilotKit Intelligence for v1 and is explicit that two claims in the vision do not
 hold because of it: "No account", and "nothing leaves your machine except the calls you choose".
 The ADR says the vision document "has been changed rather than quietly reinterpreted" — but the
 first screen of the product still said "Everything stays here. No account, no cloud", which asserts
 both of them.

 These are string tests, which is unusual and deliberate. The claim is the feature: an app whose
 pitch is local control must not be vague about the part that is not local, and a copy edit is
 exactly how that protection would be lost.
 */
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
        // The part that is not local, named rather than implied.
        #expect(disclosure.contains("copilotkit"))
        #expect(disclosure.contains("leaves your mac"))
    }
}
