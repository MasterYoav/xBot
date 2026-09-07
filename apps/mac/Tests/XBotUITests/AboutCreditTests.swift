import AppKit
import Testing
@testable import XBotUI

/// The attribution the engine's licence requires, and CLAUDE.md calls "a requirement, not a
/// courtesy".
///
/// A test for a string looks tautological until you ask how it would go missing: not by somebody
/// deciding to drop the credit, but by a refactor of the About panel that nobody thought was about
/// licences. `NOTICE` covers the repository; a person who downloads a `.dmg` never sees the
/// repository, so the credit has to travel with the thing that ships.
@Suite
struct AboutCreditTests {
    @Test func theAboutPanelCreditsOpenBotAndCopilotKit() {
        let credits = AboutPanel.credits.string
        #expect(credits.contains("OpenBot"))
        #expect(credits.contains("CopilotKit"))
        #expect(credits.contains("MIT"))
        #expect(credits.contains("2026"))
    }

    /// With the link live. A URL somebody has to retype is not a link, and "credits OpenBot with a
    /// link" is how the requirement is worded.
    @Test func openBotIsALinkAndNotJustAWord() {
        var found: [URL] = []
        let whole = NSRange(location: 0, length: AboutPanel.credits.length)
        AboutPanel.credits.enumerateAttribute(.link, in: whole) { value, _, _ in
            if let url = value as? URL { found.append(url) }
        }
        #expect(found.contains { $0.absoluteString.contains("CopilotKit/openbot") })
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
