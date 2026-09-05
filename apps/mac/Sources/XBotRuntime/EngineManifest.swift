import Foundation

/// Pinned engine image metadata. See `scripts/engine-manifest.template.json`.
public struct EngineManifest: Codable, Sendable, Equatable {
    public let channel: String
    public let version: String
    /// `repository:tag` or `repository@sha256:…` — always pinned, never bare `:latest`.
    public let image: String
    public let size: Int
    public let minimumAppVersion: String
    public let migration: Migration
    public let releaseNotes: String?

    public struct Migration: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let backwardCompatibleWith: Int
    }

    /// The image to run, or nil when the manifest carries no real one.
    ///
    /// `scripts/engine-manifest.template.json` uses an all-zero digest as a placeholder, and a copy
    /// of it reached both `manifests/engine-stable.json` and the app's bundled fallback. Nothing
    /// rejected it — the reference parsed, resolution returned it, and the runtime tried to pull an
    /// image that cannot exist, so the engine never started and the failure read as a pull error
    /// rather than "nothing has been published yet".
    ///
    /// Nil lets resolution fall through to the caller's own fallback, which is the honest answer.
    public var imageReference: ImageReference? {
        guard let reference = ImageReference(parsing: image) else { return nil }
        if let digest = reference.digest, digest.allSatisfy({ $0 == "0" }) { return nil }
        return reference
    }
}

public enum EngineManifestDecoding {
    public static func decode(from data: Data) throws -> EngineManifest {
        try JSONDecoder().decode(EngineManifest.self, from: data)
    }
}
