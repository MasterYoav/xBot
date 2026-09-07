import Foundation
import Testing
@testable import XBotCore

/// Splitting a reply into prose and code, which a bubble draws differently.
@Suite
struct MessageMarkdownTests {
    @Test func plainTextIsOneProseBlock() {
        #expect(MessageMarkdown.blocks(of: "hello there") == [.prose("hello there")])
        #expect(MessageMarkdown.blocks(of: "").isEmpty)
    }

    @Test func afenceBecomesACodeBlockWithItsLanguage() {
        let blocks = MessageMarkdown.blocks(of: """
        Try this:
        ```swift
        let x = 1
        ```
        and then run it.
        """)
        #expect(blocks == [
            .prose("Try this:"),
            .code("let x = 1", language: "swift"),
            .prose("and then run it."),
        ])
    }

    @Test func aFenceWithoutALanguageStillWorks() {
        #expect(
            MessageMarkdown.blocks(of: "```\nls -la\n```") == [.code("ls -la", language: nil)]
        )
    }

    /**
     The streaming case, and the reason this is parsed rather than rendered directly.

     While a reply types, the closing fence has not arrived yet. Treating the tail as prose until it
     does would redraw the block the moment it lands, so every reply containing code would flicker
     between two layouts as it streams.
     */
    @Test func anUnterminatedFenceIsCodeFromTheFirstLine() {
        let blocks = MessageMarkdown.blocks(of: "Here:\n```python\nprint(1)")
        #expect(blocks == [.prose("Here:"), .code("print(1)", language: "python")])
    }

    @Test func emptyProseBetweenBlocksIsDropped() {
        // Two fences back to back leave a blank line between them, which would otherwise draw as an
        // empty paragraph with real spacing around it.
        let blocks = MessageMarkdown.blocks(of: "```\na\n```\n\n```\nb\n```")
        #expect(blocks == [.code("a", language: nil), .code("b", language: nil)])
    }

    @Test func inlineMarkdownIsInterpreted() {
        let attributed = MessageMarkdown.inline("a **bold** word")
        #expect(String(attributed.characters) == "a bold word")
    }

    /// A reply is not worth losing to a stray bracket, and half-typed markdown is the normal state
    /// of a streaming one.
    @Test func brokenInlineMarkdownKeepsTheText() {
        let text = "an unclosed [link and **bold"
        #expect(String(MessageMarkdown.inline(text).characters).contains("unclosed"))
    }
}
