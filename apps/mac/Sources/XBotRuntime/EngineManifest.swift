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

    public var imageReference: ImageReference? { ImageReference(parsing: image) }
}

public enum EngineManifestDecoding {
    public static func decode(from data: Data) throws -> EngineManifest {
        try JSONDecoder().decode(EngineManifest.self, from: data)
    }
}
