import Foundation
import Testing
@testable import XBotEngine

/// The agent's computer as client tools. See `docs/plans/computer-client-tools.md`.
@Suite
struct ComputerToolsTests {
    /// The set upstream's client registers. A tool missing here is one no xBot agent is offered.
    @Test func everyUpstreamToolIsOffered() {
        #expect(ComputerTools.names == [
            "computer_navigate", "computer_read", "computer_snapshot", "computer_type",
            "computer_click", "computer_key", "computer_request_secret", "report_refusal",
            "computer_request_help", "computer_list_files", "computer_read_file",
            "computer_run_command", "computer_write_file", "computer_scroll",
        ])
    }

    @Test func everyDefinitionIsValidJSONSchema() throws {
        for tool in ComputerTools.wireTools {
            let parameters = try #require(tool["parameters"] as? [String: Any])
            #expect(parameters["type"] as? String == "object", "\(tool["name"] ?? "")")
            #expect(!(tool["description"] as? String ?? "").isEmpty)
        }
    }

    @Test func callsRouteToTheComputerAPI() {
        #expect(ComputerTools.route(name: "computer_navigate", argumentsJSON: #"{"url":"https://example.com"}"#)
            == .computer(path: "/navigate", body: #"{"url":"https:\/\/example.com"}"#))
        #expect(ComputerTools.route(name: "computer_read", argumentsJSON: "{}") == .computer(path: "/read", body: nil))
        #expect(ComputerTools.route(name: "computer_run_command", argumentsJSON: #"{"command":"ls"}"#)
            == .computer(path: "/exec", body: #"{"command":"ls"}"#))
        #expect(ComputerTools.route(name: "report_refusal", argumentsJSON: #"{"reason":"no"}"#)
            == .declined(body: #"{"reason":"no"}"#))
        #expect(ComputerTools.route(name: "not_a_tool", argumentsJSON: "{}") == nil)
    }

    /// The two that wait on a person, and what they wait for.
    @Test func requestsWaitForThePerson() {
        guard case .waitForPerson(let path, _, let until) = ComputerTools.route(
            name: "computer_request_secret", argumentsJSON: #"{"label":"the code","ref":"e1","snapshotId":3}"#
        ) else {
            Issue.record("expected a wait")
            return
        }
        #expect(path == "/control/secret")
        #expect(until == .secretEntered(label: "the code"))
        #expect(ComputerTools.route(name: "computer_request_help", argumentsJSON: #"{"reason":"sign in"}"#)
            == .waitForPerson(path: "/control/request", body: #"{"reason":"sign in"}"#, until: .controlReturned))
    }

    /// Upstream's distinctions, which decide the model's next step.
    @Test func outcomesMirrorUpstream() {
        let ok = ComputerTools.outcome(status: 200, body: Data(#"{"title":"Example Domain"}"#.utf8))
        #expect(ok["ok"] as? Bool == true)
        #expect(ok["title"] as? String == "Example Domain")

        let refused = ComputerTools.outcome(status: 403, body: Data(#"{"error":"Not allowed here.","rule":"payments"}"#.utf8))
        #expect(refused["ok"] as? Bool == false)
        #expect(refused["refused"] as? Bool == true)
        #expect(refused["rule"] as? String == "payments")
        #expect(refused["reason"] as? String == "Not allowed here.")

        let person = ComputerTools.outcome(status: 409, body: Data(#"{"error":"x","humanHasControl":true}"#.utf8))
        #expect(person["humanHasControl"] as? Bool == true)
        #expect(person["staleRefs"] == nil)

        let stale = ComputerTools.outcome(status: 409, body: Data(#"{"error":"x"}"#.utf8))
        #expect(stale["staleRefs"] as? Bool == true)

        let broken = ComputerTools.outcome(status: 500, body: nil)
        #expect(broken["reason"] as? String == "That did not work.")
    }

    @Test func navigateHandsTheModelThePageNotTheWholeBody() {
        let narrowed = ComputerTools.navigateOutcome([
            "ok": true, "title": "T", "url": "u", "text": "body", "truncated": false, "frame": "base64…",
        ])
        #expect(Set(narrowed.keys) == ["ok", "title", "url", "text", "truncated"])
    }
}
