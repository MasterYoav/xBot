import Testing
import XBotCore
@testable import XBotUI

@MainActor @Suite struct AgentsBackdropTests {
    @Test func agentsUsesItsWorldInsteadOfWallpaper() {
        #expect(!RootView.usesWallpaper(on: .agents))
    }

    @Test(arguments: [(280.0, 800.0), (480.0, 400.0)])
    func sceneryBottomStaysAlignedWithMeasuredStage(stageBottom: Double, viewportHeight: Double) {
        let sceneHeight = WorkplaceBackdropLayout.sceneHeight(
            stageBottom: stageBottom, viewportHeight: viewportHeight
        )
        #expect(Double(sceneHeight) == stageBottom)
        #expect(Double(sceneHeight) - 74 == stageBottom - 74)
    }

    @Test(arguments: [0.001, 0.0, -40.0])
    func offscreenStageUsesOnlyAPositiveSafeHeight(stageBottom: Double) {
        let sceneHeight = WorkplaceBackdropLayout.sceneHeight(
            stageBottom: stageBottom, viewportHeight: 800
        )
        #expect(sceneHeight == 1)
    }

    @Test func otherTabsKeepTheirWallpaper() {
        for page in [Page.main, .notes, .abilities, .profile] {
            #expect(RootView.usesWallpaper(on: page))
        }
    }
}
