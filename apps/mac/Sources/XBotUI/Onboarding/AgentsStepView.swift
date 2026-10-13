import SwiftUI
import XBotBrain
import XBotCore

/// Step 2: the four CLIs, each with its state and the one thing to do next. At least one ready, or
/// "Skip for now", lets the tour continue.
struct AgentsStepView: View {
    @Bindable var model: OnboardingModel
    let setup: AgentSetup
    @State private var run: SetupRun?

    var body: some View {
        StepPage(copy: .of(.agents), stageIsScene: false) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.m) { cards }
                Grid(horizontalSpacing: Space.m, verticalSpacing: Space.m) {
                    GridRow { card(.claude); card(.codex) }
                    GridRow { card(.antigravity); card(.copilot) }
                }
            }
        } controls: {
            VStack(alignment: .leading, spacing: Space.s) {
                if setup.anyReady {
                    Label(String(localized: "You're set: continue whenever you like."), systemImage: "checkmark.circle.fill")
                        .captionText()
                        .foregroundStyle(Palette.success)
                } else {
                    Toggle(String(localized: "Skip for now"), isOn: $model.agentsSkipped)
                        .toggleStyle(.checkbox)
                        .font(Typography.body)
                    Text(String(localized: "xBot needs one agent to do any work. You can set one up later in Settings › Agents."))
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(String(localized: "Look again")) { Task { await setup.detect() } }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(setup.running != nil)
            }
        }
        .sheet(item: $run) { run in
            InstallSheet(run: run, setup: setup, close: { self.run = nil })
        }
    }

    @ViewBuilder private var cards: some View {
        ForEach(HarnessKind.allCases, id: \.self) { kind in card(kind) }
    }

    private func card(_ kind: HarnessKind) -> some View {
        AgentCard(kind: kind, state: setup.state(of: kind), unverified: setup.signInUnverified.contains(kind),
                  busy: setup.running != nil,
                  install: { run = setup.start(.install, for: kind) },
                  signIn: { run = setup.start(.signIn, for: kind) },
                  retry: { run = setup.retry(kind) })
    }
}

private struct AgentCard: View {
    let kind: HarnessKind
    let state: AgentState
    let unverified: Bool
    let busy: Bool
    let install: () -> Void
    let signIn: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Circle().fill(Palette.agent(kind)).frame(width: Metrics.dot + 2, height: Metrics.dot + 2)
                Text(kind.displayName).emphasisText().foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            pill
            Text(detail)
                .captionText()
                .foregroundStyle(isFailure ? Palette.failure : Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            Spacer(minLength: 0)
            action
        }
        .padding(Space.m)
        .frame(width: Metrics.agentCard.width, height: Metrics.agentCard.height, alignment: .topLeading)
        .raisedSurface()
        .cardShadow()
        .overlay {
            if state == .ready {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .strokeBorder(Palette.success.opacity(0.5))
            }
        }
        .motion(Motion.quick, value: state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(kind.displayName): \(detail)"))
    }

    private var isFailure: Bool { if case .failed = state { true } else { false } }

    private var pill: some View {
        switch state {
        case .checking: StatusPill(.neutral, String(localized: "Looking"))
        case .missing: StatusPill(.neutral, String(localized: "Not installed"))
        case .installing: StatusPill(.running, String(localized: "Installing"))
        case .installed: StatusPill(.warning, String(localized: "Not signed in"))
        case .signingIn: StatusPill(.running, String(localized: "Signing in"))
        case .ready: StatusPill(.success, String(localized: "Ready"))
        case .needsTool: StatusPill(.warning, String(localized: "Needs a tool"))
        case .failed: StatusPill(.failure, String(localized: "Didn't work"))
        }
    }

    private var detail: String {
        switch state {
        case .checking: String(localized: "Looking for it on this Mac…")
        case .missing: String(localized: "Not on this Mac yet.")
        case .installing: String(localized: "Running its installer…")
        case .installed: String(localized: "Installed. Sign in with your account to use it.")
        case .signingIn: String(localized: "Finish signing in in your browser.")
        case .ready:
            unverified
                ? String(localized: "Installed. It asks you to sign in the first time it runs, if it needs to.")
                : String(localized: "Installed and signed in.")
        case .needsTool(let name, _): String(localized: "Its installer needs \(name), which this Mac doesn't have.")
        case .failed(let reason): reason
        }
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .missing:
            Button(String(localized: "Install"), action: install).buttonStyle(PrimaryButtonStyle()).disabled(busy)
        case .installed:
            Button(String(localized: "Sign in"), action: signIn).buttonStyle(PrimaryButtonStyle()).disabled(busy)
        case .ready:
            if unverified {
                Button(String(localized: "Sign in"), action: signIn).buttonStyle(QuietButtonStyle()).disabled(busy)
            } else {
                Label(String(localized: "Ready"), systemImage: "checkmark.circle.fill")
                    .font(Typography.chip).foregroundStyle(Palette.success)
                    .frame(height: Metrics.chipHeight)
            }
        case .needsTool(let name, let url):
            Link(String(localized: "Get \(name)"), destination: url).font(Typography.chip).tint(Palette.accent)
                .frame(height: Metrics.chipHeight)
        case .failed:
            Button(String(localized: "Try again"), action: retry).buttonStyle(PrimaryButtonStyle()).disabled(busy)
        case .checking, .installing, .signingIn:
            ProgressView().controlSize(.small).frame(height: Metrics.chipHeight)
        }
    }
}
