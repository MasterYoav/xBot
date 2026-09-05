import Foundation
import Testing
@testable import XBotRuntime

@Suite struct ImageReferenceTests {
    @Test func parsesTaggedReference() {
        let reference = ImageReference(parsing: "xbot/engine:1")
        #expect(reference?.repository == "xbot/engine")
        #expect(reference?.tag == "1")
        #expect(reference?.digest == nil)
        #expect(reference?.full == "xbot/engine:1")
    }

    @Test func parsesDigestReference() {
        let digest = "sha256:abc123"
        let reference = ImageReference(parsing: "ghcr.io/masteryoav/xbot-engine@\(digest)")
        #expect(reference?.repository == "ghcr.io/masteryoav/xbot-engine")
        #expect(reference?.digest == "abc123")
        #expect(reference?.tag == nil)
        #expect(reference?.full == "ghcr.io/masteryoav/xbot-engine@sha256:abc123")
    }

    @Test func digestInitializerNormalizesPrefix() {
        let reference = ImageReference(repository: "ghcr.io/org/engine", digest: "deadbeef")
        #expect(reference.full == "ghcr.io/org/engine@sha256:deadbeef")
    }
}

@Suite struct EngineManifestTests {
    private let sample = """
    {
      "channel": "stable",
      "version": "4f84cbe",
      "image": "ghcr.io/masteryoav/xbot-engine@sha256:abc123",
      "size": 3400000000,
      "minimumAppVersion": "1.0.0",
      "migration": { "schemaVersion": 25, "backwardCompatibleWith": 0 },
      "releaseNotes": "https://example.com"
    }
    """

    @Test func decodesManifest() throws {
        let manifest = try EngineManifestDecoding.decode(from: Data(sample.utf8))
        #expect(manifest.channel == "stable")
        #expect(manifest.image == "ghcr.io/masteryoav/xbot-engine@sha256:abc123")
        #expect(manifest.migration.schemaVersion == 25)
        #expect(manifest.imageReference?.full == "ghcr.io/masteryoav/xbot-engine@sha256:abc123")
    }
}

@Suite(.serialized)
struct EngineImageResolverTests {
    @Test func environmentOverrideWins() async {
        setenv("XBOT_ENGINE_IMAGE", "xbot/engine:9", 1)
        defer { unsetenv("XBOT_ENGINE_IMAGE") }

        let resolver = EngineImageResolver(
            manifestURL: URL(string: "https://example.invalid/manifest.json")!,
            session: .shared,
            defaults: UserDefaults(suiteName: "EngineImageResolverTests.override")!,
            bundledManifestData: { nil }
        )

        let resolved = await resolver.resolve(fallback: ImageReference(repository: "xbot/engine", tag: "1"))
        #expect(resolved.full == "xbot/engine:9")
    }

    @Test func usesCachedManifestWhenFetchFails() async throws {
        unsetenv("XBOT_ENGINE_IMAGE")
        let suite = "EngineImageResolverTests.cache"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let cached = EngineManifest(
            channel: "stable",
            version: "1",
            image: "ghcr.io/masteryoav/xbot-engine@sha256:cached",
            size: 1,
            minimumAppVersion: "1.0.0",
            migration: .init(schemaVersion: 1, backwardCompatibleWith: 0),
            releaseNotes: nil
        )
        defaults.set(try JSONEncoder().encode(cached), forKey: "xbot.engine.manifest.json")

        let resolver = EngineImageResolver(
            manifestURL: URL(string: "https://example.invalid/manifest.json")!,
            session: .shared,
            defaults: defaults,
            bundledManifestData: { nil }
        )

        let resolved = await resolver.resolve(fallback: ImageReference(repository: "xbot/engine", tag: "1"))
        #expect(resolved.full == "ghcr.io/masteryoav/xbot-engine@sha256:cached")
    }

    @Test func checkUpdateDetectsNewDigest() async throws {
        let manifest = EngineManifest(
            channel: "stable",
            version: "9",
            image: "ghcr.io/masteryoav/xbot-engine@sha256:newdigest",
            size: 1,
            minimumAppVersion: "1.0.0",
            migration: .init(schemaVersion: 1, backwardCompatibleWith: 0),
            releaseNotes: nil
        )
        let data = try JSONEncoder().encode(manifest)

        let resolver = EngineImageResolver(
            manifestURL: URL(string: "https://example.test/manifest.json")!,
            session: .shared,
            defaults: UserDefaults(suiteName: "EngineImageResolverTests.check")!,
            bundledManifestData: { nil }
        )

        // Stub fetch via cache priming — checkUpdate reads fetch first; use invalid URL and cache.
        let defaults = UserDefaults(suiteName: "EngineImageResolverTests.check")!
        defaults.set(data, forKey: "xbot.engine.manifest.json")

        unsetenv("XBOT_ENGINE_IMAGE")
        let status = await resolver.checkUpdate(
            currentImage: "ghcr.io/masteryoav/xbot-engine@sha256:olddigest",
            appVersion: "1.0.0"
        )
        #expect(status == .updateAvailable(latest: manifest))
    }
}

@Suite struct AppVersionTests {
    @Test func satisfiesMinimum() {
        #expect(AppVersion.satisfies(app: "1.2.0", minimum: "1.0.0"))
        #expect(AppVersion.satisfies(app: "1.0.0", minimum: "1.0.0"))
        #expect(!AppVersion.satisfies(app: "0.9.9", minimum: "1.0.0"))
    }
}

@Suite struct EngineUpdateCheckStoreTests {
    @Test func checksOncePerInterval() {
        let suite = "EngineUpdateCheckStoreTests.interval"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        #expect(EngineUpdateCheckStore.shouldCheck(defaults: defaults))
        EngineUpdateCheckStore.markChecked(now: Date(timeIntervalSince1970: 1_000), defaults: defaults)
        #expect(
            !EngineUpdateCheckStore.shouldCheck(
                now: Date(timeIntervalSince1970: 1_000 + 3_600),
                interval: EngineUpdateCheckStore.checkInterval,
                defaults: defaults
            )
        )
        #expect(
            EngineUpdateCheckStore.shouldCheck(
                now: Date(timeIntervalSince1970: 1_000 + EngineUpdateCheckStore.checkInterval),
                defaults: defaults
            )
        )
    }

    /**
     A template digest is not an image, and must never be resolved as one.

     `scripts/engine-manifest.template.json` carries an all-zero digest as a placeholder, and a copy
     of it was published to `manifests/engine-stable.json` and shipped as the app's bundled
     fallback. Nothing rejected it: the reference parsed, resolution returned it, and the runtime
     tried to pull `ghcr.io/…@sha256:0000…` — an image that cannot exist. The engine could not start
     at all, and the failure surfaced as a pull error rather than as "there is no published image".

     Returning nil lets resolution fall through to the caller's own fallback, which is the honest
     answer when no real image has been published yet.
     */
    @Test func aPlaceholderDigestIsNotAnImageReference() throws {
        let placeholder = """
        {
          "channel": "stable",
          "version": "0.0.0-dev",
          "image": "ghcr.io/masteryoav/xbot-engine@sha256:\(String(repeating: "0", count: 64))",
          "size": 0,
          "minimumAppVersion": "1.0.0",
          "migration": { "schemaVersion": 0, "backwardCompatibleWith": 0 }
        }
        """
        let manifest = try EngineManifestDecoding.decode(from: Data(placeholder.utf8))
        #expect(manifest.imageReference == nil)
    }

    @Test func aRealDigestStillResolves() throws {
        let real = """
        {
          "channel": "stable",
          "version": "9a4c111",
          "image": "ghcr.io/masteryoav/xbot-engine@sha256:0aa44a0d597a4d6fb7aa23f1a7cc70b2f4c0cd33678b367f32bdfdacd766e2d9",
          "size": 4520919161,
          "minimumAppVersion": "1.0.0",
          "migration": { "schemaVersion": 0, "backwardCompatibleWith": 0 }
        }
        """
        let manifest = try EngineManifestDecoding.decode(from: Data(real.utf8))
        #expect(manifest.imageReference != nil)
    }
}
