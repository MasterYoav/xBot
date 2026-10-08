import SwiftUI
import XBotCore

/// A year of token activity: a column a week, a square a day, deeper clay for busier days, and
/// the months along the bottom.
struct Heatmap: View {
    let cells: [[HeatCell]]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .top, spacing: Metrics.heatGap) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: Metrics.heatGap) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, cell in square(cell) }
                    }
                }
            }
            HStack(alignment: .top, spacing: Metrics.heatGap) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, week in
                    Text(monthLabel(week) ?? "")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                        .frame(width: Metrics.heatCell, alignment: .leading)
                }
            }
        }
    }

    private func square(_ cell: HeatCell) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(cell.isFuture ? Color.clear : cell.level == 0 ? Palette.inset : Palette.heat[cell.level - 1])
            .frame(width: Metrics.heatCell, height: Metrics.heatCell)
            .help(cell.isFuture ? "" : String(localized: "\(cell.value.formatted()) tokens · \(cell.date.formatted(date: .abbreviated, time: .omitted))"))
    }

    /// The month's name under the week its first day falls in.
    private func monthLabel(_ week: [HeatCell]) -> String? {
        guard let first = week.first(where: { Calendar.current.component(.day, from: $0.date) == 1 }) else { return nil }
        return first.date.formatted(.dateTime.month(.abbreviated))
    }
}
