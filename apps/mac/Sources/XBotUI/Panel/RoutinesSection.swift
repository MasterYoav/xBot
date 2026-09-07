import SwiftUI
import XBotCore
import XBotEngine

/// Recurring instructions this agent carries out on a schedule.
///
/// It shows and it stops; it does not compose. That is upstream's design and it is the right one for
/// this product too — `server/src/routines/routes.ts` has deliberately no create and no edit route,
/// because making a routine means turning a sentence into a cron expression and a channel, and a
/// conversation does that better than a form with a schedule field in it. So where this panel used
/// to carry a "Create Routine" button that did nothing at all, it now carries the sentence that
/// actually works: ask the agent.
public struct RoutinesSection: View {
    @Environment(AppState.self) private var state
    @State private var routines = RoutinesState()

    public init() {}

    public var body: some View {
        PanelSectionBody(String(localized: "Routines")) {
            if let problem = routines.problem {
                // Never an empty list on failure: "no routines" and "I could not ask" are opposite
                // answers, and only one of them means go and make one.
                Text(problem)
                    .captionText()
                    .foregroundStyle(Palette.stateFailed)
            } else if routines.routines.isEmpty {
                Text(
                    routines.isLoading
                        ? String(localized: "Reading…")
                        : String(localized: "Nothing standing. Ask this agent for something on a schedule — “check the inbox every weekday at nine” — and it will set one up.")
                )
                .captionText()
                .foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(routines.routines) { routine in
                    RoutineRow(
                        routine: routine,
                        onToggle: { enabled in
                            Task {
                                await routines.setEnabled(routine.id, to: enabled) {
                                    try await state.setRoutineEnabled($0, enabled: $1)
                                }
                            }
                        },
                        onDelete: {
                            Task {
                                await routines.delete(routine.id) {
                                    try await state.deleteRoutine($0)
                                }
                            }
                        }
                    )
                }

                Divider().overlay(Palette.separator).padding(.vertical, Space.xxs)

                Text(String(localized: "Ask the agent in the conversation to add or change one."))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .task(id: state.selectedAgentID) {
            await routines.load(for: state.selectedAgentID) { try await state.routines() }
        }
    }
}

struct RoutineRow: View {
    let routine: Routine
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.s) {
                Text(routine.instruction)
                    .bodyText()
                    .lineLimit(2)
                    .foregroundStyle(routine.enabled ? Palette.textPrimary : Palette.textTertiary)

                Spacer(minLength: Space.s)

                if hovering {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityLabel(String(localized: "Delete routine"))
                }

                Toggle(
                    String(localized: "On"),
                    isOn: Binding(get: { routine.enabled }, set: onToggle)
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            HStack(spacing: Space.xs) {
                // Display text, never parsed. The engine computes both of these from the expression
                // itself, and a second cron reader here would be a second answer to when it runs.
                Text(routine.schedule).captionText()
                if let next = routine.nextRunAt, routine.enabled {
                    Text("·").captionText()
                    Text(next, format: .relative(presentation: .named)).captionText()
                }
                if routine.channelIsGone {
                    Text("·").captionText()
                    // It still runs; it has nowhere to speak. Silence would be the confusing
                    // version of that.
                    Text(String(localized: "its channel is gone"))
                        .captionText()
                        .foregroundStyle(Palette.stateFailed)
                }
            }
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, Space.xxs)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
    }
}
