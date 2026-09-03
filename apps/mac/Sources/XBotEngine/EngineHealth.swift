import Foundation

/// What `/health` returns when the engine is ours.
public struct EngineHealth: Sendable, Equatable {
    public var engineVersion: String
    public var schemaVersion: String

    public init(engineVersion: String, schemaVersion: String) {
        self.engineVersion = engineVersion
        self.schemaVersion = schemaVersion
    }
}
