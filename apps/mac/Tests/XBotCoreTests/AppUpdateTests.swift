import Foundation
import Testing
@testable import XBotCore

@Suite struct AppUpdateCheckStoreTests {
    @Test func checksOncePerInterval() {
        let suite = "AppUpdateCheckStoreTests.interval"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        #expect(AppUpdateCheckStore.shouldCheck(defaults: defaults))
        AppUpdateCheckStore.markChecked(now: Date(timeIntervalSince1970: 1_000), defaults: defaults)
        #expect(
            !AppUpdateCheckStore.shouldCheck(
                now: Date(timeIntervalSince1970: 1_000 + 3_600),
                defaults: defaults
            )
        )
        #expect(
            AppUpdateCheckStore.shouldCheck(
                now: Date(timeIntervalSince1970: 1_000 + AppUpdateCheckStore.checkInterval),
                defaults: defaults
            )
        )
    }
}
