import Foundation

/// A GitHub repository, from a remote's URL: https, scp-style ssh, or ssh://.
public struct GitHubRemote: Equatable, Sendable {
    public var owner: String
    public var name: String

    public var slug: String { "\(owner)/\(name)" }
    public var webURL: URL { URL(string: "https://github.com/\(owner)/\(name)")! }

    public static func parse(_ remote: String) -> GitHubRemote? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "github.com:") ?? trimmed.range(of: "github.com/") else { return nil }
        let parts = trimmed[range.upperBound...].split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let name = parts[1].hasSuffix(".git") ? parts[1].dropLast(4) : parts[1]
        return GitHubRemote(owner: String(parts[0]), name: String(name))
    }
}

/// The branch's pull request, as `gh pr view --json` reports it.
public struct PullRequest: Equatable, Sendable {
    public enum State: Sendable { case open, draft, merged, closed }
    public enum Review: Sendable { case required, approved, changesRequested }
    public enum Checks: Sendable { case passing, failing, running }

    public var number: Int
    public var state: State
    public var review: Review?
    public var checks: Checks?
    public var url: URL?

    public static let fields = "number,state,isDraft,reviewDecision,url,statusCheckRollup"

    public static func parse(json: String) -> PullRequest? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let number = object["number"] as? Int else { return nil }
        let state: State = switch object["state"] as? String {
        case "MERGED": .merged
        case "CLOSED": .closed
        default: object["isDraft"] as? Bool == true ? .draft : .open
        }
        let review: Review? = switch object["reviewDecision"] as? String {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .required
        default: nil
        }
        let outcomes: [Checks] = (object["statusCheckRollup"] as? [[String: Any]] ?? []).map { check in
            // A commit status has a state; a check run has a status and, once completed, a conclusion.
            if let state = check["state"] as? String {
                return switch state {
                case "SUCCESS": .passing
                case "PENDING", "EXPECTED": .running
                default: .failing
                }
            }
            guard check["status"] as? String == "COMPLETED" else { return .running }
            return switch check["conclusion"] as? String {
            case "SUCCESS", "NEUTRAL", "SKIPPED": .passing
            default: .failing
            }
        }
        let checks: Checks? = outcomes.isEmpty ? nil
            : outcomes.contains(.failing) ? .failing
            : outcomes.contains(.running) ? .running : .passing
        return PullRequest(number: number, state: state, review: review, checks: checks,
                           url: (object["url"] as? String).flatMap(URL.init(string:)))
    }
}
