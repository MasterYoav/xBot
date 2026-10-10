import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@Suite struct AsciiArtTests {
    func json(_ frames: [String], fps: Double = 6, ink: String = "mint") -> String {
        let object: [String: Any] = ["title": "Rain", "ink": ink, "fps": fps, "frames": frames]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// Every frame the same size, so the picture doesn't jump between frames.
    @Test func framesArePaddedToOneSize() throws {
        let art = try AsciiArt.parse(json(["ab\ncdef", "x"]), motion: .animated)
        #expect(art.frames == ["ab  \ncdef", "x   \n    "])
        #expect(art.columns == 4 && art.rows == 2)
    }

    @Test func aStillKeepsOneFrame() throws {
        let art = try AsciiArt.parse(json(["one", "two"]), motion: .still)
        #expect(art.frames == ["one"])
    }

    @Test func tabsTrailingBlankLinesAndControlCharactersAreCleaned() throws {
        let art = try AsciiArt.parse(json(["a\tb\u{1B}[31m\n\n\n"]), motion: .still)
        #expect(art.frames == ["a    b[31m"])
    }

    @Test func speedAndSizeAreKeptSensible() throws {
        let wide = String(repeating: "#", count: 500)
        let art = try AsciiArt.parse(json([wide, "#"], fps: 400), motion: .animated)
        #expect(art.fps == AsciiArt.fpsRange.upperBound)
        #expect(art.columns == AsciiArt.maxColumns)
    }

    @Test func anUnknownInkIsTheDefault() throws {
        #expect(try AsciiArt.parse(json(["x"], ink: "plaid"), motion: .still).ink == .mint)
    }

    /// Recorded from Claude Code (Haiku, low) for xBot's prompt, as ClaudeStream re-encodes it.
    @Test func aRealAnswerParses() throws {
        let url = try #require(Bundle.module.url(forResource: "ascii-haiku-answer", withExtension: "json", subdirectory: "Fixtures"))
        let art = try AsciiArt.parse(String(contentsOf: url, encoding: .utf8), motion: .animated)
        #expect(art.frames.count == 8 && art.fps == 5 && art.title == "Koi Ripple")
    }

    @Test func nothingDrawnIsAnError() {
        #expect(throws: AsciiArt.Problem.self) { try AsciiArt.parse(json(["  \n "]), motion: .still) }
        #expect(throws: AsciiArt.Problem.self) { try AsciiArt.parse("not json", motion: .still) }
    }
}

@Suite struct AsciiPromptTests {
    @Test func xBotPicksTheSubjectWhenThePersonDoesnt() {
        var rng = SeededRandom(seed: 7)
        let prompt = AsciiWallpaperPrompt.make(motion: .still, idea: nil, using: &rng)
        #expect(AsciiWallpaperPrompt.subjects.contains { prompt.contains($0) })
        #expect(prompt.contains("\(AsciiArt.targetColumns)") && prompt.contains("\(AsciiArt.targetRows)"))
        #expect(prompt.contains("exactly one frame"))
    }

    @Test func thePersonsIdeaIsUsedAndAnimationAsksForALoop() {
        var rng = SeededRandom(seed: 1)
        let prompt = AsciiWallpaperPrompt.make(motion: .animated, idea: "a lighthouse in a storm", using: &rng)
        #expect(prompt.contains("a lighthouse in a storm"))
        #expect(prompt.contains("loop"))
    }

    /// The randomizer: two goes rarely ask for the same picture.
    @Test func promptsVary() {
        var rng = SeededRandom(seed: 3)
        let prompts = Set((0..<10).map { _ in AsciiWallpaperPrompt.make(motion: .still, idea: nil, using: &rng) })
        #expect(prompts.count > 5)
    }
}

@MainActor @Suite struct AsciiWallpaperGenerationTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    @Test func theChosenModelAndEffortDrawItReadOnlyWithTheSchema() async throws {
        let answer = #"{"title":"Stars","ink":"sky","fps":4,"frames":["* .","  *"]}"#
        let brain = ScriptedBrain([.structured(answer), .done])
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        let result = try await w.drawWallpaper(.init(motion: .animated, harness: .claude, model: "haiku", effort: .low, idea: nil))
        #expect(result.art.title == "Stars" && result.art.frames.count == 2 && result.art.ink == .sky)
        let request = try #require(brain.requests.withLock { $0.last })
        #expect(request.model == "haiku" && request.effort == .low && request.mode == .readOnly)
        #expect(request.schema == AsciiArt.schema)
        #expect(request.prompt == result.prompt)
    }

    @Test func theAgentsFailureIsReported() async throws {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.failed("usage limit")])] })
        await w.refreshHarnesses()
        await #expect(throws: AsciiArt.Problem.self) {
            try await w.drawWallpaper(.init(motion: .still, harness: .claude, model: nil, effort: nil, idea: nil))
        }
    }
}

@MainActor @Suite struct AsciiAppearanceTests {
    @Test func aDrawnWallpaperIsSavedAndComesBack() throws {
        let defaults = UserDefaults(suiteName: "ascii-\(UUID().uuidString)")!
        let folder = FileManager.default.temporaryDirectory.appending(path: "appearance-\(UUID().uuidString)")
        let appearance = Appearance(defaults: defaults, folder: folder, installedFamilies: { [] })
        let art = AsciiArt(title: "Moon", frames: ["( )"], fps: 1, ink: .amber)
        try appearance.useAscii(art)
        guard case .ascii(let url) = appearance.wallpaper else { Issue.record("not ascii"); return }
        #expect(AsciiArt.load(url) == art)
        let again = Appearance(defaults: defaults, folder: folder, installedFamilies: { [] })
        #expect(again.wallpaper == appearance.wallpaper)
    }
}

/// xorshift, so prompt tests are repeatable.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
