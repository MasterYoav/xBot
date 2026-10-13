import Foundation
import Observation

/// The first run's screens, in order (docs/06-onboarding.md).
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, agents, chats, plan, inspector, crew, extras, files, phone, worlds, ready
}

/// Where the person is in the welcome tour, and whether it's done.
///
/// Completion is stored as the tour's version, not a flag, so a future tour with something new to
/// show can be shown again to people who finished this one: bump `currentVersion`.
@MainActor
@Observable
public final class OnboardingModel {
    /// Bump to show the tour again to everyone who finished an older one.
    public static let currentVersion = 1

    enum Keys {
        static let completedVersion = "onboarding.completedVersion"
        static let skipped = "onboarding.skipped"
        static let reminderDismissed = "onboarding.reminderDismissed"
    }

    /// Shown in place of the window's content.
    public private(set) var isPresented: Bool
    public private(set) var step: OnboardingStep = .welcome
    /// +1 when the last move went forward, -1 back: the way the next screen slides in.
    public private(set) var direction = 1
    /// The agents step: at least one CLI ready (set by the step from `AgentSetup`).
    public var agentsReady = false
    /// The agents step: "Skip for now".
    public var agentsSkipped = false
    /// Home's "Finish setting up" row.
    public private(set) var showsReminder: Bool

    @ObservationIgnored private let defaults: UserDefaults

    /// `hasLibrary`: the library already holds chats or projects. Someone upgrading to the first
    /// version with a tour has been using xBot already and isn't sent through it.
    public init(defaults: UserDefaults = .standard, hasLibrary: Bool) {
        self.defaults = defaults
        let skipped = defaults.bool(forKey: Keys.skipped)
        if defaults.object(forKey: Keys.completedVersion) == nil, hasLibrary, !skipped {
            defaults.set(Self.currentVersion, forKey: Keys.completedVersion)
        }
        let completed = defaults.object(forKey: Keys.completedVersion) as? Int
        isPresented = Self.shouldShowOnLaunch(completedVersion: completed, skipped: skipped)
        showsReminder = Self.reminderShown(completedVersion: completed, skipped: skipped,
                                           dismissed: defaults.bool(forKey: Keys.reminderDismissed))
    }

    /// Not finished (this version of the tour), and not skipped.
    public static func shouldShowOnLaunch(completedVersion: Int?, skipped: Bool) -> Bool {
        (completedVersion ?? 0) < currentVersion && !skipped
    }

    static func reminderShown(completedVersion: Int?, skipped: Bool, dismissed: Bool) -> Bool {
        skipped && (completedVersion ?? 0) < currentVersion && !dismissed
    }

    public var index: Int { step.rawValue }
    public var count: Int { OnboardingStep.allCases.count }
    public var isLastStep: Bool { step == OnboardingStep.allCases.last }
    public var canGoBack: Bool { step != .welcome }

    /// Every step continues, except agents until one is ready or the person chose to skip it.
    public var canContinue: Bool {
        step == .agents ? agentsReady || agentsSkipped : true
    }

    public func next() {
        guard canContinue, let following = OnboardingStep(rawValue: index + 1) else { return }
        direction = 1
        step = following
    }

    public func back() {
        guard let previous = OnboardingStep(rawValue: index - 1) else { return }
        direction = -1
        step = previous
    }

    /// A progress dot: any step, either way.
    public func go(to target: OnboardingStep) {
        guard target != step else { return }
        direction = target.rawValue > index ? 1 : -1
        step = target
    }

    /// Ready › Start.
    public func complete() {
        defaults.set(Self.currentVersion, forKey: Keys.completedVersion)
        defaults.set(false, forKey: Keys.skipped)
        isPresented = false
        showsReminder = false
    }

    /// Skip, from any step: the tour goes, and Home offers to finish it later (unless it was
    /// finished before and only reopened from the Help menu).
    public func skip() {
        isPresented = false
        let completed = defaults.object(forKey: Keys.completedVersion) as? Int
        guard (completed ?? 0) < Self.currentVersion else { return }
        defaults.set(true, forKey: Keys.skipped)
        defaults.set(false, forKey: Keys.reminderDismissed)
        showsReminder = true
    }

    /// The × on Home's reminder.
    public func dismissReminder() {
        defaults.set(true, forKey: Keys.reminderDismissed)
        showsReminder = false
    }

    /// Help › Welcome Tour, or the reminder's button: from the start.
    public func reopen() {
        step = .welcome
        direction = 1
        agentsSkipped = false
        isPresented = true
    }
}

extension Workspace {
    /// Chats or projects already exist: someone who has used xBot before.
    public var hasLibrary: Bool { !projects.isEmpty || !chats.isEmpty }
}
