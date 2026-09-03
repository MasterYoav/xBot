import Foundation

/// Chooses which engine image to pull before each start.
///
/// Resolution order:
/// 1. `XBOT_ENGINE_IMAGE` environment override (development)
/// 2. Fresh manifest from `manifestURL`
/// 3. Cached manifest from the previous successful fetch
/// 4. Bundled fallback manifest shipped with the app
/// 5. The caller's fallback (`xbot/engine:1` for local builds)
public actor EngineImageResolver {
    public static let defaultManifestURL = URL(
        string: "https://raw.githubusercontent.com/MasterYoav/xBot/master/manifests/engine-stable.json"
    )!

    private let manifestURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let bundledManifestData: @Sendable () -> Data?

    private static let cachedManifestKey = "xbot.engine.manifest.json"

    public init(
        manifestURL: URL? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        bundledManifestData: (@Sendable () -> Data?)? = nil
    ) {
        self.manifestURL = manifestURL ?? Self.defaultManifestURL
        self.session = session
        self.defaults = defaults
        self.bundledManifestData = bundledManifestData ?? { Self.loadBundledManifest() }
    }

    public func resolve(fallback: ImageReference) async -> ImageReference {
        if let override = ProcessInfo.processInfo.environment["XBOT_ENGINE_IMAGE"],
           let reference = ImageReference(parsing: override) {
            return reference
        }

        if let manifest = await fetchManifest(from: manifestURL),
           let reference = manifest.imageReference,
           AppVersion.satisfies(app: Bundle.main.appMarketingVersion, minimum: manifest.minimumAppVersion)
        {
            cache(manifest)
            return reference
        }

        if let cached = loadCachedManifest(), let reference = cached.imageReference {
            return reference
        }

        if let bundled = bundledManifestData(),
           let manifest = try? EngineManifestDecoding.decode(from: bundled),
           let reference = manifest.imageReference {
            return reference
        }

        return fallback
    }

    /// Compare the running image against the published manifest.
    public func checkUpdate(currentImage: String?, appVersion: String) async -> EngineUpdateStatus {
        guard let manifest = await fetchManifest(from: manifestURL) else {
            if let cached = loadCachedManifest() {
                return Self.compare(manifest: cached, currentImage: currentImage, appVersion: appVersion)
            }
            return .unreachable
        }
        cache(manifest)
        return Self.compare(manifest: manifest, currentImage: currentImage, appVersion: appVersion)
    }

    private static func compare(
        manifest: EngineManifest,
        currentImage: String?,
        appVersion: String
    ) -> EngineUpdateStatus {
        if !AppVersion.satisfies(app: appVersion, minimum: manifest.minimumAppVersion) {
            return .appTooOld(latest: manifest)
        }
        guard let latest = manifest.imageReference?.full else { return .unreachable }
        if currentImage == latest { return .upToDate }
        return .updateAvailable(latest: manifest)
    }

    private func fetchManifest(from url: URL) async -> EngineManifest? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try EngineManifestDecoding.decode(from: data)
        } catch {
            return nil
        }
    }

    private func cache(_ manifest: EngineManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        defaults.set(data, forKey: Self.cachedManifestKey)
    }

    private func loadCachedManifest() -> EngineManifest? {
        guard let data = defaults.data(forKey: Self.cachedManifestKey) else { return nil }
        return try? EngineManifestDecoding.decode(from: data)
    }

    private static func loadBundledManifest() -> Data? {
        guard let url = Bundle.main.url(forResource: "engine-manifest-fallback", withExtension: "json")
        else { return nil }
        return try? Data(contentsOf: url)
    }
}

extension Bundle {
    /// `CFBundleShortVersionString`, or `dev` when running from SwiftPM.
    var appMarketingVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
