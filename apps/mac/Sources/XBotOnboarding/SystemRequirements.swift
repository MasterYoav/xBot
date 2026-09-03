import Foundation

/// macOS, disk, and RAM checks for onboarding Step 2.
public enum SystemRequirements {
    public enum MacOSStatus: Sendable, Equatable {
        case supported
        case unsupported(version: String)
    }

    public struct Result: Sendable, Equatable {
        public var macOS: MacOSStatus
        public var architecture: String
        public var freeDiskGigabytes: Double
        public var physicalMemoryGigabytes: Double

        public var diskSufficient: Bool { freeDiskGigabytes >= 12 }
        public var showsRAMWarning: Bool {
            physicalMemoryGigabytes >= 8 && physicalMemoryGigabytes < 16
        }
    }

    public static func check() -> Result {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let macOS: MacOSStatus =
            version.majorVersion >= 14 ? .supported : .unsupported(version: versionString)

        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif

        let freeBytes = freeDiskSpaceBytes() ?? 0
        let physicalBytes = ProcessInfo.processInfo.physicalMemory

        return Result(
            macOS: macOS,
            architecture: architecture,
            freeDiskGigabytes: Double(freeBytes) / 1_073_741_824,
            physicalMemoryGigabytes: Double(physicalBytes) / 1_073_741_824
        )
    }

    private static func freeDiskSpaceBytes() -> UInt64? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard
            let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return UInt64(capacity)
    }
}
