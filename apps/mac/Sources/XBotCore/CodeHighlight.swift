import Foundation

/// Enough syntax highlighting for a code block in a chat bubble.
///
/// docs/09-ui-spec.md asks for syntax highlighting on code blocks, and CLAUDE.md rules out a
/// third-party framework for it. What a reply actually contains is a short snippet in whichever
/// language the person was asking about, so a per-language grammar would be a lot of code to make a
/// dozen lines legible.
///
/// This is the small version: strings, comments and numbers — the runs whose colour does the real
/// work of showing where one thing ends and the next begins — plus keywords shared across the
/// languages that turn up. It is deliberately approximate, and being approximate is safe: a token
/// classified wrong is a word in the wrong colour, never a character that fails to appear.
public enum CodeHighlight {
    public enum Token: Equatable, Sendable {
        case plain, keyword, string, comment, number
    }

    /// Keywords, pooled rather than kept per language.
    ///
    /// A per-language table would need a language on every block, and a fence often arrives with no
    /// tag at all. Pooling costs the occasional `import` coloured inside a shell snippet — which is
    /// the harmless direction to be wrong in.
    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "class", "struct", "enum",
        "protocol", "extension", "import", "guard", "switch", "case", "default", "break",
        "continue", "public", "private", "internal", "static", "async", "await", "try", "throw",
        "throws", "catch", "do", "in", "is", "as", "self", "nil", "true", "false", "init",
        "const", "function", "export", "interface", "type", "new", "this", "null", "undefined",
        "def", "elif", "None", "True", "False", "lambda", "pass", "with", "from", "not", "and",
        "or", "echo", "fi", "then", "done", "local", "fn", "impl", "match", "mut", "use", "pub",
    ]

    /// Languages where `#` opens a comment. Elsewhere it is `#expect`, `#Preview`, or a CSS colour.
    private static let hashComments: Set<String> = [
        "python", "py", "ruby", "rb", "sh", "bash", "zsh", "shell", "yaml", "yml", "toml", "perl",
    ]

    public static func tokens(_ code: String, language: String?) -> [(String, Token)] {
        let hashIsComment = hashComments.contains(language?.lowercased() ?? "")
        var tokens: [(String, Token)] = []
        var current = ""
        var kind = Token.plain

        func flush() {
            guard !current.isEmpty else { return }
            // A plain run is only a keyword if it is the whole word, which it is: a word run is
            // accumulated until a non-word character ends it.
            let resolved = kind == .plain && keywords.contains(current) ? .keyword : kind
            tokens.append((current, resolved))
            current = ""
            kind = .plain
        }

        var characters = Array(code)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if character == "/", next == "/" || next == "*" {
                flush()
                let block = next == "*"
                var comment = ""
                while index < characters.count {
                    comment.append(characters[index])
                    if block, comment.count > 3, comment.hasSuffix("*/") { index += 1; break }
                    if !block, characters[index] == "\n" { index += 1; break }
                    index += 1
                }
                tokens.append((comment, .comment))
                continue
            }

            if character == "#", hashIsComment {
                flush()
                var comment = ""
                while index < characters.count, characters[index] != "\n" {
                    comment.append(characters[index])
                    index += 1
                }
                tokens.append((comment, .comment))
                continue
            }

            if character == "\"" || character == "'" || character == "`" {
                flush()
                var string = String(character)
                index += 1
                while index < characters.count {
                    let inner = characters[index]
                    string.append(inner)
                    index += 1
                    // A backslash consumes whatever follows, so `"\""` does not end here.
                    if inner == "\\", index < characters.count {
                        string.append(characters[index])
                        index += 1
                        continue
                    }
                    if inner == character { break }
                    // An unterminated quote stops at the line rather than swallowing the rest of
                    // the block: an apostrophe in a comment is more common than a multi-line string.
                    if inner == "\n" { break }
                }
                tokens.append((string, .string))
                continue
            }

            let isWord = character.isLetter || character.isNumber || character == "_"
            if isWord {
                if kind == .plain, current.isEmpty, character.isNumber { kind = .number }
                if kind == .number, character.isLetter, character != "." { kind = .plain }
                current.append(character)
            } else {
                flush()
                tokens.append((String(character), .plain))
            }
            index += 1
        }
        flush()
        return tokens
    }
}
