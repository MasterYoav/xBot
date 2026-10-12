import AppKit
import Sparkle
import XBotCore

/// Sparkle 2 integration. Active only when `SUFeedURL` and `SUPublicEDKey` are in the bundled
/// Info.plist (release builds). Dev SwiftPM runs have neither and stay inert.
@MainActor
final class SparkleAppUpdateController: NSObject, AppUpdateControlling, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private var isBlocked: () -> Bool = { false }
    /// Holds the relaunch that installs an update until no turn is running.
    private lazy var installDeferral = UpdateInstallDeferral { [weak self] in self?.isBlocked() ?? false }
    /// Looks again every hour whether the daily check is due: the app can stay open for days.
    private var dailyCheck: Timer?

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
        switch AppUpdateGate.userCheck(configured: isConfigured) {
        case .notSetUp:
            let alert = NSAlert()
            alert.messageText = String(localized: "Updates aren't set up in this build")
            alert.informativeText = String(localized: "This copy of xBot was built without an update feed, so it can't look for a newer version. Copies downloaded from the xBot website update themselves.")
            alert.runModal()
        case .check:
            // Even mid-turn: looking is harmless, and installing waits for the turn (see below).
            controller.checkForUpdates(nil)
            AppUpdateCheckStore.markChecked()
        }
    }

    /// At launch, and every hour after: the daily background check, when it's due and no turn runs.
    func scheduleAutomaticCheckIfDue() {
        checkInBackgroundIfDue()
        guard isConfigured, dailyCheck == nil else { return }
        dailyCheck = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkInBackgroundIfDue() }
        }
    }

    private func checkInBackgroundIfDue() {
        guard AppUpdateGate.backgroundCheck(configured: isConfigured, due: AppUpdateCheckStore.shouldCheck(), busy: isBlocked()) else { return }
        controller.updater.checkForUpdatesInBackground()
        AppUpdateCheckStore.markChecked()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        resolvedFeedURL
    }

    /// Sparkle's own scheduled checks wait for the turns too; a person asking doesn't.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if !AppUpdateGate.mayCheck(userInitiated: updateCheck == .updates, busy: isBlocked()) {
            throw CancellationError()
        }
    }

    /// Installing relaunches the app, which would cut off a reply: it waits until no turn runs.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installDeferral.deferIfBusy { installHandler() }
    }

    /// The appcast, from the signed bundle — and from the environment only in a debug build.
    ///
    /// See `AppUpdateTrust`. Both this and the key below used to fall back to the environment
    /// unconditionally, which handed the update channel to anything able to set a variable for this
    /// process.
    private var resolvedFeedURL: String? {
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           AppUpdateTrust.isAcceptableFeed(url)
        {
            return url
        }
        guard AppUpdateTrust.allowsEnvironmentOverride,
              let url = ProcessInfo.processInfo.environment["XBOT_APPCAST_URL"],
              AppUpdateTrust.isAcceptableFeed(url)
        else { return nil }
        return url
    }

    /// The EdDSA public key. Whoever controls this controls what the app installs.
    private var resolvedPublicKey: String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
           !key.isEmpty
        {
            return key
        }
        guard AppUpdateTrust.allowsEnvironmentOverride,
              let key = ProcessInfo.processInfo.environment["XBOT_SPARKLE_PUBLIC_KEY"],
              !key.isEmpty
        else { return nil }
        return key
    }
}
