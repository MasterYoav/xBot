import XBotRemote
import SwiftUI

/// The phone's look: Liquid Glass controls floating over calm charcoal cards, rounded type,
/// one accent. Tokens and small pieces shared by every screen.
enum Glass {
    /// One horizontal margin everywhere, matching the large-title inset.
    static let margin: CGFloat = 16
    static let radius: CGFloat = 28
    /// A brighter accent for glows and arcs; the plain one stays for text and tint.
    static let glow = Color(red: 0.93, green: 0.49, blue: 0.74)
    static let violet = Color(red: 0.55, green: 0.42, blue: 0.95)
}

extension View {
    /// The card surface: a few percent lighter at the top, a hairline highlight on the top edge.
    func card(padding: CGFloat = 18, radius: CGFloat = Glass.radius) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }

    /// A close button (×) at the top leading edge, for screens shown full screen from Home.
    func closable() -> some View { modifier(Closable()) }
}

private struct CardSurface: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(Color(.secondarySystemGroupedBackground))
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.035 : 0), .clear],
                                                       startPoint: .top, endPoint: .center)))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.09 : 0.6), .clear],
                                                               startPoint: .top, endPoint: .center), lineWidth: 1))
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 14, y: 6)
            }
    }
}

extension EnvironmentValues {
    /// Set by whoever shows a screen full screen: how to put it away.
    @Entry var close: (() -> Void)?
}

private struct Closable: ViewModifier {
    @Environment(\.close) private var close

    func body(content: Content) -> some View {
        content.toolbar {
            if let close {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "Close"))
                }
            }
        }
    }
}

/// A section's title: big, rounded, bold, with an optional "›" that goes somewhere.
struct SectionTitle: View {
    let title: String
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label(chevron: true) }.buttonStyle(.plain)
        } else {
            label(chevron: false)
        }
    }

    private func label(chevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(.title2, design: .rounded, weight: .bold))
            if chevron { Image(systemName: "chevron.right").font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A round icon: the glyph on a soft gradient disc.
struct IconCircle: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.14)], startPoint: .top, endPoint: .bottom)))
            .accessibilityHidden(true)
    }
}

/// The open arc on Home: how much is left, glowing at its tip.
struct ArcGauge: View {
    /// 0…1, how full.
    let value: Double
    var lineWidth: CGFloat = 30

    /// The arc covers this much of a circle, open at the bottom.
    static let sweep = 0.68

    var body: some View {
        let start = 0.5 + (1 - Self.sweep) / 2
        let clamped = min(max(value, 0), 1)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = (side - lineWidth) / 2
            let tipAngle = Angle.degrees((start + Self.sweep * clamped) * 360)
            ZStack {
                Circle().trim(from: 0, to: Self.sweep)
                    .stroke(Color(.tertiarySystemFill), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(start * 360))
                Circle().trim(from: 0, to: Self.sweep * clamped)
                    .stroke(LinearGradient(colors: [Glass.violet, Glass.glow], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(start * 360))
                    .shadow(color: Glass.glow.opacity(0.45), radius: 16)
                    .opacity(clamped > 0.01 ? 1 : 0)
                Circle().fill(.white.opacity(0.9)).frame(width: lineWidth * 0.55, height: lineWidth * 0.55)
                    .shadow(color: Glass.glow, radius: 10)
                    .offset(x: cos(tipAngle.radians) * radius, y: sin(tipAngle.radians) * radius)
                    .opacity(clamped > 0.02 ? 1 : 0)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// A square-ish tile: a label, a tinted glyph, and a big number.
struct MetricTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    var detail: String?
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(title).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(.secondary)
                    if action != nil { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }
                }
                Image(systemName: symbol).font(.system(size: 24, weight: .heavy)).foregroundStyle(tint)
                Text(value).font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            }
            .card()
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
    }
}

/// A row inside a card: a circle, a title and a grey line, then whatever trails.
struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var leading: AnyView
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded, weight: .semibold)).lineLimit(1)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .contentShape(Rectangle())
    }
}

/// A chat's round mark: the agent's initial in its colour, or a spinner while it works.
struct ChatMark: View {
    let chat: RemoteChat
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(Theme.agentColor(chat.agent).opacity(0.16))
            if chat.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Text(String((chat.crewName ?? chat.agentName).prefix(1)))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.agentColor(chat.agent))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
