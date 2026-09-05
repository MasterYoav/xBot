import Foundation
import Testing
@testable import XBotCore

/// Where Sparkle may take its appcast and its signing key from.
///
/// The public key decides what the app will install. `SparkleAppUpdateController` read both it and
/// the feed URL from the environment, so anything able to set an environment variable for the app
/// could supply its own feed and its own key — and Sparkle would verify the attacker's update
/// against the attacker's key and install it.
@Suite
struct AppUpdateTrustTests {
    @Test func aReleaseBuildTrustsOnlyItsSignedBundle() {
        // The bundled Info.plist is inside the code-signed app; the environment is not signed by
        // anybody. In debug the override stays, because that is how an appcast is tested.
        #if DEBUG
        #expect(AppUpdateTrust.allowsEnvironmentOverride)
        #else
        #expect(!AppUpdateTrust.allowsEnvironmentOverride)
        #endif
    }

    @Test func onlyHttpsFeedsAreAcceptable() {
        #expect(AppUpdateTrust.isAcceptableFeed("https://updates.example.com/appcast.xml"))
        // Rewritable in transit by anyone on the path. The signature still has to check out, but
        // the feed also carries the version and the download URL — enough to stage a downgrade.
        #expect(!AppUpdateTrust.isAcceptableFeed("http://updates.example.com/appcast.xml"))
    }

    @Test func nonsenseIsNotAFeed() {
        for value in ["", "   ", "appcast.xml", "file:///tmp/appcast.xml", "https://", "javascript:alert(1)"] {
            #expect(!AppUpdateTrust.isAcceptableFeed(value), "\(value) must not be accepted")
        }
    }
}
