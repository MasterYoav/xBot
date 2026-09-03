import SwiftUI
import WebKit

/// Loads an engine admin page with bearer auth injected before the SPA boots.
///
/// Loopback is not a boundary on a shared Mac. The token is patched into fetch and XHR at document
/// start so upstream's React admin can call `/api` without the user signing in.
struct AdminWebView: NSViewRepresentable {
    let url: URL
    let bearerToken: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(bearerScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    private var bearerScript: WKUserScript {
        let escaped = bearerToken
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let source = """
        (function() {
          var token = '\(escaped)';
          var fetch = window.fetch;
          window.fetch = function(input, init) {
            init = init || {};
            var headers = new Headers(init.headers || {});
            if (!headers.has('Authorization')) {
              headers.set('Authorization', 'Bearer ' + token);
            }
            init.headers = headers;
            init.credentials = 'include';
            return fetch.call(this, input, init);
          };
          var open = XMLHttpRequest.prototype.open;
          var send = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function() {
            this._xbotNeedsAuth = true;
            return open.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function() {
            if (this._xbotNeedsAuth) {
              try { this.setRequestHeader('Authorization', 'Bearer ' + token); } catch (e) {}
            }
            return send.apply(this, arguments);
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
