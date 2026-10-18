import SwiftUI
import XBotBrain
import XBotCore

/// The welcome tour, edge to edge in the main window in place of its content: a scene, a title,
/// one sentence and a few bullets, the step's own controls, progress dots, Back / Continue / Skip.
/// ← and → move between steps, Return continues.
public struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let workspace: Workspace
    @State private var setup = AgentSetup(recipes: OnboardingView.recipes)
    @State private var files = FileAccess()
    /// The step on screen. It follows `model.step` one beat later, so the outgoing screen has
    /// already been told which way to leave (the direction of travel) when it's removed.
    @State private var shown: OnboardingStep
    @State private var travel = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: OnboardingModel, workspace: Workspace) {
        self.model = model
        self.workspace = workspace
        _shown = State(initialValue: model.step)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Palette.window.ignoresSafeArea()
            Backdrop(.home).ignoresSafeArea()
            VStack(spacing: 0) {
                // The traffic lights' row: the window moves from here.
                Color.clear
                    .frame(height: Metrics.titleBar + Space.s)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                ZStack {
                    page(shown)
                        .id(shown)
                        .transition(slide)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                bottomBar
            }
            keyboard
        }
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: model.step) { _, step in
            travel = model.direction
            Task { @MainActor in
                withAnimation(reduceMotion ? Motion.reduced : Motion.standard) { shown = step }
            }
        }
        .onChange(of: setup.anyReady, initial: true) { _, ready in model.agentsReady = ready }
        .task { await setup.detect() }
    }

    /// The official commands. A debug build can swap in a harmless one, to look at the install
    /// sheet without installing anything: `XBOT_ONBOARDING_FAKE_COMMAND='echo hi; exit 3'`.
    static let recipes: @Sendable (HarnessKind) -> AgentRecipe = { kind in
        var recipe = AgentInstaller.recipe(for: kind)
        #if DEBUG
        if let fake = ProcessInfo.processInfo.environment["XBOT_ONBOARDING_FAKE_COMMAND"] {
            recipe.install = fake
            recipe.login = fake
        }
        #endif
        return recipe
    }

    /// In from the side it's travelling towards, out the other; a cross-fade under Reduce Motion.
    private var slide: AnyTransition {
        if reduceMotion { return .opacity }
        let forward = travel >= 0
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder private func page(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome: SceneStepView(step: step) { WelcomeScene() }
        case .agents: AgentsStepView(model: model, setup: setup)
        case .chats: SceneStepView(step: step) { ChatsScene() }
        case .plan: SceneStepView(step: step) { PlanScene() }
        case .inspector: SceneStepView(step: step) { InspectorScene() }
        case .crew: SceneStepView(step: step) { CrewScene() }
        case .extras: SceneStepView(step: step) { ExtrasScene() }
        case .files: FilesStepView(files: files)
        case .phone: PhoneStepView(remote: workspace.remote, notNow: { model.next() })
        case .worlds: WorldsStepView(workspace: workspace)
        case .ready: ReadyStepView(start: finish)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: Space.m) {
            HStack {
                if !model.isLastStep {
                    Button(String(localized: "Skip")) { skip() }
                        .buttonStyle(QuietButtonStyle())
                        .help(String(localized: "Skip the tour. Home keeps a reminder to finish it."))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            dots
            HStack(spacing: Space.s) {
                Spacer(minLength: 0)
                Button(String(localized: "Back")) { model.back() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(!model.canGoBack)
                    .opacity(model.canGoBack ? 1 : 0)
                if !model.isLastStep {
                    Button(String(localized: "Continue")) { model.next() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canContinue)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.l)
    }

    private var dots: some View {
        HStack(spacing: Space.s) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Button { model.go(to: step) } label: {
                    Capsule()
                        .fill(step == model.step ? Palette.textPrimary : Palette.textTertiary)
                        .frame(width: step == model.step ? Metrics.dot * 3 : Metrics.dot, height: Metrics.dot)
                        .padding(.vertical, Space.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(XBotButtonStyle())
                .disabled(!model.canGo(to: step))
                .accessibilityLabel(String(localized: "Step \(step.rawValue + 1) of \(model.count)"))
            }
        }
        .motion(Motion.quick, value: model.step)
    }

    /// ← and → without a modifier, from anywhere in the tour (Return is Continue's own shortcut).
    private var keyboard: some View {
        ZStack {
            Button("") { model.back() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.next() }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func skip() {
        model.skip()
        Task { await workspace.refreshHarnesses() }
    }

    /// Ready › Start: the main window, with Home's composer focused.
    private func finish() {
        model.complete()
        workspace.startDraft(in: nil)
        Task { await workspace.refreshHarnesses() }
    }
}

/// The words on each step: a title, one sentence, at most three bullets.
struct StepCopy {
    let title: String
    let sentence: String
    var bullets: [String] = []

    static func of(_ step: OnboardingStep) -> StepCopy {
        switch step {
        case .welcome:
            StepCopy(
                title: String(localized: "Your AI crew, on your Mac."),
                sentence: String(localized: "xBot puts a home around the coding agents you already use, and a crew of them to work for you."),
                bullets: [
                    String(localized: "Your chats and projects stay on this Mac."),
                    String(localized: "Works with Claude Code, Codex, Antigravity and GitHub Copilot."),
                ]
            )
        case .agents:
            StepCopy(
                title: String(localized: "Your agents"),
                sentence: String(localized: "xBot works through the agents you already pay for. Set up at least one."),
                bullets: [
                    String(localized: "Install runs the agent's official installer, where you can see it."),
                    String(localized: "Sign in opens your browser, as the agent itself does."),
                ]
            )
        case .chats:
            StepCopy(
                title: String(localized: "Projects and chats"),
                sentence: String(localized: "Add a folder, and each chat with an agent opens in a tab of its own."),
                bullets: [
                    String(localized: "Replies stream in as the agent works."),
                    String(localized: "Each tool the agent runs folds into one line."),
                    String(localized: "A chat without a project goes in the Inbox."),
                ]
            )
        case .plan:
            StepCopy(
                title: String(localized: "Plans you can edit"),
                sentence: String(localized: "Ask for a plan first, change it, then let the agent work through it."),
                bullets: [
                    String(localized: "Drag steps into a new order."),
                    String(localized: "Each step ticks off as it's done."),
                ]
            )
        case .inspector:
            StepCopy(
                title: String(localized: "Changes, files and a terminal"),
                sentence: String(localized: "See what an agent changed and run commands without leaving the chat."),
                bullets: [
                    String(localized: "Every changed file, line by line."),
                    String(localized: "Pull requests and their checks."),
                    String(localized: "A terminal for each chat."),
                ]
            )
        case .crew:
            StepCopy(
                title: String(localized: "Your crew, organised like a company"),
                sentence: String(localized: "HeadMaster leads. Hire agents, give each a role, and decide who reports to whom."),
                bullets: [
                    String(localized: "Work is handed down, and reported back up."),
                    String(localized: "Each agent can use its own agent CLI and model."),
                ]
            )
        case .extras:
            StepCopy(
                title: String(localized: "Notes, abilities and automations"),
                sentence: String(localized: "Notes beside your projects, connectors and skills, and work that runs on a schedule."),
                bullets: [
                    String(localized: "Notes are Markdown files in the project."),
                    String(localized: "Turn connectors and skills on and off."),
                    String(localized: "Automations run while xBot is closed, too."),
                ]
            )
        case .files:
            StepCopy(
                title: String(localized: "Let your agents into your files"),
                sentence: String(localized: "macOS asks once for each folder. Allow them now, and an agent never stops mid-task to ask."),
                bullets: [String(localized: "You can change this any time in System Settings.")]
            )
        case .phone:
            StepCopy(
                title: String(localized: "Your iPhone, too"),
                sentence: String(localized: "Keep working with your agents from your iPhone or iPad. They still run on this Mac."),
                bullets: [
                    String(localized: "On the same Wi-Fi it connects directly; away, through your iCloud."),
                    String(localized: "Optional: pair later in Settings › Devices."),
                ]
            )
        case .worlds:
            StepCopy(
                title: String(localized: "Make it yours"),
                sentence: String(localized: "Pick the world your crew lives in, and how xBot looks."),
                bullets: [String(localized: "Both can be changed later: the Agents page and Settings › Appearance.")]
            )
        case .ready:
            StepCopy(
                title: String(localized: "Ask HeadMaster anything."),
                sentence: String(localized: "HeadMaster takes on what you ask, and hands it to the right member of the crew.")
            )
        }
    }
}

/// One step's page: the stage (an animated scene, or the agents' cards) on top; below it the words,
/// and the step's controls beside them when it has any.
struct StepPage<Stage: View, Controls: View>: View {
    let copy: StepCopy
    let stageIsScene: Bool
    /// Controls centred under the words (Ready's Start) rather than beside them.
    let controlsBelow: Bool
    /// How much the scene is enlarged on its stage: 1 for the drawn worlds, more for mock windows.
    let zoom: CGFloat
    @ViewBuilder let stage: () -> Stage
    @ViewBuilder let controls: () -> Controls

    init(copy: StepCopy, stageIsScene: Bool = true, controlsBelow: Bool = false, zoom: CGFloat = 1,
         @ViewBuilder stage: @escaping () -> Stage, @ViewBuilder controls: @escaping () -> Controls) {
        self.copy = copy
        self.zoom = zoom
        self.stageIsScene = stageIsScene
        self.controlsBelow = controlsBelow
        self.stage = stage
        self.controls = controls
    }

    private var hasControls: Bool { Controls.self != EmptyView.self }

    var body: some View {
        GeometryReader { geometry in
            let height = min(max(geometry.size.height * Metrics.onboardingSceneShare, Metrics.onboardingScene.lowerBound),
                             Metrics.onboardingScene.upperBound)
            VStack(spacing: Space.xl) {
                Spacer(minLength: 0)
                if stageIsScene {
                    let size = CGSize(width: min(height * 12 / 7, geometry.size.width - Space.xxl * 2),
                                      height: min(height, (geometry.size.width - Space.xxl * 2) * 7 / 12))
                    // Every scene sits on one stage card, so the drawn worlds and the mock windows
                    // read as the same thing. The mock windows are composed small on their canvas;
                    // zoomed, they fill the stage like the worlds do.
                    stage()
                        .scaleEffect(zoom)
                        .frame(width: size.width, height: size.height)
                        .background(StageCard())
                        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.hairline))
                        .floatingShadow()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    stage()
                }
                if hasControls && controlsBelow {
                    words(alignment: .center)
                        .frame(maxWidth: Metrics.onboardingText + Metrics.onboardingControls / 2)
                    controls()
                } else if hasControls {
                    HStack(alignment: .top, spacing: Space.xxl) {
                        words(alignment: .leading)
                            .frame(maxWidth: Metrics.onboardingText, alignment: .leading)
                        controls()
                            .frame(maxWidth: Metrics.onboardingControls, alignment: .leading)
                    }
                } else {
                    words(alignment: .center)
                        .frame(maxWidth: Metrics.onboardingText + Metrics.onboardingControls / 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.xxl)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func words(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Space.s) {
            Text(copy.title).heroText()
                .foregroundStyle(Palette.textPrimary)
            Text(copy.sentence).bodyText()
                .foregroundStyle(Palette.textSecondary)
            if !copy.bullets.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(copy.bullets, id: \.self) { bullet in
                        Label {
                            Text(bullet).captionText().foregroundStyle(Palette.textSecondary)
                        } icon: {
                            Image(systemName: "checkmark").font(Typography.caption).foregroundStyle(Palette.accent)
                        }
                    }
                }
                .padding(.top, Space.xs)
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension StepPage where Controls == EmptyView {
    init(copy: StepCopy, zoom: CGFloat = 1, @ViewBuilder stage: @escaping () -> Stage) {
        self.init(copy: copy, zoom: zoom, stage: stage, controls: { EmptyView() })
    }
}

/// A step that only explains: its scene and its words (Welcome, chats, plans, the inspector, the
/// crew, the extras).
struct SceneStepView<Scene: View>: View {
    let step: OnboardingStep
    @ViewBuilder let scene: () -> Scene

    var body: some View {
        StepPage(copy: .of(step), zoom: step == .plan ? Metrics.onboardingMockZoom : 1, stage: scene)
    }
}

/// The card behind a scene: frosted, with a soft glow of the accent from the top. The world scenes
/// paint over it edge to edge.
private struct StageCard: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            LinearGradient(colors: [Palette.accent.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
        }
    }
}
