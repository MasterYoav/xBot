import SwiftUI
import WebKit

/// Loads an engine admin page, authenticated the way a browser can be.
///
/// The engine checks its bearer token on every path, and a webview cannot put a header on the
/// `<script>` and `<link>` loads that follow its first request — so the page answered
/// "Unauthorized." and never drew. The first request is a POST to the engine's session exchange,
/// carrying the token once; the engine answers with an HttpOnly, SameSite=Strict cookie scoped to its
/// own origin and redirects to the page. Everything after that authenticates by cookie, the way any
/// browser does.
///
/// It replaced a script that patched `fetch` and XHR to add the raw token to every request — in every
/// frame, on every page the webview ever loaded. A connector's OAuth sign-in opens a third-party page
/// in this same webview, and that page's own scripts would have sent the engine token to that third
/// party. A cookie is never sent anywhere but where it came from, and no page script can read it.
struct AdminWebView: NSViewRepresentable {
    let url: URL
    let bearerToken: String

    /// The engine's exchange path, from `engine/server/src/xbot/bearer-auth.ts`.
    nonisolated static let sessionPath = "/xbot/admin-session"

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Non-persistent: the session cookie lives as long as this window and is never written to
        // disk, so closing Plugins ends the session.
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        if let request = Self.sessionRequest(for: url, bearerToken: bearerToken) {
            webView.load(request)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url?.absoluteString != url.absoluteString,
              let request = Self.sessionRequest(for: url, bearerToken: bearerToken)
        else { return }
        webView.load(request)
    }

    /// POST to the engine's exchange with the token, asking to land on `url`'s path.
    ///
    /// Only the path and query go in `to`; the engine refuses anything that would leave its origin.
    /// Nonisolated because it touches nothing but its arguments — the view type is main-actor bound,
    /// and without this a caller off the main actor traps on Swift 6's runtime isolation check.
    nonisolated static func sessionRequest(for url: URL, bearerToken: String) -> URLRequest? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        let destination = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        components.percentEncodedPath = sessionPath
        components.queryItems = [URLQueryItem(name: "to", value: destination)]
        components.fragment = nil
        guard let exchange = components.url else { return nil }

        var request = URLRequest(url: exchange)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
