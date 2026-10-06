import AppKit
import SwiftUI

/// The About window, and the credits that travel with the app.
///
/// xBot's design follows MonoCode, and xBot 1.x ran on OpenBot's engine (MIT, © 2026 CopilotKit).
/// `NOTICE` at the repository root says both, but a person who downloads a `.dmg` never sees the
/// repository, so the credits have to travel with the thing that ships.
///
/// It is the system panel rather than a window of our own. AppKit already draws the icon, the name,
/// the version and the copyright line correctly, in every language and at every text size, and
/// takes an attributed string for the rest. A hand-built window would be a worse copy of it, and
/// this is the one screen where being conventional is the whole point.
public enum AboutPanel {
    /// Where Help points. The repository's docs index, because that is what exists — an app that
    /// ships a Help menu pointing at a help book it does not have is worse than one with no Help
    /// menu at all.
    public static let documentationURL = URL(string: "https://github.com/MasterYoav/xBot#documentation")!

    public static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [.credits: credits]
        )
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// The credit, with the link live. A URL somebody has to retype is not a link.
    /// Exposed so a test can hold it to the obligation. The credit is a licence term, not
    /// decoration, and the way it would go missing is a refactor nobody thought was about licences.
    public static var credits: NSAttributedString {
        let body = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 11)

        let text: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        func link(_ title: String, _ url: String) -> NSAttributedString {
            NSAttributedString(string: title, attributes: [.font: font, .link: URL(string: url)!])
        }

        body.append(NSAttributedString(
            string: String(localized: "Your own AI coworkers, on your own Mac.\n\nDesigned after "),
            attributes: text
        ))
        body.append(link("MonoCode", "https://github.com/hardbeat920/monocode"))
        body.append(NSAttributedString(
            string: String(localized: ". xBot 1.x was built on "),
            attributes: text
        ))
        body.append(link("OpenBot", "https://github.com/CopilotKit/openbot"))
        body.append(NSAttributedString(string: String(localized: " by "), attributes: text))
        body.append(link("CopilotKit", "https://copilotkit.ai"))
        body.append(NSAttributedString(
            string: String(localized: ", used under the MIT licence."),
            attributes: text
        ))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        body.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: body.length)
        )
        return body
    }
}
