import Foundation

/// What the engine is costing this Mac right now.
///
/// docs/07: "Settings → Advanced shows current memory and disk use … A user who thinks the app is
/// heavy should be able to see whether it is." The container is the heaviest thing xBot puts on a
/// machine — Postgres, the engine, a Chromium — and before this nothing in the app could say how
/// heavy.
public struct EngineResourceUsage: Sendable, Equatable {
    public let memoryBytes: UInt64
    /// The container's cap, when Docker reports one.
    public let memoryLimitBytes: UInt64?
    /// Conversations, files and browser profiles on disk. Nil when it could not be measured.
    public let diskBytes: UInt64?

    public init(memoryBytes: UInt64, memoryLimitBytes: UInt64?, diskBytes: UInt64?) {
        self.memoryBytes = memoryBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.diskBytes = diskBytes
    }
}

/// Docker's human-readable sizes, read back into bytes.
///
/// Two unit systems, about 7% apart a gigabyte: `docker stats` reports memory in binary units
/// (`65.09MiB / 15.66GiB`) and `docker system df` reports sizes in decimal ones (`49.82MB`). A parser
/// that treated `MB` and `MiB` alike would be wrong on every figure it showed.
public enum DockerSize {
    public static func bytes(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let split = trimmed.firstIndex(where: { $0.isLetter }) else {
            return Double(trimmed).map { UInt64($0) }
        }
        guard let value = Double(trimmed[..<split].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let multiplier: Double
        switch trimmed[split...].lowercased() {
        case "b": multiplier = 1
        case "kb": multiplier = 1_000
        case "mb": multiplier = 1_000_000
        case "gb": multiplier = 1_000_000_000
        case "tb": multiplier = 1_000_000_000_000
        case "kib": multiplier = 1_024
        case "mib": multiplier = 1_048_576
        case "gib": multiplier = 1_073_741_824
        case "tib": multiplier = 1_099_511_627_776
        default: return nil
        }
        return UInt64(value * multiplier)
    }

    /// `"65.09MiB / 15.66GiB"` → used and limit.
    public static func memoryUsage(_ text: String) -> (used: UInt64, limit: UInt64?)? {
        let parts = text.split(separator: "/").map(String.init)
        guard let first = parts.first, let used = bytes(first) else { return nil }
        return (used, parts.count > 1 ? bytes(parts[1]) : nil)
    }

    /// `du -sk` output — one `<kilobytes>\t<path>` line per path — summed into bytes.
    public static func duKilobytesTotal(_ output: String) -> UInt64? {
        let values = output.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.flatMap { UInt64($0) }
        }
        return values.isEmpty ? nil : values.reduce(0, +) * 1_024
    }
}
