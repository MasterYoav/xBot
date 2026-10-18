import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct OnboardingModelTests {
    func defaults() -> UserDefaults { UserDefaults(suiteName: "onboarding-\(UUID().uuidString)")! }

    @Test func aFirstLaunchShowsTheTourFromWelcome() {
        let model = OnboardingModel(defaults: defaults(), hasLibrary: false)
        #expect(model.isPresented)
        #expect(model.step == .welcome)
        #expect(!model.showsReminder)
    }

    @Test func theStepsAreInTheSpecsOrder() {
        #expect(OnboardingStep.allCases == [
            .welcome, .agents, .chats, .plan, .inspector, .crew, .extras, .files, .phone, .worlds, .ready,
        ])
    }

    @Test func backAndContinueStopAtTheEnds() {
        let model = OnboardingModel(defaults: defaults(), hasLibrary: false)
        #expect(!model.canGoBack)
        model.back()
        #expect(model.step == .welcome)
        model.agentsSkipped = true
        for _ in 0..<30 { model.next() }
        #expect(model.step == .ready)
        #expect(model.isLastStep)
        #expect(model.canGoBack)
        model.back()
        #expect(model.step == .worlds)
        #expect(model.direction == -1)
        model.next()
        #expect(model.direction == 1)
    }

    @Test func goingToAStepRecordsTheDirectionOfTravel() {
        let model = OnboardingModel(defaults: defaults(), hasLibrary: false)
        model.agentsReady = true
        model.go(to: .files)
        #expect(model.step == .files && model.direction == 1)
        model.go(to: .chats)
        #expect(model.step == .chats && model.direction == -1)
    }

    @Test func theAgentsStepNeedsOneReadyAgentOrSkipForNow() {
        let model = OnboardingModel(defaults: defaults(), hasLibrary: false)
        model.next()
        #expect(model.step == .agents)
        #expect(!model.canContinue)
        model.next()
        #expect(model.step == .agents)
        model.agentsReady = true
        #expect(model.canContinue)
        model.agentsReady = false
        model.agentsSkipped = true
        #expect(model.canContinue)
        model.next()
        #expect(model.step == .chats)
    }

    /// A progress dot can't jump past the agents step before it's done.
    @Test func dotsDoNotJumpPastAnUnfinishedAgentsStep() {
        let model = OnboardingModel(defaults: defaults(), hasLibrary: false)
        #expect(model.canGo(to: .agents))
        #expect(!model.canGo(to: .files))
        model.go(to: .files)
        #expect(model.step == .welcome)
        model.agentsSkipped = true
        #expect(model.canGo(to: .files))
        model.go(to: .files)
        #expect(model.step == .files)
        model.go(to: .welcome)
        #expect(model.step == .welcome)
    }

    @Test func otherStepsAlwaysContinue() {
        let model = OnboardingModel(defaults: defaults(), hasLibrary: false)
        #expect(model.canContinue)
        model.agentsSkipped = true
        model.go(to: .files)
        #expect(model.canContinue)
    }

    @Test func completionPersistsWithItsVersion() {
        let store = defaults()
        let model = OnboardingModel(defaults: store, hasLibrary: false)
        model.complete()
        #expect(!model.isPresented)
        #expect(store.integer(forKey: "onboarding.completedVersion") == OnboardingModel.currentVersion)
        let relaunch = OnboardingModel(defaults: store, hasLibrary: false)
        #expect(!relaunch.isPresented && !relaunch.showsReminder)
    }

    @Test func aNewerTourIsShownAgain() {
        let store = defaults()
        store.set(OnboardingModel.currentVersion - 1, forKey: "onboarding.completedVersion")
        #expect(OnboardingModel(defaults: store, hasLibrary: true).isPresented)
        #expect(OnboardingModel.shouldShowOnLaunch(completedVersion: 0, skipped: false))
        #expect(!OnboardingModel.shouldShowOnLaunch(completedVersion: OnboardingModel.currentVersion, skipped: false))
        #expect(!OnboardingModel.shouldShowOnLaunch(completedVersion: nil, skipped: true))
        #expect(OnboardingModel.shouldShowOnLaunch(completedVersion: nil, skipped: false))
    }

    @Test func skippingLeavesTheReminderAndIsNotShownOnTheNextLaunch() {
        let store = defaults()
        let model = OnboardingModel(defaults: store, hasLibrary: false)
        model.next()
        model.skip()
        #expect(!model.isPresented)
        #expect(model.showsReminder)
        #expect(store.bool(forKey: "onboarding.skipped"))
        let relaunch = OnboardingModel(defaults: store, hasLibrary: false)
        #expect(!relaunch.isPresented)
        #expect(relaunch.showsReminder)
    }

    @Test func dismissingTheReminderSticks() {
        let store = defaults()
        let model = OnboardingModel(defaults: store, hasLibrary: false)
        model.skip()
        model.dismissReminder()
        #expect(!model.showsReminder)
        #expect(!OnboardingModel(defaults: store, hasLibrary: false).showsReminder)
    }

    @Test func finishingAfterASkipClearsTheReminder() {
        let store = defaults()
        let model = OnboardingModel(defaults: store, hasLibrary: false)
        model.skip()
        model.reopen()
        model.complete()
        #expect(!model.showsReminder)
        #expect(!store.bool(forKey: "onboarding.skipped"))
    }

    @Test func theWelcomeTourReopensFromTheStart() {
        let model = OnboardingModel(defaults: defaults(), hasLibrary: false)
        model.agentsSkipped = true
        model.go(to: .phone)
        model.complete()
        model.reopen()
        #expect(model.isPresented)
        #expect(model.step == .welcome)
        #expect(!model.agentsSkipped)
    }

    @Test func skippingAReopenedTourAfterFinishingLeavesNoReminder() {
        let model = OnboardingModel(defaults: defaults(), hasLibrary: false)
        model.complete()
        model.reopen()
        model.skip()
        #expect(!model.showsReminder)
        #expect(!model.isPresented)
    }

    /// Someone upgrading with chats or projects already isn't sent through the first run.
    @Test func anExistingLibraryCountsAsDone() {
        let store = defaults()
        let model = OnboardingModel(defaults: store, hasLibrary: true)
        #expect(!model.isPresented)
        #expect(!model.showsReminder)
        #expect(store.integer(forKey: "onboarding.completedVersion") == OnboardingModel.currentVersion)
    }

    @Test func anExistingLibraryDoesNotOverrideASkip() {
        let store = defaults()
        store.set(true, forKey: "onboarding.skipped")
        let model = OnboardingModel(defaults: store, hasLibrary: true)
        #expect(!model.isPresented)
        #expect(model.showsReminder)
    }

    @Test func aWorkspaceWithChatsOrProjectsHasALibrary() {
        let inbox = FileManager.default.temporaryDirectory.appending(path: "ob-\(UUID().uuidString)")
        let empty = Workspace(store: .inMemory(), inbox: inbox, discover: { [:] })
        #expect(!empty.hasLibrary)
        let store = Store.inMemory()
        let w = Workspace(store: store, inbox: inbox, discover: { [:] })
        _ = w.addProject(at: FileManager.default.temporaryDirectory)
        #expect(w.hasLibrary)
        #expect(Workspace(store: store, inbox: inbox, discover: { [:] }).hasLibrary)
    }
}
