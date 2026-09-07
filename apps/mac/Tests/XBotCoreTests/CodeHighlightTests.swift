import Testing
@testable import XBotCore

/// The small highlighter behind code blocks in a bubble.
@Suite
struct CodeHighlightTests {
    /// The invariant that makes an approximate highlighter safe: a token classified wrong is a word
    /// in the wrong colour, never a character that fails to appear.
    private func reassembled(_ code: String, language: String? = nil) -> String {
        CodeHighlight.tokens(code, language: language).map(\.0).joined()
    }

    @Test func everyCharacterSurvives() {
        for sample in [
            "let x = \"hi\" // note",
            "def f(): # comment\n    return 1",
            "/* block */ const a = `t`;",
            "an unterminated \"string",
            "",
        ] {
            #expect(reassembled(sample, language: "python") == sample)
        }
    }

    @Test func keywordsStringsAndNumbersAreFound() {
        let tokens = CodeHighlight.tokens("let x = 42", language: "swift")
        #expect(tokens.contains { $0 == ("let", .keyword) })
        #expect(tokens.contains { $0 == ("42", .number) })

        let string = CodeHighlight.tokens("f(\"hi\")", language: nil)
        #expect(string.contains { $0 == ("\"hi\"", .string) })
    }

    @Test func aBackslashDoesNotEndAString() {
        let tokens = CodeHighlight.tokens("\"a\\\"b\" x", language: nil)
        #expect(tokens.first?.0 == "\"a\\\"b\"")
        #expect(tokens.first?.1 == .string)
    }

    /// `#` opens a comment in a shell snippet and does not in `#expect` or a CSS colour.
    @Test func hashIsOnlyACommentWhereItIsOne() {
        #expect(CodeHighlight.tokens("# hi", language: "bash").first?.1 == .comment)
        #expect(CodeHighlight.tokens("#expect(x)", language: "swift").first?.1 != .comment)
    }

    @Test func blockCommentsEndAtTheirTerminator() {
        let tokens = CodeHighlight.tokens("/* a */ let", language: "swift")
        #expect(tokens.first?.0 == "/* a */")
        #expect(tokens.contains { $0 == ("let", .keyword) })
    }
}
