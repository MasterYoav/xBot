import Foundation

/// TypeSafe AI's Jev, the "System One" model: given a state and typed questions, it answers each
/// with calibrated probabilities in well under a second, and never writes text. xBot asks it to
/// gate, route and score between agent steps, and to pick the cheapest capable agent for a task.
/// See docs/superpowers/specs/2026-10-12-jev-workflows-design.md.
public struct JevClient: Sendable {
    /// Sends one request. Injected, so tests answer per client and never share a class-level
    /// URLProtocol stub across parallel suites.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    public static let defaultModel = "jev-latest"

    let key: String
    let model: String
    let timeout: Duration
    let transport: Transport

    /// `key` is used only in the Authorization header; it is never logged, echoed or put in an error.
    public init(key: String, model: String = JevClient.defaultModel, timeout: Duration = .seconds(10),
                transport: @escaping Transport = JevClient.urlSession) {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.isEmpty ? Self.defaultModel : model
        self.timeout = timeout
        self.transport = transport
    }

    /// The real network, through an ephemeral session: nothing about the call is cached on disk.
    public static let urlSession: Transport = { request in
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JevError.unreadable }
        return (data, http)
    }

    private static let session = URLSession(configuration: .ephemeral)

    /// One call with any number of questions. Throws a `JevError`, never anything else.
    public func ask(state: String, questions: [String: JevQuestion]) async throws(JevError) -> JevResponse {
        guard !key.isEmpty else { throw .noKey }
        let request = makeRequest(state: state, questions: questions)
        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw .badKey
        case 422: throw .invalid(Self.detail(in: data))
        case 429: throw .rateLimited
        case 529, 503: throw .overloaded
        default: throw .http(response.statusCode)
        }
        guard let parsed = JevResponse(data: data) else { throw .unreadable }
        return parsed
    }

    func makeRequest(state: String, questions: [String: JevQuestion]) -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Double(timeout.components.seconds) + 1
        let body: [String: Any] = [
            "model": model, "state": state,
            "questions": questions.mapValues(\.json),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// The transport, raced against the timeout: a server that never answers can't hold a
    /// workflow (or Settings' Check) forever.
    private func send(_ request: URLRequest) async throws(JevError) -> (Data, HTTPURLResponse) {
        let transport = self.transport
        let timeout = self.timeout
        do {
            return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
                group.addTask { try await transport(request) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw JevError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw JevError.timedOut }
                return first
            }
        } catch let error as JevError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw .offline
            default: throw .offline
            }
        } catch {
            throw .offline
        }
    }

    /// What a 422 says was wrong, trimmed to a line. Jev's validation messages are about the
    /// request's shape; they never contain the key.
    static func detail(in data: Data) -> String {
        let object = try? JSONSerialization.jsonObject(with: data)
        var text: String?
        if let dict = object as? [String: Any] {
            if let detail = dict["detail"] as? String { text = detail }
            else if let message = dict["message"] as? String { text = message }
            else if let error = dict["error"] as? String { text = error }
            else if let list = dict["detail"] as? [[String: Any]] { text = list.compactMap { $0["msg"] as? String }.first }
        }
        let line = (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.prefix(200))
    }
}

/// One question to Jev. Its name is the key it's asked under.
public struct JevQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public var key: String
        public var description: String
        public init(key: String, description: String) { self.key = key; self.description = description }
    }

    public enum Kind: Equatable, Sendable {
        /// Yes or no; the answer is P(yes). Criteria, optional, say what each means.
        case noul(yes: String?, no: String?)
        case choice([Option])
        /// 2–10 ordered levels, lowest first.
        case score([String])
    }

    public var instructions: String
    public var kind: Kind

    public init(instructions: String, kind: Kind) {
        self.instructions = instructions
        self.kind = kind
    }

    public static func noul(_ instructions: String, yes: String? = nil, no: String? = nil) -> JevQuestion {
        JevQuestion(instructions: instructions, kind: .noul(yes: yes, no: no))
    }

    public static func choice(_ instructions: String, options: [Option]) -> JevQuestion {
        JevQuestion(instructions: instructions, kind: .choice(options))
    }

    public static func score(_ instructions: String, levels: [String]) -> JevQuestion {
        JevQuestion(instructions: instructions, kind: .score(levels))
    }

    var json: [String: Any] {
        var out: [String: Any] = ["instructions": instructions]
        switch kind {
        case .noul(let yes, let no):
            out["type"] = "noul"
            if yes != nil || no != nil {
                var criteria: [String: String] = [:]
                if let yes { criteria["true"] = yes }
                if let no { criteria["false"] = no }
                out["criteria"] = criteria
            }
        case .choice(let options):
            out["type"] = "choice"
            out["criteria"] = Dictionary(options.map { ($0.key, $0.description) }) { first, _ in first }
        case .score(let levels):
            out["type"] = "score"
            out["criteria"] = levels
        }
        return out
    }
}

public enum JevAnswer: Equatable, Sendable {
    /// P(yes).
    case noul(Double)
    case choice(String, probabilities: [String: Double], confidence: Double)
    /// `score` can land between levels (2.38: between the third and the fourth). `legend` maps
    /// each level's index, as a string, to its text.
    case score(Double, legend: [String: String], probabilities: [String: Double], confidence: Double)

    public var choice: String? { if case .choice(let key, _, _) = self { key } else { nil } }

    init?(json: [String: Any]) {
        func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        func numbers(_ value: Any?) -> [String: Double] {
            (value as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
        switch json["type"] as? String {
        case "noul":
            guard let p = number(json["noul"]) else { return nil }
            self = .noul(p)
        case "choice":
            guard let key = json["choice"] as? String else { return nil }
            self = .choice(key, probabilities: numbers(json["probabilities"]), confidence: number(json["confidence"]) ?? 0)
        case "score":
            guard let score = number(json["score"]) else { return nil }
            let legend = (json["legend"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            self = .score(score, legend: legend, probabilities: numbers(json["probabilities"]),
                          confidence: number(json["confidence"]) ?? 0)
        default:
            return nil
        }
    }
}

public struct JevResponse: Equatable, Sendable {
    /// The version that answered ("jev-1.13.0").
    public var model: String
    public var answers: [String: JevAnswer]
    public var inputTokens: Int
    public var outputTokens: Int

    public init(model: String, answers: [String: JevAnswer], inputTokens: Int = 0, outputTokens: Int = 0) {
        self.model = model
        self.answers = answers
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    /// An answer of a type this xBot doesn't know is skipped, not fatal.
    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = object["answers"] as? [String: Any] else { return nil }
        let usage = object["usage"] as? [String: Any]
        self.init(
            model: object["model"] as? String ?? "",
            answers: answers.compactMapValues { ($0 as? [String: Any]).flatMap(JevAnswer.init(json:)) },
            inputTokens: (usage?["input_tokens"] as? NSNumber)?.intValue ?? 0,
            outputTokens: (usage?["output_tokens"] as? NSNumber)?.intValue ?? 0
        )
    }
}

/// Why Jev didn't answer, each one a sentence for the person. None ever includes the key.
public enum JevError: Error, Equatable, Sendable {
    case noKey
    case badKey
    /// 422: the question wasn't valid; Jev's own words.
    case invalid(String)
    case rateLimited
    case overloaded
    case http(Int)
    case offline
    case timedOut
    case unreadable

    public var sentence: String {
        switch self {
        case .noKey: String(localized: "There's no Jev key yet. Add one in Settings › AI.")
        case .badKey: String(localized: "Jev didn't accept the key. Check it at console.typesafe.ai.")
        case .invalid(let detail):
            detail.isEmpty
                ? String(localized: "Jev couldn't read the question.")
                : String(localized: "Jev couldn't read the question: \(detail.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))." )
        case .rateLimited: String(localized: "Jev is rate limiting this key. Try again in a minute.")
        case .overloaded: String(localized: "Jev is overloaded right now. Try again shortly.")
        case .http(let status): String(localized: "Jev answered with an error (HTTP \(status)).")
        case .offline: String(localized: "Jev can't be reached. Check this Mac's internet connection.")
        case .timedOut: String(localized: "Jev didn't answer in time.")
        case .unreadable: String(localized: "Jev's answer couldn't be read.")
        }
    }
}
