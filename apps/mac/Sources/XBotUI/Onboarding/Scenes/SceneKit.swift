import SwiftUI
import XBotWorld

// The shared machinery of the onboarding scenes: one clock per scene, easing written as plain
// functions of time, a stage that scales a 720 × 420 composition to the room it's given, and the
// pieces several scenes draw (the crew, a mock xBot window, a speech bubble).
//
// Every scene is a pure function of `SceneTime`: no @State animations, no timers. That is what
// makes a loop seamless, Reduce Motion a single still frame (the clock is simply not run), and the
// motion gate free (a paused TimelineView draws nothing).

// MARK: - The clock

/// Where a scene is in its loop.
struct SceneTime {
    /// Seconds into the loop.
    var t: Double
    /// The wall clock, for the world art (clouds, fish, stars). Frozen under Reduce Motion.
    var date: Date
    /// When the scene appeared: lets a world be drawn at an hour of our choosing (dawn) while its
    /// clouds still drift.
    var origin: Date
    /// Reduce Motion: this is the scene's final frame and nothing moves.
    var still: Bool
    /// The loop's length, for the fade at its seam.
    var loop: Double

    /// 0 → 1 as the loop starts, 1 → 0 just before it repeats, so the seam is a soft dissolve.
    var seam: Double {
        if still { return 1 }
        let fadeIn = Ease.progress(t, 0, SceneMotion.loopFadeIn)
        let fadeOut = 1 - Ease.progress(t, loop - SceneMotion.loopFadeOut, SceneMotion.loopFadeOut)
        return Ease.inOut(min(fadeIn, fadeOut))
    }

    /// 0 → 1 over `beats` beats, starting at beat `start`.
    func beat(_ start: Double, _ beats: Double = 1) -> Double {
        Ease.progress(t, start * SceneMotion.beat, beats * SceneMotion.beat)
    }

    /// True once beat `start` has passed.
    func after(_ start: Double) -> Bool { t >= start * SceneMotion.beat }

    /// The same moment, at a given hour of the day: the village's sky follows the clock.
    func worldDate(hour: Double) -> Date {
        let day = Calendar.current.startOfDay(for: origin)
        return day.addingTimeInterval(hour * 3600 + date.timeIntervalSince(origin))
    }
}

/// Runs a scene: a TimelineView at a modest frame rate that stops while the app is in the
/// background (`motionPaused`) and never starts under Reduce Motion, where the scene's final
/// frame is drawn once instead. After a pause it picks up where it was rather than jumping.
struct SceneClock<Content: View>: View {
    /// Seconds per loop.
    let loop: Double
    /// The frame shown under Reduce Motion: the scene's resolved, final composition.
    let finalFrame: Double
    var interval: Double = SceneMotion.frameInterval
    @ViewBuilder var content: (SceneTime) -> Content

    @Environment(\.motionPaused) private var motionPaused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var pausedAt: Date?

    #if DEBUG
    @Environment(\.sceneDebugTime) private var debugTime
    #endif

    var body: some View {
        #if DEBUG
        if let debugTime {
            // A fixed moment, for rendering a scene to a picture (see `SceneDebugTime`).
            let origin = Date(timeIntervalSinceReferenceDate: 812_000_000)
            let t = debugTime.still ? finalFrame : debugTime.t
            content(SceneTime(t: t, date: origin.addingTimeInterval(t), origin: origin, still: debugTime.still, loop: loop))
        } else {
            running
        }
        #else
        running
        #endif
    }

    private var running: some View {
        TimelineView(.animation(minimumInterval: interval, paused: motionPaused || reduceMotion)) { context in
            if reduceMotion {
                content(SceneTime(t: finalFrame, date: start, origin: start, still: true, loop: loop))
            } else {
                let now = pausedAt ?? context.date
                let elapsed = max(0, now.timeIntervalSince(start))
                content(SceneTime(t: elapsed.truncatingRemainder(dividingBy: loop), date: now, origin: start,
                                  still: false, loop: loop))
            }
        }
        .onAppear {
            start = .now
            pausedAt = motionPaused ? .now : nil
        }
        .onChange(of: motionPaused) { _, paused in
            if paused {
                pausedAt = .now
            } else if let pausedAt {
                start = start.addingTimeInterval(Date.now.timeIntervalSince(pausedAt))
                self.pausedAt = nil
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
/// Debug only: draw a scene at one moment of its loop (or its Reduce Motion frame) instead of
/// running its clock, so it can be rendered to a picture and looked at frame by frame.
struct SceneDebugTime: Equatable {
    var t: Double
    var still = false
}

extension EnvironmentValues {
    @Entry var sceneDebugTime: SceneDebugTime? = nil
}
#endif

// MARK: - Easing

/// Curves as functions of a 0…1 progress. Decoration only: nothing here can be grabbed, which is
/// the one place the design system allows fixed curves.
enum Ease {
    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// 0 → 1 over `[start, start + duration]`.
    static func progress(_ t: Double, _ start: Double, _ duration: Double) -> Double {
        clamp((t - start) / max(duration, 0.0001))
    }

    static func out(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    static func `in`(_ x: Double) -> Double { pow(clamp(x), 3) }
    static func inOut(_ x: Double) -> Double {
        let x = clamp(x)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// A spring's settle, sampled: critically damped at `bounce` 0, a little overshoot above it.
    /// Reaches exactly 1 at x = 1 so a held frame never shimmers.
    static func spring(_ x: Double, bounce: Double = 0) -> Double {
        let x = clamp(x)
        guard x < 1 else { return 1 }
        let decay = 7.0
        if bounce <= 0 { return 1 - exp(-decay * x) * (1 + decay * x) }
        let omega = 50 * bounce
        return 1 - exp(-decay * x) * cos(omega * x)
    }

    /// A single hop: up and back down, 0 at both ends.
    static func hop(_ x: Double) -> Double {
        let x = clamp(x)
        return 4 * x * (1 - x)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ x: Double) -> CGFloat { a + (b - a) * CGFloat(x) }
}

// MARK: - The stage

/// Composes a scene on the 720 × 420 design canvas and scales it, uniformly, to the room it is
/// given. The canvas grows along the longer side (it never letterboxes), so `content` receives the
/// design-space size it actually has: at least 720 × 420, wider or taller to match the room.
struct SceneStage<Content: View>: View {
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { geometry in
            let room = geometry.size
            let canvas = SceneMetrics.canvas
            let scale = max(0.01, min(room.width / canvas.width, room.height / canvas.height))
            let design = CGSize(width: room.width / scale, height: room.height / scale)
            content(design)
                .frame(width: design.width, height: design.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: room.width, height: room.height, alignment: .topLeading)
                // A scene never draws over the controls placed around it.
                .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// A world scene's frame: the picture clipped to soft corners with a hairline, so a world reads as
/// a window onto it rather than a background.
struct WorldFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: SceneMetrics.frameRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SceneMetrics.frameRadius, style: .continuous)
                .strokeBorder(Palette.hairline))
    }
}

/// Behind the floating mock windows: a faint pool of the accent, so the window sits in light.
struct AmbientLight: View {
    var body: some View {
        RadialGradient(colors: [ScenePalette.ambient, .clear], center: .center, startRadius: 0,
                       endRadius: SceneMetrics.canvas.width * 0.55)
    }
}

// MARK: - The crew

/// The founding crew's looks, as `Agent.foundingCrew` seeds them (XBotCore keeps that list
/// internal), plus the CTO the crew scene hires. Keep these in step with Agent.swift.
enum SceneCrew {
    struct Member {
        let name: String
        let avatar: AgentAvatar
        let seed: Int
        var crown = false
    }

    static let headMaster = Member(
        name: "HeadMaster",
        avatar: AgentAvatar(skin: 1, hair: 6, hairColor: 8, eyes: 2, outfit: 5, outfitColor: 7, accessory: 4),
        seed: 11, crown: true)
    static let forge = Member(
        name: "Forge", avatar: AgentAvatar(skin: 3, hair: 2, hairColor: 2, eyes: 0, outfit: 2, outfitColor: 1, accessory: 2),
        seed: 23)
    static let hawk = Member(
        name: "Hawk", avatar: AgentAvatar(skin: 0, hair: 4, hairColor: 0, eyes: 3, outfit: 3, outfitColor: 4, accessory: 1),
        seed: 37)
    static let quill = Member(
        name: "Quill", avatar: AgentAvatar(skin: 2, hair: 7, hairColor: 5, eyes: 4, outfit: 1, outfitColor: 3, accessory: 6),
        seed: 41)
    static let cto = Member(
        name: String(localized: "CTO"),
        avatar: AgentAvatar(skin: 4, hair: 1, hairColor: 1, eyes: 1, outfit: 5, outfitColor: 5, accessory: 3),
        seed: 53)

    static let founders = [headMaster, forge, hawk, quill]
}

/// A crew member drawn with the real sprite, its feet at the bottom of a fixed box so scenes can
/// place people by where they stand.
struct ScenePerson: View {
    let member: SceneCrew.Member
    let date: Date
    var legs: AvatarSprite.Legs = .stand
    /// 1 facing right, -1 facing left.
    var facing: Double = 1
    var pixel: CGFloat = SceneMetrics.crewPixel
    var talking = false
    var nameTag = true

    /// The box the sprite stands in: comfortably larger than a 16 × 24 sprite.
    static func box(_ pixel: CGFloat) -> CGSize { CGSize(width: 26 * pixel, height: 28 * pixel) }

    var body: some View {
        let frame = LivingAvatar.frame(at: date, seed: member.seed, legs: legs, talking: talking, headOnly: false)
        let box = Self.box(pixel)
        AvatarSprite(avatar: member.avatar, frame: frame, pixel: pixel)
            .scaleEffect(x: facing, y: 1)
            .overlay(alignment: .bottom) {
                if nameTag {
                    SceneNameTag(name: member.name, crown: member.crown)
                        .fixedSize()
                        .offset(y: 4 * pixel + Space.xs)
                }
            }
            .frame(width: box.width, height: box.height, alignment: .bottom)
    }
}

extension View {
    /// Places a `ScenePerson` (or anything in its box) so their feet are at `feet`.
    func standing(at x: CGFloat, feet: CGFloat, pixel: CGFloat = SceneMetrics.crewPixel) -> some View {
        position(x: x, y: feet - ScenePerson.box(pixel).height / 2)
    }
}

/// The world's name tag: white on a dark plate, a crown for HeadMaster. World art, so it keeps
/// the sprites' outline ink rather than a UI colour.
struct SceneNameTag: View {
    let name: String
    var crown = false

    var body: some View {
        HStack(spacing: Space.xxs + 1) {
            if crown { Text(verbatim: "♛").foregroundStyle(AvatarPalette.gold) }
            Text(verbatim: name)
        }
        .font(SceneType.nameTag)
        .foregroundStyle(AvatarPalette.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(RoundedRectangle(cornerRadius: 3).fill(AvatarPalette.outline.opacity(0.72)))
    }
}

/// MapleStory's chat balloon: white, pixel-bordered, a little tail.
struct SceneBubble: View {
    let text: String
    var tail = true

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(SceneType.balloon)
                .foregroundStyle(AvatarPalette.outline)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Rectangle().fill(AvatarPalette.white))
                .overlay(Rectangle().strokeBorder(AvatarPalette.outline, lineWidth: 1.5))
            if tail {
                Path { p in
                    p.move(to: .zero); p.addLine(to: CGPoint(x: 8, y: 0)); p.addLine(to: CGPoint(x: 4, y: 5)); p.closeSubpath()
                }
                .fill(AvatarPalette.outline)
                .frame(width: 8, height: 5)
            }
        }
        .shadow(color: AvatarPalette.outline.opacity(0.18), radius: 0, x: 2, y: 2)
        .fixedSize()
    }
}

// MARK: - A mock xBot window

/// The stylised xBot window the chat, plan and inspector scenes play in: the real surfaces and
/// hairlines, traffic lights, and a title bar holding whatever the scene puts there.
struct MockWindow<Bar: View, Content: View>: View {
    var size: CGSize = SceneMetrics.mockWindow
    @ViewBuilder var bar: () -> Bar
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                HStack(spacing: Space.s - 1) {
                    ForEach([Palette.failure, Palette.warning, Palette.success].indices, id: \.self) { i in
                        Circle()
                            .fill([Palette.failure, Palette.warning, Palette.success][i].opacity(0.85))
                            .frame(width: SceneMetrics.trafficLight, height: SceneMetrics.trafficLight)
                    }
                }
                .padding(.trailing, Space.s)
                bar()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m)
            .frame(height: Metrics.titleBar)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .background(Palette.window)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.hairline))
        .floatingShadow()
    }
}

/// A line of text that isn't there yet: a rounded bar the width of the words it stands for.
struct GhostLine: View {
    var width: CGFloat
    var color: Color = Palette.hover
    var height: CGFloat = Space.s

    var body: some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}

/// The first `count` words of `text`, for replies that stream in.
func words(_ text: String, _ count: Int) -> String {
    text.split(separator: " ", omittingEmptySubsequences: true).prefix(max(0, count)).joined(separator: " ")
}

// MARK: - Small shared pieces

/// Something arriving: it rises a little and fades in.
struct Arrive: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(Ease.out(progress))
            .offset(y: Ease.lerp(SceneMotion.rise * 0.6, 0, Ease.out(progress)))
    }
}

/// The shadow ink for objects in the scenes (a falling folder, a lifted card): the same black the
/// design system's depths (`cardShadow`, `floatingShadow`) use.
enum SceneShadow {
    static let ink = Color.black
}

/// A tick, drawn so it can be traced in with `trim`.
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return p
    }
}
