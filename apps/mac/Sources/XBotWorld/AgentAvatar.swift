import Foundation

// MARK: - AgentAvatar

/// An original pixel-art chibi, as a choice per part. Drawn by `AvatarSprite` in the UI.
public struct AgentAvatar: Codable, Equatable, Hashable, Sendable {
    public var skin = 0
    public var hair = 0
    public var hairColor = 0
    public var eyes = 0
    public var outfit = 0
    public var outfitColor = 0
    public var accessory = 0

    public enum Part: String, CaseIterable, Sendable {
        case skin, hair, hairColor, eyes, outfit, outfitColor, accessory

        /// How many choices the sprite draws for this part.
        public var count: Int {
            switch self {
            case .skin: 6
            case .hair: 9
            case .hairColor: 10
            case .eyes: 6
            case .outfit: 7
            case .outfitColor: 10
            case .accessory: 8
            }
        }

        public var title: String {
            switch self {
            case .skin: String(localized: "Skin")
            case .hair: String(localized: "Hair")
            case .hairColor: String(localized: "Hair colour")
            case .eyes: String(localized: "Eyes")
            case .outfit: String(localized: "Outfit")
            case .outfitColor: String(localized: "Outfit colour")
            case .accessory: String(localized: "Accessory")
            }
        }
    }

    public init(skin: Int = 0, hair: Int = 0, hairColor: Int = 0, eyes: Int = 0, outfit: Int = 0,
                outfitColor: Int = 0, accessory: Int = 0) {
        self.skin = skin
        self.hair = hair
        self.hairColor = hairColor
        self.eyes = eyes
        self.outfit = outfit
        self.outfitColor = outfitColor
        self.accessory = accessory
    }

    public subscript(part: Part) -> Int {
        get {
            switch part {
            case .skin: skin
            case .hair: hair
            case .hairColor: hairColor
            case .eyes: eyes
            case .outfit: outfit
            case .outfitColor: outfitColor
            case .accessory: accessory
            }
        }
        set {
            let value = ((newValue % part.count) + part.count) % part.count
            switch part {
            case .skin: skin = value
            case .hair: hair = value
            case .hairColor: hairColor = value
            case .eyes: eyes = value
            case .outfit: outfit = value
            case .outfitColor: outfitColor = value
            case .accessory: accessory = value
            }
        }
    }

    public mutating func step(_ part: Part, by delta: Int) { self[part] += delta }

    public static func random(using rng: inout some RandomNumberGenerator) -> AgentAvatar {
        var avatar = AgentAvatar()
        for part in Part.allCases { avatar[part] = Int.random(in: 0..<part.count, using: &rng) }
        return avatar
    }

    public static func random() -> AgentAvatar {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }

    enum CodingKeys: String, CodingKey { case skin, hair, hairColor, eyes, outfit, outfitColor, accessory }

    /// Missing parts are the first choice and out-of-range ones wrap, so an avatar saved by another
    /// version of xBot always draws.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for part in Part.allCases {
            let key = CodingKeys(rawValue: part.rawValue)!
            self[part] = (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0
        }
    }
}
