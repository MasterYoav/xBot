import Foundation

/// How hard the agent thinks. Five stops are the CLIs' own levels; Galaxy is the most each can do:
/// Claude Code at max on its strongest model, Codex at "ultra" on a model that reasons that far.
public enum Effort: String, Codable, CaseIterable, Sendable {
    case low, medium, high, extra, max, galaxy

    /// Slider labels; product vocabulary from the design, so not sentences.
    public var title: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .extra: String(localized: "Extra")
        case .max: String(localized: "Max")
        case .galaxy: String(localized: "Galaxy")
        }
    }

    /// From a CLI's own level name; levels below Low read as Low.
    public init?(cliValue: String) {
        switch cliValue {
        case "none", "minimal", "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        case "xhigh": self = .extra
        case "max": self = .max
        case "ultra": self = .galaxy
        default: return nil
        }
    }

    /// Claude Code's `--effort` value. It has no level past max; Galaxy adds the model instead.
    var claudeValue: String {
        switch self {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .extra: "xhigh"
        case .max, .galaxy: "max"
        }
    }

    /// Codex's `model_reasoning_effort`.
    var codexValue: String {
        switch self {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .extra: "xhigh"
        case .max: "max"
        case .galaxy: "ultra"
        }
    }
}

/// A model an agent offers, with the reasoning it supports.
public struct ModelOption: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var efforts: [Effort]
    /// The level the agent itself recommends for this model, when it says.
    public var recommended: Effort?

    public var supportsGalaxy: Bool { efforts.contains(.galaxy) }

    public init(id: String, name: String, efforts: [Effort], recommended: Effort? = nil) {
        self.id = id
        self.name = name
        self.efforts = efforts
        self.recommended = recommended
    }
}

/// Codex's models, from the cache Codex keeps of what the account can use.
public enum CodexModels {
    public static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/models_cache.json")
    }

    /// Listed models, in Codex's own order; empty when the cache is missing or unreadable.
    public static func read(from url: URL = cacheURL) -> [ModelOption] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models
            .filter { ($0["visibility"] as? String) == "list" }
            .sorted { ($0["priority"] as? Int ?? .max) < ($1["priority"] as? Int ?? .max) }
            .compactMap { model in
                guard let slug = model["slug"] as? String else { return nil }
                let levels = (model["supported_reasoning_levels"] as? [[String: Any]] ?? [])
                    .compactMap { ($0["effort"] as? String).flatMap(Effort.init(cliValue:)) }
                var unique: [Effort] = []
                for level in levels where !unique.contains(level) { unique.append(level) }
                return ModelOption(
                    id: slug,
                    name: model["display_name"] as? String ?? slug,
                    efforts: unique,
                    recommended: (model["default_reasoning_level"] as? String).flatMap(Effort.init(cliValue:))
                )
            }
    }

    /// The model a turn should use: the chosen one, unless Galaxy needs one that reasons at "ultra".
    public static func model(for effort: Effort?, chosen: String?, in models: [ModelOption]) -> String? {
        guard effort == .galaxy, !models.isEmpty else { return chosen }
        if let chosen, models.first(where: { $0.id == chosen })?.supportsGalaxy == true { return chosen }
        return models.first(where: \.supportsGalaxy)?.id ?? chosen
    }
}
