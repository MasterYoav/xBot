import AppKit
import SwiftUI
import XBotCore

/// The picture behind the agent's space: from the top, fading into the window by about the middle.
/// Full strength on Home; softer behind a conversation so the text stays the thing you read.
public struct Backdrop: View {
    public enum Strength: Sendable {
        case home, chat

        var opacity: Double {
            switch self {
            case .home: 1
            case .chat: 0.38
            }
        }
    }

    let strength: Strength
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(_ strength: Strength) { self.strength = strength }

    static let fade = LinearGradient(
        stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: 0.3),
            .init(color: .black.opacity(0.55), location: 0.62),
            .init(color: .clear, location: 1),
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let sunset: NSImage? = Bundle.module.url(forResource: "sunset", withExtension: "jpg")
        .flatMap(NSImage.init(contentsOf:))

    /// Settings › Appearance › Wallpaper. Nil draws nothing: the window's own colour.
    @MainActor static func image(for wallpaper: Appearance.Wallpaper) -> NSImage? {
        switch wallpaper {
        case .sunset: sunset
        case .none, .ascii: nil
        case .custom(let url): PictureCache.image(at: url)
        case .desktop:
            NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }.flatMap(PictureCache.image(at:))
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            if case .ascii(let url) = Appearance.shared.wallpaper, !reduceTransparency,
               let art = AsciiCache.art(at: url, revision: Appearance.shared.asciiRevision) {
                AsciiArtView(art: art)
                    .frame(width: geometry.size.width, height: geometry.size.height * Metrics.backdropHeight, alignment: .top)
                    .clipped()
                    .mask(Self.fade)
                    .opacity(strength.opacity * (scheme == .dark ? 0.8 : 0.6))
            } else if let image = Self.image(for: Appearance.shared.wallpaper), !reduceTransparency {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height * Metrics.backdropHeight, alignment: .top)
                    .clipped()
                    // Dark mode dims it: a bright picture at full strength would glare.
                    .overlay(Color.black.opacity(scheme == .dark ? 0.42 : 0))
                    .mask(Self.fade)
                    .opacity(strength.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Pictures read from disk once each. A wallpaper is drawn on every layout pass, and decoding a
/// full-size photo each time made resizing the window stutter.
@MainActor
enum PictureCache {
    private static var images: [URL: NSImage] = [:]

    static func image(at url: URL) -> NSImage? {
        if let image = images[url] { return image }
        // A folder (a rotating desktop picture set) is not a picture.
        guard let image = NSImage(contentsOf: url) else { return nil }
        images[url] = image
        return image
    }

    /// A newly chosen custom picture keeps the same file name, so the old copy must go.
    static func forget(_ url: URL) { images[url] = nil }
}

/// Drawn art read from disk once per save.
@MainActor
enum AsciiCache {
    private static var cached: (URL, Int, AsciiArt)?

    static func art(at url: URL, revision: Int) -> AsciiArt? {
        if let cached, cached.0 == url, cached.1 == revision { return cached.2 }
        guard let art = AsciiArt.load(url) else { return nil }
        cached = (url, revision, art)
        return art
    }
}

/// Text art filling the width it's given, top-aligned, its frames played in a loop. Reduce Motion
/// shows the first frame.
struct AsciiArtView: View {
    let art: AsciiArt
    /// The wallpaper fills the width and runs off the bottom; a preview shows all of it.
    var wholePicture = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            // SF Mono's advance is 0.6 of its size; lines a touch tighter than the font's own.
            let byWidth = geometry.size.width / (CGFloat(max(art.columns, 1)) * 0.6)
            let byHeight = geometry.size.height / (CGFloat(max(art.rows, 1)) * 0.88)
            let size = max(2, wholePicture ? min(byWidth, byHeight) : byWidth)
            let still = art.frames.count < 2 || reduceMotion
            TimelineView(.animation(minimumInterval: 1 / art.fps, paused: still)) { context in
                let index = still ? 0 : Int(context.date.timeIntervalSinceReferenceDate * art.fps) % art.frames.count
                Text(verbatim: art.frames[index])
                    .font(.system(size: size, design: .monospaced))
                    .lineSpacing(-size * 0.12)
                    .foregroundStyle(Palette.asciiInk(art.ink))
                    .fixedSize()
                    .frame(width: geometry.size.width, height: wholePicture ? geometry.size.height : nil,
                           alignment: wholePicture ? .center : .topLeading)
            }
        }
        .accessibilityHidden(true)
    }
}
