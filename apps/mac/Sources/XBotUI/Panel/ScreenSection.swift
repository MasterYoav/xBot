import SwiftUI
import XBotCore
import XBotEngine

/// The live view of the agent's browser.
public struct ScreenSection: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        VStack(spacing: Space.m) {
            frame
            controlRow
        }
        .padding(Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var frame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.elevatedSurface)

            if let frame = state.screenFrame, let image = NSImage(data: frame.imageData) {
                Image(nsImage: image)
                    .resizable()
                    // Aspect-preserving and letterboxed. A stretched screenshot of somebody's
                    // bank is worse than no screenshot: it looks like a bug in their bank.
                    .aspectRatio(contentMode: .fit)
            } else {
                emptyState
            }

            if state.control == .human {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.attention, lineWidth: 2)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .motion(Motion.quick, value: state.control)
    }

    private var emptyState: some View {
        // The reference's shape: a glyph and the agent's own name. Never "No data."
        VStack(spacing: Space.s) {
            Image(systemName: "display")
                .font(.system(size: 28))
                .foregroundStyle(Palette.textTertiary)
            Text(String(localized: "\(state.selectedAgent?.name ?? "This agent")'s screen"))
                .captionText()
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var controlRow: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                state.setControl(state.control == .human ? .agent : .human)
            } label: {
                Text(
                    state.control == .human
                        ? String(localized: "Give control back")
                        : String(localized: "Take control")
                )
                .bodyEmphasis()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s)
                .background(
                    Palette.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                )
            }
            .buttonStyle(XBotButtonStyle())

            if state.control == .human {
                // Say what is happening to the agent, because "refused" and "queued" lead to very
                // different expectations and only one of them is true.
                Text(String(localized: "While you're driving, this agent's actions are refused, not queued."))
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .motion(Motion.quick, value: state.control)
    }
}
