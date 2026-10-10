import Foundation
import XBotBrain

/// A wallpaper drawn in text by one of the agents: one frame, or a short loop of them.
public struct AsciiArt: Codable, Equatable, Sendable {
    public enum Motion: String, CaseIterable, Sendable { case still, animated }

    /// The colour the text is drawn in. The agent picks one that suits the picture.
    public enum Ink: String, Codable, CaseIterable, Sendable { case mint, amber, rose, sky, violet, snow }

    public enum Problem: LocalizedError {
        case nothingDrawn
        case agent(String)
        case noAgent

        public var errorDescription: String? {
            switch self {
            case .nothingDrawn: String(localized: "The agent didn't draw anything usable. Try again.")
            case .agent(let reason): reason
            case .noAgent: String(localized: "That agent isn't installed.")
            }
        }
    }

    public var title: String
    public var frames: [String]
    /// Frames per second, for an animated one.
    public var fps: Double
    public var ink: Ink

    public static let targetColumns = 96
    public static let targetRows = 28
    public static let maxColumns = 160
    public static let maxRows = 60
    public static let maxFrames = 24
    public static let fpsRange: ClosedRange<Double> = 1...12

    public init(title: String, frames: [String], fps: Double, ink: Ink) {
        self.title = title
        self.frames = frames
        self.fps = fps
        self.ink = ink
    }

    public var columns: Int { frames.first?.split(separator: "\n", omittingEmptySubsequences: false).first?.count ?? 0 }
    public var rows: Int { frames.first?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0 }

    /// What the agent answers with.
    public static let schema = #"""
    {"type":"object","additionalProperties":false,"required":["title","ink","fps","frames"],"properties":{
      "title":{"type":"string","description":"A short name for the picture, 1 to 4 words."},
      "ink":{"type":"string","enum":["mint","amber","rose","sky","violet","snow"],"description":"The colour the text is drawn in, to suit the picture."},
      "fps":{"type":"number","description":"Frames per second for an animation, 2 to 10. 1 for a still."},
      "frames":{"type":"array","description":"The picture: one string per frame, lines separated by \\n, every frame the same size.","items":{"type":"string"}}}}
    """#

    /**
     The agent's answer, cleaned up so it always draws: tabs become spaces, escape codes and other
     control characters go, blank lines at the ends go, and every frame is padded to one size (a
     frame that changed size would make the picture jump). A still keeps its first frame.
     */
    public static func parse(_ json: String, motion: Motion) throws -> AsciiArt {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let raw = object["frames"] as? [String] else { throw Problem.nothingDrawn }
        var frames = raw.prefix(motion == .still ? 1 : maxFrames).map(clean)
        frames.removeAll { $0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !frames.isEmpty else { throw Problem.nothingDrawn }
        let width = min(frames.flatMap { $0 }.map(\.count).max() ?? 0, maxColumns)
        let height = min(frames.map(\.count).max() ?? 0, maxRows)
        let padded = frames.map { lines -> String in
            (0..<height).map { row in
                let line = row < lines.count ? String(lines[row].prefix(width)) : ""
                return line + String(repeating: " ", count: width - line.count)
            }.joined(separator: "\n")
        }
        let fps = (object["fps"] as? Double).map { min(max($0, fpsRange.lowerBound), fpsRange.upperBound) } ?? 6
        return AsciiArt(
            title: (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            frames: padded, fps: padded.count == 1 ? 1 : fps,
            ink: (object["ink"] as? String).flatMap(Ink.init(rawValue:)) ?? .mint
        )
    }

    private static func clean(_ frame: String) -> [String] {
        var lines = frame.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { line in
            String(String.UnicodeScalarView(line.replacingOccurrences(of: "\t", with: "    ").unicodeScalars.filter {
                $0.value >= 0x20 && $0.value != 0x7F
            }))
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        return lines
    }

    public static func load(_ url: URL) -> AsciiArt? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AsciiArt.self, from: $0) }
    }
}

/// The prompt xBot writes for the agent: a subject (the person's idea, or one xBot picks), a style,
/// the exact size, and for a loop, how it should move.
public enum AsciiWallpaperPrompt {
    static let subjects = [
        "a quiet mountain range under a starry sky", "ocean waves rolling onto a beach at dusk",
        "a city skyline at night with lit windows", "a forest of tall pines in fog",
        "a lighthouse on a cliff", "a desert with dunes and a big moon", "koi fish in a pond",
        "a spaceship drifting past a ringed planet", "cherry blossoms falling in the wind",
        "a cozy cabin in the snow", "a waterfall in a jungle", "northern lights over a frozen lake",
        "a sleeping cat on a windowsill in the rain", "a hot air balloon over fields",
        "a retro synthwave sun over a grid", "a whale swimming through the deep sea",
        "a field of flowers with butterflies", "a volcano under a cloudy sky",
        "a train crossing a long bridge", "a campfire under the stars", "a jellyfish swarm",
    ]
    static let styles = [
        "fine detail with a dense character ramp (.:-=+*#%@) for shading",
        "bold, clean shapes with lots of empty space", "a woodcut look with strong contrast",
        "soft dithering with dots and colons", "box-drawing and block characters (░▒▓█)",
        "a minimal, calm composition",
    ]
    static let motions = [
        "slow and gentle, like breathing", "steady drifting from left to right",
        "twinkling and flickering", "rippling", "falling softly", "pulsing glow",
    ]

    public static func make(motion: AsciiArt.Motion, idea: String?, using rng: inout some RandomNumberGenerator) -> String {
        let idea = idea?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = (idea?.isEmpty == false ? idea : nil) ?? subjects.randomElement(using: &rng)!
        let style = styles.randomElement(using: &rng)!
        var text = """
            Draw ASCII art to be the wallpaper of a desktop app: \(subject).
            Style: \(style).
            Size: every frame exactly \(AsciiArt.targetRows) lines of exactly \(AsciiArt.targetColumns) characters \
            (pad with spaces). Use only printable characters; no tabs, no colour codes, no code fences.
            It sits behind the app's text and fades out towards the bottom, so put the main subject in the \
            upper two thirds and keep the bottom calm.

            """
        switch motion {
        case .still:
            text += "Give exactly one frame, and set fps to 1."
        case .animated:
            let feel = motions.randomElement(using: &rng)!
            text += """
                Animate it as a seamless loop of 8 to 12 frames: \(feel). Change only the parts that move \
                between frames, and make the last frame lead back into the first. Choose fps between 3 and 8.
                """
        }
        text += "\nPick the ink colour that suits it, and give it a short title. Don't use any tools; just answer."
        return text
    }
}

extension Workspace {
    public struct WallpaperRequest: Sendable {
        public var motion: AsciiArt.Motion
        public var harness: HarnessKind
        public var model: String?
        public var effort: Effort?
        /// What the person would like; nil or empty lets xBot pick.
        public var idea: String?

        public init(motion: AsciiArt.Motion, harness: HarnessKind, model: String?, effort: Effort?, idea: String?) {
            self.motion = motion
            self.harness = harness
            self.model = model
            self.effort = effort
            self.idea = idea
        }
    }

    /// Has the chosen agent draw a wallpaper: xBot writes the prompt, the agent answers to a schema,
    /// read-only, in xBot's own folder. Returns the art and the prompt it was drawn from.
    public func drawWallpaper(_ request: WallpaperRequest) async throws -> (art: AsciiArt, prompt: String) {
        guard let brain = brains[request.harness] else { throw AsciiArt.Problem.noAgent }
        var rng = SystemRandomNumberGenerator()
        let prompt = AsciiWallpaperPrompt.make(motion: request.motion, idea: request.idea, using: &rng)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let turn = TurnRequest(prompt: prompt, directory: inbox, model: request.model, mode: .readOnly,
                               effort: request.effort, schema: AsciiArt.schema)
        var answer: String?
        var failure: String?
        for await event in events(brain, turn, harness: request.harness) {
            switch event {
            case .structured(let json): answer = json
            case .failed(let reason): failure = reason
            default: break
            }
        }
        if let answer { return (try AsciiArt.parse(answer, motion: request.motion), prompt) }
        throw failure.map(AsciiArt.Problem.agent) ?? AsciiArt.Problem.nothingDrawn
    }
}
