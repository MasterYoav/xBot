import Testing
@testable import XBotCore

/// Animation clocks (worlds, faces, wallpapers, timers) run only while someone can see them.
@Suite struct MotionPolicyTests {
    @Test func motionRunsOnlyWhileTheAppIsActiveAndItsWindowIsOnScreen() {
        #expect(MotionPolicy.isLive(appActive: true, windowOnScreen: true))
        #expect(!MotionPolicy.isLive(appActive: false, windowOnScreen: true))
        #expect(!MotionPolicy.isLive(appActive: true, windowOnScreen: false))
        #expect(!MotionPolicy.isLive(appActive: false, windowOnScreen: false))
    }
}
