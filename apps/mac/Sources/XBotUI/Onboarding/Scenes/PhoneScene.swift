import SwiftUI

/// Step 9, Your iPhone, too: a Mac shows the pairing code, which draws itself; an iPhone slides up
/// beside it and scans it; then a pulse travels between the two, back and forth.
struct PhoneScene: View {
    init() {}

    private enum Script {
        static let loop = 28.0
        static let mac = 0.4
        static let phone = 1.2
        static let phoneTakes = 1.8
        static let qr = 2.2
        static let qrTakes = 3.2
        static let scan = 5.6
        static let scanTakes = 2.0
        static let paired = 7.8
        static let pulses = 9.4
        static let pulseTakes = 2.2
        static let finalFrame = 24.0
    }

    private enum Layout {
        static let display = CGSize(width: 330, height: 212)
        static let phone = CGSize(width: 116, height: 238)
        static let macCentre = CGPoint(x: -112, y: -4)
        static let phoneCentre = CGPoint(x: 222, y: 28)
        static let qr: CGFloat = 104
    }

    var body: some View {
        SceneClock(loop: Script.loop * SceneMotion.beat, finalFrame: Script.finalFrame * SceneMotion.beat) { time in
            SceneStage { size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                ZStack {
                    AmbientLight()
                    mac(time)
                        .position(x: centre.x + Layout.macCentre.x, y: centre.y + Layout.macCentre.y)
                    pulse(time, centre: centre)
                    phone(time)
                        .position(x: centre.x + Layout.phoneCentre.x, y: centre.y + Layout.phoneCentre.y)
                }
                .frame(width: size.width, height: size.height)
                .opacity(time.seam)
            }
        }
    }

    // MARK: The Mac

    private func mac(_ time: SceneTime) -> some View {
        let appear = Ease.out(time.beat(Script.mac, 1))
        let paired = time.after(Script.paired)
        return VStack(spacing: 0) {
            // The display: a black bezel around the screen.
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .fill(ScenePalette.screenGlass)
                .frame(width: Layout.display.width, height: Layout.display.height)
                .overlay {
                    VStack(spacing: Space.s) {
                        Text(String(localized: "Pair your iPhone")).font(Typography.emphasis).foregroundStyle(Palette.textPrimary)
                        SceneQRCode(progress: time.beat(Script.qr, Script.qrTakes))
                            .frame(width: Layout.qr, height: Layout.qr)
                            .opacity(paired ? 0.35 : 1)
                            .overlay {
                                if paired {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: Layout.qr * 0.36))
                                        .foregroundStyle(Palette.success)
                                        .background(Circle().fill(ScenePalette.qrPaper).padding(4))
                                        .scaleEffect(Ease.spring(time.beat(Script.paired, 0.8), bounce: 0.25))
                                }
                            }
                        Text(paired ? String(localized: "Paired with iPhone") : String(localized: "Scan with the iPhone’s camera"))
                            .font(Typography.caption)
                            .foregroundStyle(paired ? Palette.success : Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.window)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.small + 1, style: .continuous))
                    .padding(Space.s)
                }
            // The base: a thin aluminium slab, a little wider, with the lip to open it.
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: Radius.medium, bottomTrailing: Radius.medium),
                                   style: .continuous)
                .fill(LinearGradient(colors: [ScenePalette.aluminium, ScenePalette.aluminiumEdge],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: Layout.display.width + 44, height: Space.m)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: Space.xs, bottomTrailing: Space.xs))
                        .fill(ScenePalette.aluminiumEdge)
                        .frame(width: 54, height: Space.xs)
                }
        }
        .floatingShadow()
        .opacity(appear)
        .offset(y: Ease.lerp(SceneMotion.rise, 0, appear))
    }

    // MARK: The iPhone

    private func phone(_ time: SceneTime) -> some View {
        let rise = Ease.spring(time.beat(Script.phone, Script.phoneTakes), bounce: 0.14)
        let scan = time.beat(Script.scan, Script.scanTakes)
        let found = time.after(Script.scan + Script.scanTakes)
        let paired = time.after(Script.paired)
        return RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(ScenePalette.phoneBody)
            .frame(width: Layout.phone.width, height: Layout.phone.height)
            .overlay {
                ZStack {
                    // The camera's view: dim, with the code framed in the middle.
                    LinearGradient(colors: [ScenePalette.screenGlass, ScenePalette.phoneBody], startPoint: .top, endPoint: .bottom)
                    if !paired {
                        SceneQRCode(progress: time.beat(Script.qr, Script.qrTakes))
                            .frame(width: 54, height: 54)
                            .opacity(0.8)
                            .rotationEffect(.degrees(-4))
                        Viewfinder(found: found)
                            .frame(width: 74, height: 74)
                        if time.after(Script.scan) && !found {
                            Capsule()
                                .fill(Palette.accent)
                                .frame(width: 66, height: 2)
                                .shadow(color: Palette.accent, radius: 4)
                                .offset(y: Ease.lerp(-32, 32, Ease.inOut(scan < 0.5 ? scan * 2 : 2 - scan * 2)))
                        }
                    } else {
                        VStack(spacing: Space.s) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(SceneType.pairedCheck)
                                .foregroundStyle(Palette.success)
                                .scaleEffect(Ease.spring(time.beat(Script.paired, 0.8), bounce: 0.25))
                            Text(String(localized: "Paired")).font(Typography.emphasis).foregroundStyle(ScenePalette.screenInk)
                            Text(verbatim: "xBot").font(Typography.caption).foregroundStyle(ScenePalette.screenInk.opacity(0.6))
                        }
                        .opacity(Ease.out(time.beat(Script.paired, 0.6)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .padding(5)
                .overlay(alignment: .top) {
                    Capsule().fill(ScenePalette.phoneBody).frame(width: 34, height: 10).padding(.top, 11)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(ScenePalette.aluminiumEdge.opacity(0.6), lineWidth: 1))
            .floatingShadow()
            .rotationEffect(.degrees(Ease.lerp(8, 0, rise)))
            .offset(y: Ease.lerp(330, 0, rise))
    }

    // MARK: The pulse between them

    @ViewBuilder
    private func pulse(_ time: SceneTime, centre: CGPoint) -> some View {
        if time.after(Script.pulses) {
            let from = CGPoint(x: centre.x + Layout.phoneCentre.x, y: centre.y + Layout.phoneCentre.y - Layout.phone.height / 2 - Space.s)
            let to = CGPoint(x: centre.x + Layout.macCentre.x + Layout.display.width / 2 - Space.xl,
                             y: centre.y + Layout.macCentre.y - Layout.display.height / 2 - Space.s)
            let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 84)
            let elapsed = time.t / SceneMotion.beat - Script.pulses
            let leg = Int(elapsed / Script.pulseTakes)
            let p = time.still ? 0.5 : Ease.inOut((elapsed - Double(leg) * Script.pulseTakes) / Script.pulseTakes)
            // Phone to Mac, then back.
            let u = leg % 2 == 0 ? p : 1 - p
            let point = Self.bezier(from, control, to, u)
            ZStack {
                Path { path in
                    path.move(to: from)
                    path.addQuadCurve(to: to, control: control)
                }
                .stroke(Palette.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
                Circle()
                    .fill(RadialGradient(colors: [Palette.accent.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 16))
                    .frame(width: 32, height: 32)
                    .position(point)
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 8, height: 8)
                    .position(point)
            }
            .opacity(Ease.out(time.beat(Script.pulses, 0.8)))
        }
    }

    private static func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let u = CGFloat(t)
        return CGPoint(x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x,
                       y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y)
    }
}

/// A QR code that draws itself: its three finder squares first, then the modules in a sweep from
/// the top left. The pattern is made up, and stable, so every frame shows the same code.
private struct SceneQRCode: View {
    let progress: Double
    private static let n = 25

    var body: some View {
        Canvas { context, size in
            let cell = size.width / CGFloat(Self.n + 2)
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cell * 1.2),
                         with: .color(ScenePalette.qrPaper))
            let sweep = progress * 1.15
            for r in 0..<Self.n {
                for c in 0..<Self.n where Self.dark(r, c) {
                    let finder = Self.finder(r, c)
                    // Finders arrive in the first fifth; the rest on a diagonal sweep with a little grain.
                    let at = finder ? 0.0 : 0.15 + 0.85 * (Double(r + c) / Double(2 * Self.n) + Self.grain(r, c) * 0.12)
                    let shown = Ease.clamp((sweep - at) / 0.1)
                    guard shown > 0 else { continue }
                    let inset = cell * CGFloat(1 - shown) / 2
                    let rect = CGRect(x: CGFloat(c + 1) * cell + inset, y: CGFloat(r + 1) * cell + inset,
                                      width: cell - 2 * inset, height: cell - 2 * inset)
                    context.fill(Path(rect), with: .color(ScenePalette.qrInk))
                }
            }
        }
    }

    private static func finder(_ r: Int, _ c: Int) -> Bool {
        (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7)
    }

    private static func dark(_ r: Int, _ c: Int) -> Bool {
        for (r0, c0) in [(0, 0), (0, n - 7), (n - 7, 0)] {
            let y = r - r0, x = c - c0
            if (0..<7).contains(y) && (0..<7).contains(x) {
                let ring = min(min(x, 6 - x), min(y, 6 - y))
                return ring != 1
            }
            // The quiet border around each finder.
            if (-1...7).contains(y) && (-1...7).contains(x) { return false }
        }
        if r == 6 { return c % 2 == 0 }
        if c == 6 { return r % 2 == 0 }
        // A small alignment square near the bottom right.
        let ay = r - (n - 9), ax = c - (n - 9)
        if (-2...2).contains(ay) && (-2...2).contains(ax) { return max(abs(ax), abs(ay)) != 1 }
        return grain(r, c) > 0.48
    }

    private static func grain(_ r: Int, _ c: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: r &* 73_856_093 ^ c &* 19_349_663)
        h ^= h >> 13
        h &*= 0x5BD1_E995
        h ^= h >> 15
        return Double(h % 1000) / 1000
    }
}

/// The camera's corner brackets, turning green when the code is found.
private struct Viewfinder: View {
    let found: Bool

    var body: some View {
        Canvas { context, size in
            let l: CGFloat = 14
            var path = Path()
            for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (size.width, 0, -1, 1), (0, size.height, 1, -1),
                                   (size.width, size.height, -1, -1)] {
                path.move(to: CGPoint(x: x, y: y + dy * l))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + dx * l, y: y))
            }
            context.stroke(path, with: .color(found ? Palette.success : ScenePalette.screenInk),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}
