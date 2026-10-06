import AppKit
import Testing
@testable import XBotUI

/// The credits that travel with the app. A person who downloads a `.dmg` never sees `NOTICE`.
///
/// A test for a string looks tautological until you ask how it would go missing: not by somebody
/// deciding to drop a credit, but by a refactor of the About panel that nobody thought was about
/// credits.
@Suite
struct AboutCreditTests {
    /// The design xBot follows.
    @Test func theAboutPanelCreditsMonoCodeWithALink() {
        #expect(AboutPanel.credits.string.contains("MonoCode"))
        #expect(links().contains { $0.absoluteString.contains("hardbeat920/monocode") })
    }

    /// xBot 1.x shipped OpenBot's engine; the credit stays with the product that grew out of it.
    @Test func theAboutPanelStillCreditsOpenBotAndCopilotKit() {
        let credits = AboutPanel.credits.string
        #expect(credits.contains("OpenBot"))
        #expect(credits.contains("CopilotKit"))
        #expect(links().contains { $0.absoluteString.contains("CopilotKit/openbot") })
    }

    private func links() -> [URL] {
        var found: [URL] = []
        let whole = NSRange(location: 0, length: AboutPanel.credits.length)
        AboutPanel.credits.enumerateAttribute(.link, in: whole) { value, _, _ in
            if let url = value as? URL { found.append(url) }
        }
        return found
    }
}

/// Where the Help menu goes.
///
/// SwiftUI's default "xBot Help" opens Help Viewer, which looks for a help book this app has never
/// had and tells the person help is not available — a menu item that exists only to say no, in the
/// one menu somebody opens because they are already stuck.
@Suite
struct DocumentationLinkTests {
    @Test func helpPointsAtSomethingThatExists() {
        let url = AboutPanel.documentationURL
        #expect(url.scheme == "https")
        #expect(url.host()?.contains("github.com") == true)
        #expect(url.absoluteString.contains("xBot"))
    }
}
