import Testing
@testable import XBotCore
@testable import XBotOnboarding

struct SystemRequirementsTests {
    @Test func macOSVersionIsReported() {
        let result = SystemRequirements.check()
        #expect(result.architecture == "arm64" || result.architecture == "x86_64")
        #expect(result.physicalMemoryGigabytes > 0)
    }

    @Test func diskThresholdIsTwelveGigabytes() {
        let result = SystemRequirements.Result(
            macOS: .supported,
            architecture: "arm64",
            freeDiskGigabytes: 11.9,
            physicalMemoryGigabytes: 32
        )
        #expect(result.diskSufficient == false)

        let ok = SystemRequirements.Result(
            macOS: .supported,
            architecture: "arm64",
            freeDiskGigabytes: 12,
            physicalMemoryGigabytes: 32
        )
        #expect(ok.diskSufficient)
    }

    @Test func ramWarningOnlyBetweenEightAndSixteenGigabytes() {
        let warn = SystemRequirements.Result(
            macOS: .supported,
            architecture: "arm64",
            freeDiskGigabytes: 100,
            physicalMemoryGigabytes: 12
        )
        #expect(warn.showsRAMWarning)

        let silent = SystemRequirements.Result(
            macOS: .supported,
            architecture: "arm64",
            freeDiskGigabytes: 100,
            physicalMemoryGigabytes: 16
        )
        #expect(!silent.showsRAMWarning)
    }
}

struct OnboardingVersionTests {
    @Test func resetAndComplete() {
        defer { OnboardingVersion.reset() }
        OnboardingVersion.reset()
        #expect(!OnboardingVersion.isComplete)
        OnboardingVersion.markComplete()
        #expect(OnboardingVersion.isComplete)
    }
}
