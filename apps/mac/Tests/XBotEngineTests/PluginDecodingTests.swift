import Foundation
import Testing
@testable import XBotEngine

@Suite struct PluginDecodingTests {
    @Test func decodesPluginsPage() throws {
        let json = """
        {
          "catalogue": [{
            "key": "google-drive",
            "title": "Google Drive",
            "vendor": "Google",
            "summary": "Files.",
            "docsUrl": "https://example.com",
            "auth": "user-oauth",
            "perInstance": false
          }],
          "servers": [{
            "id": "google-drive",
            "title": "Google Drive",
            "vendor": "Google",
            "url": "https://example.com/mcp",
            "summary": "Files.",
            "docsUrl": "https://example.com",
            "provenance": "first-party",
            "hasCredential": true,
            "toolsRefreshedAt": null,
            "lastError": null,
            "addedBy": null,
            "dynamicClient": true,
            "tools": [{
              "serverId": "google-drive",
              "name": "search_files",
              "description": "Search Drive.",
              "inputSchema": {},
              "ref": "google-drive/search_files",
              "effect": "read",
              "grantedTo": ["agent-1"]
            }],
            "withdrawn": []
          }],
          "skills": [],
          "botsMayCallBack": true,
          "redirectUri": "http://127.0.0.1:3001/api/plugins/oauth/callback"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let page = try #require(PluginDecoding.pluginsPage(from: data))

        #expect(page.catalogue.count == 1)
        #expect(page.catalogue[0].auth == .userOAuth)
        #expect(page.servers[0].tools[0].ref == "google-drive/search_files")
        #expect(page.botsMayCallBack)
    }

    @Test func decodesGrantedPlugins() throws {
        let json = """
        {
          "tools": [{
            "ref": "google-drive/search_files",
            "toolName": "search_files",
            "description": "Search Drive.",
            "inputSchema": {}
          }],
          "skills": [{
            "slug": "inbox-triage",
            "title": "Inbox triage",
            "summary": "Sort mail.",
            "instructions": "Be concise."
          }]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let granted = try #require(PluginDecoding.grantedPlugins(from: data))

        #expect(granted.tools.count == 1)
        #expect(granted.skills[0].slug == "inbox-triage")
    }
}
