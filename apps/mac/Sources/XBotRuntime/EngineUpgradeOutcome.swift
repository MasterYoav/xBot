import Foundation

/// Result of replacing the running engine container with a newer image.
public enum EngineUpgradeOutcome: Sendable, Equatable {
    case succeeded
    /// The new image failed; the previous image is running again on the same volumes.
    case rolledBack
    /// Neither the new nor the previous image could be brought up.
    case failed

    public var sentence: String {
        switch self {
        case .succeeded:
            String(localized: "Engine update installed.")
        case .rolledBack:
            String(
                localized:
                    "The update didn't start correctly. Your previous engine is running again."
            )
        case .failed:
            String(
                localized:
                    "The update failed and the engine couldn't be restored. Try restarting from General settings."
            )
        }
    }
}
