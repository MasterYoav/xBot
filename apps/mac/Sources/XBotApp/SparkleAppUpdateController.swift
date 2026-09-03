import Sparkle
import XBotCore

/// Sparkle 2 integration. Active only when `SUFeedURL` and `SUPublicEDKey` are in the bundled
/// Info.plist (release builds). Dev SwiftPM runs have neither and stay inert.
@MainActor
final class SparkleAppUpdateController: NSObject, AppUpdateControlling, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private var isBlocked: () -> Bool = { false }

    var isConfigured: Bool {
        resolvedFeedURL != nil && resolvedPublicKey != nil
    }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        if isConfigured {
            controller.startUpdater()
        }
    }

    func bindUpdateBlockingActivity(_ isBlocked: @escaping () -> Bool) {
        self.isBlocked = isBlocked
    }

    func checkForUpdates(userInitiated: Bool) {
        guard isConfigured, !isBlocked() else { return }
        controller.checkForUpdates(nil)
        AppUpdateCheckStore.markChecked()
    }

    func scheduleAutomaticCheckIfDue() {
        guard isConfigured, AppUpdateCheckStore.shouldCheck(), !isBlocked() else { return }
        controller.updater.checkForUpdatesInBackground()
        AppUpdateCheckStore.markChecked()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        resolvedFeedURL
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isBlocked() {
            throw CancellationError()
        }
    }

    private var resolvedFeedURL: String? {
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           !url.isEmpty
        {
            return url
        }
        if let url = ProcessInfo.processInfo.environment["XBOT_APPCAST_URL"], !url.isEmpty {
            return url
        }
        return nil
    }

    private var resolvedPublicKey: String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
           !key.isEmpty
        {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["XBOT_SPARKLE_PUBLIC_KEY"], !key.isEmpty {
            return key
        }
        return nil
    }
}
