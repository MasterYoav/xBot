import SwiftUI
import XBotCore
import XBotEngine

/// Settings → Audit. The append-only record of what agents did, natively.
///
/// The one admin surface ADR-0004 keeps out of a webview: "It is the product's central trust claim.
/// A user who wants to know what their agent did with their browser should not meet a
/// different-feeling interface at exactly that moment."
public struct AuditSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var audit = AuditState()

    public init() {}

    public var body: some View {
        Form {
            Section {
                TextField(
                    String(localized: "Filter by event, e.g. computer"),
                    text: $audit.eventTypeFilter
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await reload() } }
            } footer: {
                Text(String(
                    localized: "Everything an agent did that the engine recorded. Nothing here can be edited or deleted from the app — retention is an engine setting."
                ))
            }

            Section {
                if let problem = audit.problem {
                    // Not an empty list. "Nothing has happened" and "I could not ask" are opposite
                    // answers, and this is the screen where confusing them matters most.
                    Text(problem).foregroundStyle(Palette.stateFailed)
                } else if audit.events.isEmpty {
                    Text(
                        audit.isLoading
                            ? String(localized: "Reading…")
                            : String(localized: "Nothing recorded yet.")
                    )
                    .foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(audit.events) { event in
                        row(event)
                    }
                    if audit.canLoadMore {
                        Button(String(localized: "Show older")) {
                            Task { await audit.loadMore { try await state.auditEvents($0) } }
                        }
                        .buttonStyle(XBotButtonStyle())
                        .disabled(audit.isLoading)
                    }
                }
            } header: {
                Text(String(localized: "Recent"))
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
    }

    private func reload() async {
        await audit.load { try await state.auditEvents($0) }
    }

    private func row(_ event: AuditEvent) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack {
                Text(event.eventType).bodyEmphasis()
                Spacer()
                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
            if !event.summary.isEmpty {
                Text(event.summary)
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: Space.xs) {
                if let target = event.targetId {
                    Text(target).captionText().foregroundStyle(Palette.textTertiary)
                }
                // Named rather than left blank: an action nobody took is the deployment acting,
                // which is a different thing from an action somebody took and worth telling apart.
                Text(event.actorUserId ?? String(localized: "xBot"))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.vertical, Space.xxs)
    }
}
