import ImageIO
import SwiftUI
import UIKit
import XBotRemote

/// Pictures decoded at the size they're shown, once, and kept small (a few MB at most).
enum ThumbnailCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 12 << 20
        return cache
    }()

    static func image(_ image: RemoteImage, maxPixel: Int) -> UIImage? {
        let key = "\(image.id.uuidString)-\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = image.jpeg, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let decoded = UIImage(cgImage: cg)
        cache.setObject(decoded, forKey: key, cost: cg.bytesPerRow * cg.height)
        return decoded
    }
}

/// A picture at most `maxWidth` wide, in its own shape, decoded off the main thread.
struct Thumbnail: View {
    let image: RemoteImage
    var maxWidth: CGFloat = 260
    @State private var decoded: UIImage?
    @Environment(\.displayScale) private var scale

    private var aspect: CGFloat { CGFloat(max(image.width, 1)) / CGFloat(max(image.height, 1)) }

    var body: some View {
        let width = min(maxWidth, maxWidth * max(aspect, 0.6))
        ZStack {
            Rectangle().fill(Color(.tertiarySystemFill))
            if let decoded {
                Image(uiImage: decoded).resizable().scaledToFill().transition(.opacity)
            }
        }
        .frame(width: width, height: width / aspect)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect(cornerRadius: 18, style: .continuous))
        .task(id: image.id) {
            let pixels = Int(maxWidth * scale)
            let image = image
            let made = await Task.detached(priority: .userInitiated) { ThumbnailCache.image(image, maxPixel: pixels) }.value
            withAnimation(.easeOut(duration: 0.2)) { decoded = made }
        }
        .accessibilityLabel(image.caption ?? String(localized: "Picture"))
    }
}

/// A Mac screenshot an agent took: a rounded thumbnail, full screen on tap.
struct ScreenshotCard: View {
    let image: RemoteImage
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: open) { Thumbnail(image: image, maxWidth: 260) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("screenshot-card")
                .accessibilityHint(String(localized: "Opens it full screen"))
            if let caption = image.caption {
                Label(caption, systemImage: "macwindow").font(.caption).foregroundStyle(.secondary).padding(.leading, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Full screen, pinch to zoom, double-tap to zoom in and out.
struct ImageViewer: View {
    let image: RemoteImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let data = image.jpeg, let picture = UIImage(data: data) {
                ZoomableImage(image: picture).ignoresSafeArea()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding()
            .accessibilityLabel(String(localized: "Close"))
        }
        .statusBarHidden()
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        ])
        context.coordinator.view = view
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var view: UIView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { view }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: view)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
            }
        }
    }
}

/// "Forge wants to delete 3 files": Allow or Don't allow, then the answer and who gave it.
struct ApprovalCard: View {
    let client: RemoteClient
    let approval: RemoteApproval
    /// Answered here and accepted by the Mac, until the card's own update arrives.
    @State private var answered: Bool?
    @State private var busy = false
    @State private var tapped = 0

    private var state: String {
        if approval.state == "pending", let answered { return answered ? "allowed" : "refused" }
        return approval.state
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Circle().fill(tint.gradient))
                Text(String(localized: "Needs your OK")).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(approval.summary).font(.headline).fixedSize(horizontal: false, vertical: true)
            if !approval.detail.isEmpty {
                Text(approval.detail).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(4)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10, style: .continuous))
            }
            switch state {
            case "pending":
                HStack(spacing: 10) {
                    Button { answer(false) } label: { Text(String(localized: "Don't Allow")).frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button { answer(true) } label: { Text(String(localized: "Allow")).bold().frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .controlSize(.large)
                .disabled(busy)
                Text(String(localized: "Waits up to 10 minutes, then it won't run."))
                    .font(.caption2).foregroundStyle(.tertiary)
            case "allowed":
                Label(by(String(localized: "Allowed")), systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            case "refused":
                Label(by(String(localized: "Not allowed")), systemImage: "xmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.red)
            default:
                Label(String(localized: "No answer in time, so it didn't run."), systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: 330, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(tint.opacity(state == "pending" ? 0.5 : 0.2), lineWidth: 1))
        .sensoryFeedback(.impact(weight: .light), trigger: tapped)
        .animation(.snappy, value: state)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("approval-card")
    }

    private var symbol: String {
        switch state { case "allowed": "checkmark"; case "refused": "xmark"; case "pending": "hand.raised.fill"; default: "clock" }
    }

    private var tint: Color {
        switch state { case "allowed": .green; case "refused": .red; case "pending": .orange; default: .gray }
    }

    private func by(_ verb: String) -> String {
        guard let who = approval.answeredBy else { return verb }
        return String(localized: "\(verb) on \(who)")
    }

    private func answer(_ allow: Bool) {
        tapped += 1
        busy = true
        Task {
            if await client.answerApproval(approval.id, allow: allow) { answered = allow }
            busy = false
        }
    }
}
