import Foundation
import Testing
@testable import XBotMarkdown

@Suite struct MarkdownDocumentTests {
    let sample = """
    # Title

    Some *intro* text with `code`
    on two lines.

    - one
    - [x] done
      more of done
    1. first

    > a quote
    > second

    ```swift
    let x = 1
    ```

    ---
    | a | b |
    |---|---|

    Setext
    ======
    """ + "\n"

    @Test func untouchedIsByteForByte() {
        for text in [sample, "", "Just text", "a\n\n\n\nb\n\n", "  - indented\n    - deeper\n", "<div>\nhi\n</div>\n"] {
            #expect(MarkdownDocument(parsing: text).markdown == text, "\(text.debugDescription)")
        }
    }

    @Test func blocksAreRecognised() {
        let kinds = MarkdownDocument(parsing: sample).blocks.map(\.kind)
        #expect(kinds == [.heading(level: 1), .paragraph, .bullet(indent: 0, checked: nil), .bullet(indent: 0, checked: true),
                          .numbered(indent: 0, number: 1), .quote, .code(language: "swift"), .rule, .raw, .heading(level: 1)])
        let doc = MarkdownDocument(parsing: sample)
        #expect(doc.blocks[3].text == "done\nmore of done")
        #expect(doc.blocks[5].text == "a quote\nsecond")
        #expect(doc.blocks[6].text == "let x = 1")
        #expect(doc.blocks[9].text == "Setext")
    }

    @Test func onlyEditedBlocksAreRewritten() {
        var doc = MarkdownDocument(parsing: "Intro   with  spaces\n\n* star item\n\nEnd\n")
        doc.blocks[2].text = "The end"
        #expect(doc.markdown == "Intro   with  spaces\n\n* star item\n\nThe end\n")
        doc.blocks[1].kind = .bullet(indent: 0, checked: false)
        #expect(doc.markdown == "Intro   with  spaces\n\n- [ ] star item\n\nThe end\n")
    }

    @Test func newBlocksGetSensibleSpacing() {
        var doc = MarkdownDocument(parsing: "- a\n")
        doc.blocks.append(.init(kind: .bullet(indent: 0, checked: nil), text: "b"))
        doc.blocks.append(.init(kind: .paragraph, text: "After"))
        doc.blocks.insert(.init(kind: .heading(level: 2), text: "Top"), at: 0)
        #expect(doc.markdown == "## Top\n\n- a\n- b\n\nAfter\n")
    }

    @Test func editedBlocksRenderEachKind() {
        let cases: [(MarkdownDocument.Kind, String, String)] = [
            (.heading(level: 3), "Hi", "### Hi"),
            (.numbered(indent: 2, number: 4), "x\ny", "  4. x\n     y"),
            (.quote, "a\n\nb", "> a\n>\n> b"),
            (.code(language: "js"), "f()", "```js\nf()\n```"),
            (.rule, "", "---"),
        ]
        for (kind, text, expected) in cases {
            #expect(MarkdownDocument.render(.init(kind: kind, text: text)) == expected)
        }
    }

    @Test func inlineRoundTrips() {
        for source in ["plain", "**bold** and *em* and `co*de` and ~~gone~~", "a [link](https://xbot.dev) here",
                       "mixed **bold *both*** end", "star \\* literal"] {
            let styled = InlineMarkdown.attributed(source)
            let back = InlineMarkdown.markdown(styled)
            // Re-reading what we wrote gives the same styled text.
            #expect(Self.looks(InlineMarkdown.attributed(back)) == Self.looks(styled), "\(source) → \(back)")
        }
    }

    /// Each visible character with its styling (a space's styling doesn't show, so it's ignored).
    static func looks(_ text: AttributedString) -> [String] {
        text.runs.flatMap { run in
            text[run.range].characters.map { c in
                c.isWhitespace ? String(c) : "\(c)|\(run.inlinePresentationIntent?.rawValue ?? 0)|\(run.link?.absoluteString ?? "")"
            }
        }
    }

    @Test func styledTextBecomesMarkdown() {
        var text = AttributedString("Hello world")
        let world = text.range(of: "world")!
        text[world].inlinePresentationIntent = .stronglyEmphasized
        #expect(InlineMarkdown.markdown(text) == "Hello **world**")
        // Bold that starts with a space keeps the space outside the markers.
        var spaced = AttributedString("a b")
        spaced[spaced.range(of: " b")!].inlinePresentationIntent = .emphasized
        #expect(InlineMarkdown.markdown(spaced) == "a *b*")
    }
}
