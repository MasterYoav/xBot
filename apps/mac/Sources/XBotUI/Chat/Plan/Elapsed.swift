import SwiftUI

/// "11s", "1m 4s"; ticking while there is no end.
struct Elapsed: View {
    let start: Date
    let end: Date?

    var body: some View {
        if let end {
            Text(Self.format(end.timeIntervalSince(start)))
        } else {
            TimelineView(.periodic(from: start, by: 1)) { context in
                Text(Self.format(context.date.timeIntervalSince(start)))
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return whole < 60 ? "\(whole)s" : "\(whole / 60)m \(whole % 60)s"
    }

    /// Tool durations keep a tenth: "1.4s".
    static func short(_ seconds: TimeInterval) -> String {
        seconds < 10 ? String(format: "%.1fs", max(0, seconds)) : format(seconds)
    }
}
