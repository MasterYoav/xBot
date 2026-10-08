import Foundation
import Testing
@testable import XBotCore

@Suite struct PullRequestTests {
    @Test func remotes() {
        #expect(GitHubRemote.parse("https://github.com/MasterYoav/xBot.git") == GitHubRemote(owner: "MasterYoav", name: "xBot"))
        #expect(GitHubRemote.parse("git@github.com:MasterYoav/xBot.git\n") == GitHubRemote(owner: "MasterYoav", name: "xBot"))
        #expect(GitHubRemote.parse("ssh://git@github.com/o/r") == GitHubRemote(owner: "o", name: "r"))
        #expect(GitHubRemote.parse("https://gitlab.com/o/r.git") == nil)
    }

    @Test func openPullRequestWithFailingCheck() {
        let json = #"{"number":15,"state":"OPEN","isDraft":false,"reviewDecision":"APPROVED","url":"https://github.com/o/r/pull/15","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]}"#
        let pr = PullRequest.parse(json: json)
        #expect(pr?.number == 15 && pr?.state == .open && pr?.review == .approved && pr?.checks == .failing)
        #expect(pr?.url?.absoluteString == "https://github.com/o/r/pull/15")
    }

    @Test func runningChecksAndStatusContexts() {
        let json = #"{"number":2,"state":"OPEN","isDraft":true,"reviewDecision":"","url":"https://x","statusCheckRollup":[{"__typename":"StatusContext","state":"PENDING"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]}"#
        let pr = PullRequest.parse(json: json)
        #expect(pr?.state == .draft && pr?.review == nil && pr?.checks == .running)
    }

    @Test func noChecksIsNoChecks() {
        let pr = PullRequest.parse(json: #"{"number":3,"state":"MERGED","isDraft":false,"reviewDecision":"REVIEW_REQUIRED","url":"https://x","statusCheckRollup":[]}"#)
        #expect(pr?.state == .merged && pr?.review == .required && pr?.checks == nil)
    }
}
