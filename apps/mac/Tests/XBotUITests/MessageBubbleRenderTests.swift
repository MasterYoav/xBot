import SwiftUI
import Testing
import XBotCore
import XBotEngine
@testable import XBotUI

/// The bubble, actually drawn.
///
/// Views do not get unit tests here — CLAUDE.md says so, and it is right about the ones that only
/// arrange state. This one stopped being that when markdown landed: it splits a reply into blocks,
/// tokenises code and concatenates coloured runs, and every one of those can compile and then draw
/// nothing. `ImageRenderer` is the cheapest way to find that out, and it costs a fraction of a
/// second.
///
/// It asserts the picture is not blank rather than comparing to a reference image. A snapshot test
/// would fail on every font-rendering change in every macOS release, which is how snapshot suites
/// end up disabled; "something was drawn, in more than one colour" is the part that actually breaks.
@MainActor
@Suite
struct MessageBubbleRenderTests {
    private func render(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.frame(width: 480))
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: data))
    }

    /// How many distinct colours were drawn, sampled on a grid.
    ///
    /// A view that lays out but paints nothing gives one — the background — which is exactly the
    /// failure that compiles cleanly and passes every other kind of test.
    private func colourCount(_ bitmap: NSBitmapImageRep) -> Int {
        var seen = Set<String>()
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                seen.insert(
                    "\(Int(colour.redComponent * 255)),"
                        + "\(Int(colour.greenComponent * 255)),"
                        + "\(Int(colour.blueComponent * 255))"
                )
            }
        }
        return seen.count
    }

    @Test func aReplyWithMarkdownDrawsSomething() throws {
        let message = Message(
            id: "m1",
            author: .agent("Orchestrator"),
            text: "The **three** files are in `registry.ts`, and *that* is all."
        )
        let bitmap = try render(MessageBubble(message: message))
        #expect(bitmap.pixelsWide > 0)
        #expect(colourCount(bitmap) > 1)
    }

    /// The risk that is invisible until it is drawn.
    ///
    /// The bubble applies `.foregroundStyle` to everything inside it. If that won over the
    /// per-token colours the highlighter produces, every keyword, string and comment would collapse
    /// to one colour — a code block that still renders, still passes the splitter's tests, and is
    /// just quietly not highlighted any more.
    @Test func codeKeepsItsOwnColoursUnderTheBubblesForegroundStyle() throws {
        let tokens = CodeHighlight.tokens(
            "let x = \"hi\" // note\nif x { return 42 }",
            language: "swift"
        )
        let text = tokens.reduce(Text(verbatim: "")) { result, token in
            let colour: Color = switch token.1 {
            case .plain: Palette.textPrimary
            case .keyword: Palette.codeKeyword
            case .string: Palette.codeString
            case .comment: Palette.codeComment
            case .number: Palette.codeNumber
            }
            return result + Text(verbatim: token.0).foregroundColor(colour)
        }

        let plain = try render(
            Text(verbatim: "let x = \"hi\" // note\nif x { return 42 }")
                .font(Typography.mono)
                .foregroundStyle(Palette.bubbleIncomingText)
        )
        let coloured = try render(
            text
                .font(Typography.mono)
                // The bubble's own style, applied the way the bubble applies it.
                .foregroundStyle(Palette.bubbleIncomingText)
        )

        // Strictly more colours than the same text in one colour. An ancestor style that won would
        // make these equal.
        #expect(colourCount(coloured) > colourCount(plain))
    }
}
