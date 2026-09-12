import Foundation

/// When the engine may be stopped because nobody is using it.
///
/// docs/07-container-runtime.md: "The engine idles cheaply, but the VM does not. The app stops the
/// engine after a configurable idle period, default 30 minutes, and starts it on demand when the
/// user sends a message." It was specified and never built, so a Mac that opened xBot once in the
/// morning carried a couple of gigabytes of Postgres, engine and Chromium until somebody noticed —
/// and the doc is blunt about how that ends: "being casual about it is how an app gets uninstalled."
///
/// A pure function so every rule can be pinned down without a container, and so the one that
/// matters most is impossible to get wrong quietly: **a routine the person set up must not stop
/// running because the app decided they were idle.** Routines postdate the doc, and an idle stop
/// written straight from it would have broken "check the inbox every weekday at nine" on the first
/// quiet afternoon, with nothing anywhere saying so.
public enum EngineIdlePolicy {
    /// The doc's default.
    public static let defaultTimeout: TimeInterval = 30 * 60

    public enum Verdict: Equatable, Sendable {
        case keepRunning
        case stop
    }

    /// - Parameter enabledRoutines: how many routines are switched on, or nil when that could not be
    ///   found out. Nil keeps the engine running: stopping on a guess risks exactly the failure this
    ///   type exists to prevent, and the cost of guessing the other way is some memory for a while.
    public static func verdict(
        lastActivity: Date,
        now: Date,
        timeout: TimeInterval = defaultTimeout,
        turnRunning: Bool,
        humanHoldsControl: Bool,
        enabledRoutines: Int?
    ) -> Verdict {
        // Somebody is being answered. Stopping mid-turn would throw the reply away.
        if turnRunning { return .keepRunning }
        // Somebody has their hands on the agent's browser, typing into a real login form.
        if humanHoldsControl { return .keepRunning }
        if now.timeIntervalSince(lastActivity) < timeout { return .keepRunning }
        guard let enabledRoutines else { return .keepRunning }
        return enabledRoutines > 0 ? .keepRunning : .stop
    }
}
