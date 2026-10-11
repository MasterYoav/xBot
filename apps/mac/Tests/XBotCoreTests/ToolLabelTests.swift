import Foundation
import Testing
@testable import XBotCore

@Suite struct ToolLabelTests {
    /// Connector (MCP) tools arrive as `mcp__<server>__<tool>` from Claude Code and, via xBot's
    /// parser, from Codex. They read as the connector, not the raw name.
    @Test func connectorToolsReadAsTheConnector() {
        #expect(ToolLabel.verb("mcp__node_repl__js", running: false) == "Used node_repl: js")
        #expect(ToolLabel.verb("mcp__claude_ai_Gmail__search_threads", running: true) == "Using claude_ai_Gmail: search_threads")
        #expect(ToolLabel.symbol("mcp__node_repl__js") == "point.3.connected.trianglepath.dotted")
        #expect(ToolLabel.verb("Read", running: false) == "Read")
        #expect(ToolLabel.verb("mcp__odd", running: false) == "Used odd")
    }
}

@Suite struct ToolSummaryConnectorTests {
    func tool(_ name: String) -> ToolPart { ToolPart(id: UUID().uuidString, name: name, summary: "", output: "", isError: false) }

    @Test func aStepsConnectorCallsAreNamedInItsSummary() {
        #expect(ToolLabel.summary(of: [tool("mcp__node_repl__js"), tool("mcp__node_repl__js")]) == "Used node_repl twice")
        #expect(ToolLabel.summary(of: [tool("Bash"), tool("mcp__claude_ai_Gmail__search")]) == "Ran a command, used claude_ai_Gmail once")
        #expect(ToolLabel.summary(of: [tool("mcp__a__x"), tool("mcp__b__y"), tool("mcp__a__z")]) == "Used a twice, used b once")
    }
}

@Suite struct PageTabsTests {
    /// Abilities, Notes, Automations and Agents are pages of their own: no chat tabs above them.
    @Test func tabsShowOnlyOnChatPages() {
        for page: Page in [.abilities, .notes, .automations, .agents] { #expect(!page.showsTabs, "\(page)") }
        #expect(Page.main.showsTabs && Page.profile.showsTabs)
    }
}
