import AppKit
import SwiftUI

/// The sunset behind the agent's space: from the top, fading into the window by about the middle.
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
    /// Settings › General › Background picture.
    @AppStorage("showBackdrop") private var show = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(_ strength: Strength) { self.strength = strength }

    static let image: NSImage? = Bundle.module.url(forResource: "sunset", withExtension: "jpg")
        .flatMap(NSImage.init(contentsOf:))

    public var body: some View {
        GeometryReader { geometry in
            if let image = Self.image, show, !reduceTransparency {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height * Metrics.backdropHeight, alignment: .top)
                    .clipped()
                    // Dark mode dims it: a pastel sky at full brightness would glare.
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
