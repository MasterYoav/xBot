import Foundation
import Testing
@testable import XBotBrain

@Suite struct EffortTests {
    func request(_ effort: Effort?, model: String? = nil) -> TurnRequest {
        TurnRequest(prompt: "x", directory: URL(filePath: "/tmp"), model: model, mode: .editFiles, effort: effort)
    }

    func pair(_ arguments: [String], _ flag: String) -> String? {
        arguments.firstIndex(of: flag).map { arguments[$0 + 1] }
    }

    @Test func claudeGetsItsEffortFlag() {
        #expect(pair(HarnessKind.claude.arguments(for: request(.low)), "--effort") == "low")
        #expect(pair(HarnessKind.claude.arguments(for: request(.extra)), "--effort") == "xhigh")
        #expect(pair(HarnessKind.claude.arguments(for: request(.max)), "--effort") == "max")
        #expect(!HarnessKind.claude.arguments(for: request(nil)).contains("--effort"))
    }

    /// Galaxy is the most Claude Code can do: max effort on its strongest model, whatever was picked.
    @Test func claudesGalaxyIsMaxOnOpus() {
        let arguments = HarnessKind.claude.arguments(for: request(.galaxy, model: "haiku"))
        #expect(pair(arguments, "--effort") == "max")
        #expect(pair(arguments, "--model") == "opus")
        #expect(arguments.filter { $0 == "--model" }.count == 1)
    }

    @Test func codexGetsItsReasoningSetting() {
        #expect(HarnessKind.codex.arguments(for: request(.extra)).contains(#"model_reasoning_effort="xhigh""#))
        #expect(HarnessKind.codex.arguments(for: request(.galaxy)).contains(#"model_reasoning_effort="ultra""#))
        #expect(!HarnessKind.codex.arguments(for: request(nil)).contains { $0.hasPrefix("model_reasoning_effort") })
    }

    @Test func codexModelsComeFromItsCacheInPriorityOrder() throws {
        let url = try #require(Bundle.module.url(forResource: "codex-models-cache", withExtension: "json", subdirectory: "Fixtures"))
        let models = CodexModels.read(from: url)
        #expect(models.map(\.id) == ["gpt-6.1-sol", "gpt-6-luna", "gpt-5.6-sol"])
        #expect(models.first?.name == "GPT-6.1-Sol")
        #expect(models.first?.recommended == .low)
        #expect(models.first?.supportsGalaxy == true)
        #expect(models[1].supportsGalaxy == false)
        #expect(CodexModels.read(from: URL(filePath: "/nonexistent.json")).isEmpty)
    }

    /// Galaxy needs a Codex model that reasons at "ultra"; one that cannot is swapped for the first
    /// that can.
    @Test func codexGalaxyPicksAModelThatCanDoIt() throws {
        let url = try #require(Bundle.module.url(forResource: "codex-models-cache", withExtension: "json", subdirectory: "Fixtures"))
        let models = CodexModels.read(from: url)
        #expect(CodexModels.model(for: .galaxy, chosen: "gpt-6-luna", in: models) == "gpt-6.1-sol")
        #expect(CodexModels.model(for: .galaxy, chosen: "gpt-5.6-sol", in: models) == "gpt-5.6-sol")
        #expect(CodexModels.model(for: .galaxy, chosen: nil, in: models) == "gpt-6.1-sol")
        #expect(CodexModels.model(for: .high, chosen: "gpt-6-luna", in: models) == "gpt-6-luna")
    }

    @Test func effortsReadLikeTheSlider() {
        #expect(Effort.allCases.map(\.title) == ["Low", "Medium", "High", "Extra", "Max", "Galaxy"])
        #expect(Effort(cliValue: "xhigh") == .extra)
        #expect(Effort(cliValue: "ultra") == .galaxy)
        #expect(Effort(cliValue: "minimal") == .low)
    }
}
