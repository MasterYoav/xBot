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

    static let sunset: NSImage? = Bundle.module.url(forResource: "sunset", withExtension: "jpg")
        .flatMap(NSImage.init(contentsOf:))

    /// Settings › Appearance › Wallpaper. Nil draws nothing: the window's own colour.
    @MainActor static func image(for wallpaper: Appearance.Wallpaper) -> NSImage? {
        switch wallpaper {
        case .sunset: sunset
        case .none: nil
        case .custom(let url): PictureCache.image(at: url)
        case .desktop:
            NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }.flatMap(PictureCache.image(at:))
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            if let image = Self.image(for: Appearance.shared.wallpaper), !reduceTransparency {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height * Metrics.backdropHeight, alignment: .top)
                    .clipped()
                    // Dark mode dims it: a bright picture at full strength would glare.
                    .overlay(Color.black.opacity(scheme == .dark ? 0.42 : 0))
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.3),
                                .init(color: .black.opacity(0.55), location: 0.62),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
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
