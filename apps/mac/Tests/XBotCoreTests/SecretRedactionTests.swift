import Foundation
import Testing
@testable import XBotCore

/// MCP servers' command lines and addresses are shown in the app and sent to a paired phone, and
/// they often carry a token. What looks like a secret is masked; the rest is left as it was.
@Suite struct SecretRedactionTests {
    let mask = SecretRedaction.mask

    @Test func plainCommandLinesAreUnchanged() {
        #expect(SecretRedaction.redact("headroom mcp serve") == "headroom mcp serve")
        #expect(SecretRedaction.redact("npx -y @modelcontextprotocol/server-filesystem /Users/me") == "npx -y @modelcontextprotocol/server-filesystem /Users/me")
        #expect(SecretRedaction.redact("https://mcp.example.com/sse") == "https://mcp.example.com/sse")
        #expect(SecretRedaction.redact("") == "")
    }

    @Test func urlQueryValuesAreMasked() {
        #expect(SecretRedaction.redact("https://mcp.example.com/sse?api_key=abc123&team=x")
            == "https://mcp.example.com/sse?api_key=\(mask)&team=\(mask)")
        #expect(SecretRedaction.redact("https://h.example/p#access_token=abc") == "https://h.example/p#access_token=\(mask)")
    }

    @Test func urlUserinfoIsMasked() {
        #expect(SecretRedaction.redact("https://me:hunter2@mcp.example.com/x") == "https://\(mask)@mcp.example.com/x")
        #expect(SecretRedaction.redact("https://ghp_abc@mcp.example.com") == "https://\(mask)@mcp.example.com")
        // An @ in the path isn't userinfo.
        #expect(SecretRedaction.redact("https://registry.example/@scope/pkg") == "https://registry.example/@scope/pkg")
    }

    @Test func secretFlagsAreMasked() {
        #expect(SecretRedaction.redact("server --token abc --port 3000") == "server --token \(mask) --port 3000")
        #expect(SecretRedaction.redact("server --api-key=abc") == "server --api-key=\(mask)")
        #expect(SecretRedaction.redact("server --access-token abc") == "server --access-token \(mask)")
        #expect(SecretRedaction.redact("server --password p --verbose") == "server --password \(mask) --verbose")
    }

    @Test func secretAssignmentsAreMasked() {
        #expect(SecretRedaction.redact("env GITHUB_TOKEN=ghp_x OPENAI_API_KEY=sk-1 node s.js")
            == "env GITHUB_TOKEN=\(mask) OPENAI_API_KEY=\(mask) node s.js")
        #expect(SecretRedaction.redact("docker run -e STRIPE_SECRET=s image") == "docker run -e STRIPE_SECRET=\(mask) image")
        #expect(SecretRedaction.redact("run MODE=fast") == "run MODE=fast")
    }

    @Test func bearerTokensAreMasked() {
        #expect(SecretRedaction.redact("mcp-remote https://x.example --header Authorization: Bearer abc.def")
            == "mcp-remote https://x.example --header Authorization: Bearer \(mask)")
        #expect(SecretRedaction.redact("--header X-API-Key: abc") == "--header X-API-Key: \(mask)")
    }

    @Test func aUrlInsideAnOptionIsRedactedToo() {
        #expect(SecretRedaction.redact("mcp-remote --url=https://u:p@x.example/?k=v")
            == "mcp-remote --url=https://\(mask)@x.example/?k=\(mask)")
    }

    /// The Abilities page and the phone both read the server's summary from here.
    @Test func mcpSummariesAreRedacted() throws {
        let json = #"{"mcpServers": {"gh": {"command": "npx", "args": ["server", "--token", "ghp_secret"]}, "web": {"url": "https://u:p@x.example/sse?key=k"}}}"#
        let servers = AbilityParsing.claudeMCPs(Data(json.utf8), project: nil)
        #expect(servers.first { $0.key == "gh" }?.summary == "npx server --token \(mask)")
        #expect(servers.first { $0.key == "web" }?.summary == "https://\(mask)@x.example/sse?key=\(mask)")
        #expect(!servers.contains { ($0.summary ?? "").contains("secret") })
    }
}
