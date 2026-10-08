import SwiftUI

/// A quiet rounded control for the composer: "● Claude Code · Opus ⌄", "✎ Can edit ⌄", "Plan".
/// Used as a Menu's label, or alone as a toggle.
public struct Chip: View {
    let title: String
    var systemImage: String?
    var detail: String?
    var dot: Color?
    var isOn = false
    var showsChevron = false
    @State private var hovering = false

    public init(
        _ title: String, systemImage: String? = nil, detail: String? = nil, dot: Color? = nil,
        isOn: Bool = false, showsChevron: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.dot = dot
        self.isOn = isOn
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            if let dot { Circle().fill(dot).frame(width: Metrics.dot, height: Metrics.dot) }
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
            if let detail { Text(detail).foregroundStyle(isOn ? Palette.accent : Palette.textTertiary) }
            if showsChevron {
                Image(systemName: "chevron.down").imageScale(.small).foregroundStyle(Palette.textTertiary)
            }
        }
        .font(Typography.chip)
        .foregroundStyle(isOn ? Palette.accent : Palette.textSecondary)
        .padding(.horizontal, Space.s)
        .frame(height: Metrics.chipHeight)
        .background(
            isOn ? Palette.accentTint : (hovering ? Palette.hover : .clear),
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: isOn)
    }
}
