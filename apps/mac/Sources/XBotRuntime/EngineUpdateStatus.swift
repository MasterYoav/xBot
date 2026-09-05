import Foundation

public enum EngineUpdateStatus: Sendable, Equatable {
    case upToDate
    case updateAvailable(latest: EngineManifest)
    case appTooOld(latest: EngineManifest)
    case unreachable

    public var sentence: String {
        switch self {
        case .upToDate:
            String(localized: "You're on the latest engine.")
        case .updateAvailable(let latest):
            String(localized: "Engine \(latest.version) is available.")
        case .appTooOld(let latest):
            String(
                localized:
                    "Engine \(latest.version) needs xBot \(latest.minimumAppVersion) or newer."
            )
        case .unreachable:
            String(localized: "Couldn't reach the update server.")
        }
    }

    public var installableImage: ImageReference? {
        if case .updateAvailable(let latest) = self { return latest.imageReference }
        return nil
    }
}
