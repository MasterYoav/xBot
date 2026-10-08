import Testing
import XBotCore
@testable import XBotUI

@Suite struct TasksCardRunsTests {
    func steps(_ added: [Bool]) -> [PlanStep] {
        added.enumerated().map { PlanStep(title: "\($0.offset)", active: "", added: $0.element) }
    }

    @Test func addedStepsFormOneHighlightedRunWhileRunning() {
        let runs = TasksCard.runs(steps([false, false, true, true, false]), from: 0, highlightAdded: true)
        #expect(runs == [
            TasksCard.Run(indices: [0, 1], highlighted: false),
            TasksCard.Run(indices: [2, 3], highlighted: true),
            TasksCard.Run(indices: [4], highlighted: false),
        ])
    }

    @Test func afterTheRunNothingIsHighlighted() {
        let runs = TasksCard.runs(steps([false, true, true]), from: 0, highlightAdded: false)
        #expect(runs == [TasksCard.Run(indices: [0, 1, 2], highlighted: false)])
    }

    @Test func foldedStepsAreSkipped() {
        let runs = TasksCard.runs(steps([false, false, false, true]), from: 3, highlightAdded: true)
        #expect(runs == [TasksCard.Run(indices: [3], highlighted: true)])
    }
}
