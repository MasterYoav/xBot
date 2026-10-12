import Foundation
import Synchronization
import Testing
@testable import XBotBrain

/// Records the requests it is given and answers each with a canned status and body. Injected per
/// client: never a class-level URLProtocol stub, which parallel suites would share (CLAUDE.md).
final class CannedTransport: Sendable {
    let requests = Mutex<[URLRequest]>([])
    private let status: Int
    private let body: Data

    init(status: Int = 200, body: Data) {
        self.status = status
        self.body = body
    }

    convenience init(status: Int = 200, json: String) { self.init(status: status, body: Data(json.utf8)) }

    var transport: JevClient.Transport {
        { [self] request in
            requests.withLock { $0.append(request) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (body, response)
        }
    }

    func sentBody() throws -> [String: Any] {
        let request = try #require(requests.withLock { $0.first })
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

func jevFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct JevClientTests {
    let key = "tsk-test-0123456789"

    // MARK: Requests

    @Test func postsToSystemOneWithTheKeyAsABearerToken() async throws {
        let canned = CannedTransport(json: #"{"model":"jev-1.13.0","answers":{"ok":{"type":"noul","noul":0.9}}}"#)
        let client = JevClient(key: key, transport: canned.transport)
        _ = try await client.ask(state: "s", questions: ["ok": .noul("Is it?")])
        let request = try #require(canned.requests.withLock { $0.first })
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func aNoulQuestionsBodyCarriesItsCriteriaWhenGiven() async throws {
        let canned = CannedTransport(json: #"{"model":"m","answers":{}}"#)
        let client = JevClient(key: key, model: "jev-1.13.0", transport: canned.transport)
        _ = try await client.ask(state: "The build log", questions: [
            "failing": .noul("Is the build failing?", yes: "It failed", no: "It passed"),
            "plain": .noul("Plain?"),
        ])
        let body = try canned.sentBody()
        #expect(body["model"] as? String == "jev-1.13.0")
        #expect(body["state"] as? String == "The build log")
        let questions = try #require(body["questions"] as? [String: [String: Any]])
        #expect(questions["failing"]?["type"] as? String == "noul")
        #expect(questions["failing"]?["instructions"] as? String == "Is the build failing?")
        #expect(questions["failing"]?["criteria"] as? [String: String] == ["true": "It failed", "false": "It passed"])
        #expect(questions["plain"]?["criteria"] == nil)
    }

    @Test func aChoiceSendsItsOptionsAsKeyedDescriptions() async throws {
        let canned = CannedTransport(json: #"{"model":"m","answers":{}}"#)
        _ = try await JevClient(key: key, transport: canned.transport).ask(state: "s", questions: [
            "route": .choice("Which?", options: [.init(key: "fix", description: "Fix it"), .init(key: "ship", description: "Ship it")]),
        ])
        let questions = try #require(try canned.sentBody()["questions"] as? [String: [String: Any]])
        #expect(questions["route"]?["type"] as? String == "choice")
        #expect(questions["route"]?["criteria"] as? [String: String] == ["fix": "Fix it", "ship": "Ship it"])
    }

    @Test func aScoreSendsItsLevelsLowestFirst() async throws {
        let canned = CannedTransport(json: #"{"model":"m","answers":{}}"#)
        _ = try await JevClient(key: key, transport: canned.transport).ask(state: "s", questions: [
            "effort": .score("How hard?", levels: ["Low", "Medium", "High", "Max"]),
        ])
        let questions = try #require(try canned.sentBody()["questions"] as? [String: [String: Any]])
        #expect(questions["effort"]?["type"] as? String == "score")
        #expect(questions["effort"]?["criteria"] as? [String] == ["Low", "Medium", "High", "Max"])
    }

    @Test func theDefaultModelIsJevLatest() async throws {
        let canned = CannedTransport(json: #"{"model":"m","answers":{}}"#)
        _ = try await JevClient(key: key, transport: canned.transport).ask(state: "s", questions: ["q": .noul("?")])
        #expect(try canned.sentBody()["model"] as? String == "jev-latest")
        #expect(JevClient.defaultModel == "jev-latest")
    }

    // MARK: Answers

    @Test func parsesARealChoiceResponse() async throws {
        let canned = CannedTransport(body: try jevFixture("jev-choice-response"))
        let response = try await JevClient(key: key, transport: canned.transport).ask(state: "s", questions: ["q": .noul("?")])
        #expect(response.model == "jev-1.13.0")
        #expect(response.inputTokens == 724)
        #expect(response.outputTokens == 90)
        guard case .choice(let choice, let probabilities, let confidence) = response.answers["release_trigger"] else {
            Issue.record("not a choice"); return
        }
        #expect(choice == "version_bump")
        #expect(probabilities["version_bump"] == 0.97)
        #expect(confidence == 0.95)
        #expect(response.answers["workflow_shape"]?.choice == "decide_steps")
    }

    @Test func parsesNoulAndScoreAnswers() async throws {
        let json = #"""
        {"model":"jev-1.13.0","answers":{
          "gate":{"type":"noul","noul":0.96},
          "effort":{"type":"score","score":2.38,"legend":{"0":"Low","1":"Medium","2":"High","3":"Max"},
                    "probabilities":{"0":0,"1":0.1,"2":0.42,"3":0.48},"confidence":0.58}}}
        """#
        let response = try await JevClient(key: key, transport: CannedTransport(json: json).transport)
            .ask(state: "s", questions: ["q": .noul("?")])
        #expect(response.answers["gate"] == .noul(0.96))
        guard case .score(let score, let legend, _, let confidence) = response.answers["effort"] else {
            Issue.record("not a score"); return
        }
        #expect(score == 2.38)
        #expect(legend["2"] == "High")
        #expect(confidence == 0.58)
    }

    @Test func anAnswerOfAnUnknownTypeIsSkippedNotFatal() async throws {
        let json = #"{"model":"m","answers":{"a":{"type":"noul","noul":0.2},"b":{"type":"dream","x":1}}}"#
        let response = try await JevClient(key: key, transport: CannedTransport(json: json).transport)
            .ask(state: "s", questions: ["q": .noul("?")])
        #expect(response.answers["a"] == .noul(0.2))
        #expect(response.answers["b"] == nil)
    }

    // MARK: Errors, as sentences

    @Test(arguments: [(401, JevError.badKey), (422, .invalid("state is required")), (429, .rateLimited),
                      (529, .overloaded), (500, .http(500))])
    func statusesBecomeErrors(status: Int, expected: JevError) async throws {
        let canned = CannedTransport(status: status, json: #"{"detail":"state is required"}"#)
        await #expect(throws: expected) {
            try await JevClient(key: key, transport: canned.transport).ask(state: "s", questions: ["q": .noul("?")])
        }
    }

    @Test func everyErrorIsASentenceWithoutTheKey() {
        let all: [JevError] = [.noKey, .badKey, .invalid("x"), .rateLimited, .overloaded, .http(500), .offline, .timedOut, .unreadable]
        for error in all {
            #expect(error.sentence.hasSuffix("."))
            #expect(!error.sentence.contains(key))
        }
        #expect(JevError.badKey.sentence.contains("key"))
        #expect(JevError.rateLimited.sentence.localizedCaseInsensitiveContains("rate"))
    }

    @Test func anUnreadableBodyIsAnError() async throws {
        await #expect(throws: JevError.unreadable) {
            try await JevClient(key: key, transport: CannedTransport(json: "<html>").transport)
                .ask(state: "s", questions: ["q": .noul("?")])
        }
    }

    @Test func noNetworkIsOffline() async throws {
        let failing: JevClient.Transport = { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: JevError.offline) {
            try await JevClient(key: key, transport: failing).ask(state: "s", questions: ["q": .noul("?")])
        }
    }

    @Test func aTransportThatNeverAnswersTimesOut() async throws {
        let hanging: JevClient.Transport = { _ in
            try await Task.sleep(for: .seconds(60))
            throw URLError(.cancelled)
        }
        let started = ContinuousClock.now
        await #expect(throws: JevError.timedOut) {
            try await JevClient(key: key, timeout: .milliseconds(200), transport: hanging)
                .ask(state: "s", questions: ["q": .noul("?")])
        }
        #expect(ContinuousClock.now - started < .seconds(30))
    }

    @Test func aURLSessionTimeoutIsATimeoutToo() async throws {
        let failing: JevClient.Transport = { _ in throw URLError(.timedOut) }
        await #expect(throws: JevError.timedOut) {
            try await JevClient(key: key, transport: failing).ask(state: "s", questions: ["q": .noul("?")])
        }
    }

    @Test func anEmptyKeyIsRefusedBeforeAnythingIsSent() async throws {
        let canned = CannedTransport(json: "{}")
        await #expect(throws: JevError.noKey) {
            try await JevClient(key: "  ", transport: canned.transport).ask(state: "s", questions: ["q": .noul("?")])
        }
        #expect(canned.requests.withLock { $0.isEmpty })
    }
}
