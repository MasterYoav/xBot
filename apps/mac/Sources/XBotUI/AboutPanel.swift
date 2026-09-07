import AppKit
import SwiftUI

/// The About window, which exists because the licence and CLAUDE.md both require it.
///
/// "The About window credits OpenBot with a link. This is a requirement, not a courtesy." The
/// engine is a derivative work of OpenBot, MIT licensed, © 2026 CopilotKit; `NOTICE` at the
/// repository root has said so all along, and a person who downloads a `.dmg` never sees the
/// repository. The credit has to travel with the thing that ships.
///
/// It is the system panel rather than a window of our own. AppKit already draws the icon, the name,
/// the version and the copyright line correctly, in every language and at every text size, and
/// takes an attributed string for the rest. A hand-built window would be a worse copy of it, and
/// this is the one screen where being conventional is the whole point.
public enum AboutPanel {
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

        body.append(
            NSAttributedString(
                string: String(
                    localized: "Your own AI coworkers, on your own Mac.\n\nxBot's engine is a fork of "
                ),
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
        )
        body.append(
            NSAttributedString(
                string: "OpenBot",
                attributes: [
                    .font: font,
                    .link: URL(string: "https://github.com/CopilotKit/openbot")!,
                ]
            )
        )
        body.append(
            NSAttributedString(
                string: String(localized: " by "),
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
        )
        body.append(
            NSAttributedString(
                string: "CopilotKit",
                attributes: [
                    .font: font,
                    .link: URL(string: "https://copilotkit.ai")!,
                ]
            )
        )
        body.append(
            NSAttributedString(
                string: String(
                    localized: ", used under the MIT licence. Copyright © 2026 CopilotKit."
                ),
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
        )

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
