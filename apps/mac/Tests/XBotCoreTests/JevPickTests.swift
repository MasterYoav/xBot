import Foundation
import Testing
import XBotBrain
@testable import XBotCore

/// "Jev picks": one call, a choice over the installed CLIs and models (each described with its
/// strength and relative cost) and a score for effort.
@Suite struct JevPickTests {
    let models: [HarnessKind: [ModelOption]] = [
        .claude: [ModelOption(id: "opus", name: "Opus", efforts: Effort.allCases),
                  ModelOption(id: "haiku", name: "Haiku", efforts: Effort.allCases)],
        .codex: [ModelOption(id: "gpt-5-mini", name: "gpt-5-mini", efforts: [.low, .medium, .high])],
    ]

    var options: [BrainOption] { JevPick.options(installed: [.claude, .codex, .copilot], models: { models[$0] ?? [] }) }

    @Test func everyInstalledCLIAndModelIsAnOption() {
        #expect(options.map(\.name) == ["Claude Code · Opus", "Claude Code · Haiku", "Codex · gpt-5-mini", "GitHub Copilot"])
        #expect(Set(options.map(\.key)).count == options.count)
        #expect(options.last?.choice == BrainChoice(harness: .copilot))
    }

    @Test func eachOptionSaysItsStrengthAndRelativeCost() {
        let opus = options.first { $0.name == "Claude Code · Opus" }
        #expect(opus?.description == "Claude Code · Opus — strongest, most expensive")
        let mini = options.first { $0.name == "Codex · gpt-5-mini" }
        #expect(mini?.description == "Codex · gpt-5-mini — quick edits, cheapest")
        for option in options { #expect(option.description.contains("—")) }
    }

    @Test func oneCallAsksForABrainAndAnEffort() {
        let questions = JevPick.questions(for: options)
        guard case .choice(let choices) = questions["brain"]?.kind else { Issue.record("no brain choice"); return }
        #expect(choices.count == options.count)
        #expect(questions["effort"] == .score(questions["effort"]!.instructions, levels: ["Low", "Medium", "High", "Max"]))
    }

    @Test func theAnswerBecomesAChoiceAtAnEffort() throws {
        let mini = try #require(options.first { $0.name == "Codex · gpt-5-mini" })
        let response = JevResponse(model: "jev", answers: [
            "brain": .choice(mini.key, probabilities: [:], confidence: 0.82),
            "effort": .score(0.2, legend: [:], probabilities: [:], confidence: 0.7),
        ])
        let pick = try #require(JevPick.decide(response, options: options))
        #expect(pick.choice == BrainChoice(harness: .codex, model: "gpt-5-mini", effort: .low))
        #expect(pick.sentence == "Jev chose Codex · gpt-5-mini, low effort (0.82)")
    }

    @Test func anEffortTheModelCantDoComesDownToOneItCan() throws {
        let mini = try #require(options.first { $0.name == "Codex · gpt-5-mini" })
        let response = JevResponse(model: "jev", answers: [
            "brain": .choice(mini.key, probabilities: [:], confidence: 0.9),
            "effort": .score(3, legend: [:], probabilities: [:], confidence: 0.9),
        ])
        #expect(JevPick.decide(response, options: options)?.choice.effort == .high)
    }

    @Test func anUnknownChoiceIsNoPick() {
        let response = JevResponse(model: "jev", answers: ["brain": .choice("nope", probabilities: [:], confidence: 1)])
        #expect(JevPick.decide(response, options: options) == nil)
    }

    @Test func aMissingEffortLeavesTheAgentsDefault() throws {
        let response = JevResponse(model: "jev", answers: ["brain": .choice(options[0].key, probabilities: [:], confidence: 0.6)])
        let pick = try #require(JevPick.decide(response, options: options))
        #expect(pick.choice.effort == nil)
        #expect(pick.sentence == "Jev chose Claude Code · Opus (0.60)")
    }
}
