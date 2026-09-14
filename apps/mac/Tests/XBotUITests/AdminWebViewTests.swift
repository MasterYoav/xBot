import Foundation
import Testing
@testable import XBotUI

/// How the admin webview authenticates to the engine.
@Suite
struct AdminWebViewTests {
    private let admin = URL(string: "http://127.0.0.1:49390/admin/plugins?tab=connectors")!

    /// The first request is the engine's exchange, carrying the token once, asking to land on the page.
    @Test func theFirstRequestExchangesTheTokenForASession() throws {
        let request = try #require(AdminWebView.sessionRequest(for: admin, bearerToken: "tok"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let url = try #require(request.url)
        #expect(url.host() == "127.0.0.1")
        #expect(url.port == 49390)
        #expect(url.path() == AdminWebView.sessionPath)
        let to = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "to" }?.value
        #expect(to == "/admin/plugins?tab=connectors")
    }

    /// The token goes in a header, never in the URL, where it would reach history and logs.
    @Test func theTokenIsNeverInTheURL() throws {
        let request = try #require(AdminWebView.sessionRequest(for: admin, bearerToken: "secret-token"))
        #expect(!(request.url?.absoluteString.contains("secret-token") ?? true))
    }
}
