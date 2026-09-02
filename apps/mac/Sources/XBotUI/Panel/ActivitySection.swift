import SwiftUI
import XBotCore
import XBotEngine

/// What the agent did away from the browser. Newest first, monospaced.
public struct ActivitySection: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        PanelSectionBody(String(localized: "Activity")) {
            if state.activity.isEmpty {
                Text(String(localized: "Nothing yet. Commands, files, and pages will show up here."))
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(state.activity) { entry in
                    ActivityRow(entry: entry)
                }
            }

            Divider().overlay(Palette.separator).padding(.vertical, Space.xs)

            // Be precise about what this is. Upstream is, and a user who thinks this is the record
            // will one day go looking for something that was never kept here.
            Text(String(localized: "This is held for the open conversation and clears on reload. The permanent record is the audit trail."))
                .captionText()
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.s) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                Text(entry.summary)
                    .font(Typography.mono)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            if let detail = entry.detail {
                Text(detail)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(3)
                    .padding(.leading, Space.l)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var symbol: String {
        switch entry.kind {
        case .command(let code): code == 0 ? "checkmark.circle" : "xmark.circle"
        case .fileRead: "doc"
        case .fileWrite: "square.and.pencil"
        case .navigate: "safari"
        }
    }

    private var tint: Color {
        if case .command(let code) = entry.kind, code != 0 { return Palette.stateFailed }
        return Palette.textSecondary
    }
}
