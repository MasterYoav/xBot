import Foundation
import Testing
@testable import XBotCore

@Suite struct AppUpdateGateTests {
    /// "Check for Updates…" in a build without an appcast says so instead of doing nothing.
    @Test func aBuildWithoutUpdatesSaysSo() {
        #expect(AppUpdateGate.userCheck(configured: false) == .notSetUp)
        #expect(AppUpdateGate.userCheck(configured: true) == .check)
    }

    @Test func theBackgroundCheckWaitsForTurnsAndTheDay() {
        #expect(AppUpdateGate.backgroundCheck(configured: true, due: true, busy: false))
        #expect(!AppUpdateGate.backgroundCheck(configured: true, due: true, busy: true))
        #expect(!AppUpdateGate.backgroundCheck(configured: true, due: false, busy: false))
        #expect(!AppUpdateGate.backgroundCheck(configured: false, due: true, busy: false))
    }

    @Test func aPersonMayAlwaysLook() {
        #expect(AppUpdateGate.mayCheck(userInitiated: true, busy: true))
        #expect(AppUpdateGate.mayCheck(userInitiated: false, busy: false))
        #expect(!AppUpdateGate.mayCheck(userInitiated: false, busy: true))
    }
}

@MainActor @Suite struct UpdateInstallDeferralTests {
    final class Flag { var value: Bool; init(_ value: Bool) { self.value = value } }

    @Test func installsAtOnceWhenNothingRuns() {
        let deferral = UpdateInstallDeferral(interval: .milliseconds(5), isBusy: { false })
        let waits = deferral.deferIfBusy { Issue.record("the caller installs") }
        #expect(!waits)
    }

    /// The relaunch waits for the turn to end, then goes ahead once.
    @Test func waitsForTheTurnsToEnd() async {
        let busy = Flag(true)
        let installed = Flag(false)
        let deferral = UpdateInstallDeferral(interval: .milliseconds(5), isBusy: { busy.value })
        let waits = deferral.deferIfBusy { installed.value = true }
        #expect(waits)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(!installed.value)
        busy.value = false
        for _ in 0..<500 where !installed.value { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(installed.value)
    }
}
