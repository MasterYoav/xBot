import Foundation

/// App update checks through Sparkle. See docs/11-packaging-and-updates.md.
@MainActor
public protocol AppUpdateControlling: AnyObject {
    /// Whether an appcast URL and public key are configured for this build.
    var isConfigured: Bool { get }

    /// Called once at launch so the controller can hold background checks, and the relaunch that
    /// installs an update, while a turn is running.
    func bindUpdateBlockingActivity(_ isBlocked: @escaping () -> Bool)

    /// "Check for Updates…". In a build without an appcast it says so instead of doing nothing.
    func checkForUpdates(userInitiated: Bool)

    /// Daily automatic check — skipped while `isBlocked` returns true.
    func scheduleAutomaticCheckIfDue()
}

/// When Sparkle is not configured (no appcast in the bundled Info.plist).
@MainActor
public final class DisabledAppUpdateController: AppUpdateControlling {
    public static let shared = DisabledAppUpdateController()

    public var isConfigured: Bool { false }

    public func bindUpdateBlockingActivity(_ isBlocked: @escaping () -> Bool) {}

    public func checkForUpdates(userInitiated: Bool) {}

    public func scheduleAutomaticCheckIfDue() {}
}

/// What the update controller decides, apart from Sparkle, so it can be tested.
public enum AppUpdateGate {
    public enum UserCheck: Equatable, Sendable {
        /// A build without an appcast and key (a development build): say updates aren't set up.
        case notSetUp
        case check
    }

    public static func userCheck(configured: Bool) -> UserCheck { configured ? .check : .notSetUp }

    /// The daily check in the background: configured, due, and no turn running.
    public static func backgroundCheck(configured: Bool, due: Bool, busy: Bool) -> Bool {
        configured && due && !busy
    }

    /// Whether Sparkle may look now. A person asking may; a background check waits for the turns.
    /// Looking is harmless either way: installing is what waits (`UpdateInstallDeferral`).
    public static func mayCheck(userInitiated: Bool, busy: Bool) -> Bool { userInitiated || !busy }
}

/// Holds the relaunch that installs an update until no turn is running, so an update never lands
/// in the middle of a reply (the relaunch would cut it off).
@MainActor
public final class UpdateInstallDeferral {
    private let isBusy: () -> Bool
    private let interval: Duration
    private var waiting: Task<Void, Never>?

    public init(interval: Duration = .seconds(2), isBusy: @escaping () -> Bool) {
        self.interval = interval
        self.isBusy = isBusy
    }

    /// Whether the install is waiting. False: nothing is running, install now. True: `install`
    /// runs once nothing is (a later call replaces an earlier wait).
    public func deferIfBusy(_ install: @escaping @MainActor () -> Void) -> Bool {
        guard isBusy() else { return false }
        waiting?.cancel()
        let interval = interval
        waiting = Task { @MainActor [weak self] in
            while self?.isBusy() == true {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
            }
            guard self != nil else { return }
            install()
        }
        return true
    }

    public var isWaiting: Bool { waiting != nil }
}

/// When the app last looked for a newer xBot build.
public enum AppUpdateCheckStore: Sendable {
    public static let checkInterval: TimeInterval = 86_400

    private static let lastCheckKey = "xbot.app.lastUpdateCheck"

    public static func shouldCheck(
        now: Date = .now,
        interval: TimeInterval = checkInterval,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let last = defaults.object(forKey: lastCheckKey) as? Date else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    public static func markChecked(now: Date = .now, defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastCheckKey)
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastCheckKey)
    }
}
