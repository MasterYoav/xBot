import Foundation

/// Masks what looks like a secret in a command line or an address, for showing it: an MCP
/// server's is shown on the Abilities page and sent to a paired phone, and people put their tokens
/// in them (`--token …`, `GITHUB_TOKEN=…`, `https://user:pass@…`, `?api_key=…`). It errs towards
/// masking: the person can see the full line where they wrote it.
public enum SecretRedaction {
    public static let mask = "••••"

    /// Name parts (split on `-` and `_`) that mark the value after them as a secret.
    private static let secretWords: Set<String> = [
        "token", "secret", "password", "passwd", "pwd", "key", "apikey", "auth", "credential",
        "credentials", "pat", "cookie",
    ]

    /// Authorization schemes: the credential is the word after them.
    private static let schemes: Set<String> = ["bearer", "basic", "token"]

    public static func redact(_ text: String) -> String {
        var maskNext = false
        var words: [String] = []
        for word in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            if word.isEmpty { words.append(word); continue }
            if maskNext {
                if schemes.contains(word.lowercased()) { words.append(word); continue }   // "Bearer <token>"
                maskNext = false
                if !word.hasPrefix("-") { words.append(mask); continue }
            }
            if schemes.contains(word.lowercased()), word.first?.isUppercase == true {
                maskNext = true
                words.append(word)
                continue
            }
            // --token abc, X-API-Key: abc
            if word.hasPrefix("-") && !word.contains("=") || word.hasSuffix(":") && !word.contains("://") {
                if isSecretName(word) { maskNext = true }
                words.append(word)
                continue
            }
            // --api-key=abc, GITHUB_TOKEN=abc, --url=https://… (an = before any scheme)
            if let equals = word.firstIndex(of: "="), equals > word.startIndex,
               word.range(of: "://").map({ equals < $0.lowerBound }) ?? true {
                let name = String(word[..<equals])
                let value = String(word[word.index(after: equals)...])
                words.append(name + "=" + (isSecretName(name) && !value.isEmpty ? mask : redactURL(value)))
                continue
            }
            words.append(redactURL(word))
        }
        return words.joined(separator: " ")
    }

    /// `scheme://user:pass@host/path?k=v#k=v` → userinfo and every query and fragment value masked.
    static func redactURL(_ word: String) -> String {
        guard let scheme = word.range(of: "://") else { return word }
        var head = String(word[..<scheme.upperBound])
        var rest = String(word[scheme.upperBound...])
        // Userinfo: an @ before the first / ? or # after the scheme.
        let authorityEnd = rest.firstIndex { "/?#".contains($0) } ?? rest.endIndex
        if let at = rest[..<authorityEnd].lastIndex(of: "@") {
            rest = mask + rest[at...]
        }
        guard let start = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) else { return head + rest }
        head += rest[..<start]
        var tail = ""
        var piece = ""
        func flush() {
            if let eq = piece.firstIndex(of: "="), piece.index(after: eq) < piece.endIndex {
                tail += piece[...eq] + mask
            } else {
                tail += piece
            }
            piece = ""
        }
        for character in rest[start...] {
            if "?#&;".contains(character) {
                flush()
                tail.append(character)
            } else {
                piece.append(character)
            }
        }
        flush()
        return head + tail
    }

    private static func isSecretName(_ name: String) -> Bool {
        let bare = name.trimmingCharacters(in: CharacterSet(charactersIn: "-:"))
        return bare.lowercased().split { $0 == "-" || $0 == "_" || $0 == "." }.contains { secretWords.contains(String($0)) }
    }
}
