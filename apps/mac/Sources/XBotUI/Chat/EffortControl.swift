import SwiftUI
import XBotCore

/// The composer's Effort chip: the level by name; it opens the slider.
struct EffortChip: View {
    let effort: Effort
    let recommended: Effort
    let onChange: (Effort) -> Void
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Chip(effort.title, systemImage: "brain", showsChevron: true)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $open, arrowEdge: .top) {
            EffortCard(effort: effort, recommended: recommended, onChange: onChange)
        }
        .help(String(localized: "How hard the agent thinks"))
    }
}

/// "Effort · Medium": Faster to Smarter, six stops, a brain for a knob — and at the top, Galaxy.
struct EffortCard: View {
    let effort: Effort
    let recommended: Effort
    let onChange: (Effort) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text(String(localized: "Effort")).bodyText().foregroundStyle(Palette.textTertiary)
                Text(effort.title).emphasisText()
                    .foregroundStyle(effort == .galaxy ? Palette.galaxyLabel : Palette.textPrimary)
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Palette.textTertiary)
                    .help(String(localized: "Higher effort thinks longer and costs more. Galaxy is the most the agent can do: Claude Code at max on Opus, Codex at its ultra level."))
            }
            VStack(spacing: Space.s) {
                HStack {
                    Text(String(localized: "Faster"))
                    Spacer()
                    Text(String(localized: "Smarter"))
                }
                .captionText()
                .foregroundStyle(Palette.textTertiary)
                EffortTrack(effort: effort, recommended: recommended, onChange: onChange)
            }
        }
        .padding(Space.m)
        .frame(width: Metrics.effortCardWidth)
        .motion(Motion.quick, value: effort)
    }
}

/// The track: stops as dots, the recommended one as a tick with its label beneath; a filled run up
/// to the knob; and at Galaxy, a field of shimmering pixels and a knob that radiates.
struct EffortTrack: View {
    let effort: Effort
    let recommended: Effort
    let onChange: (Effort) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    private let stops = Effort.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let knobX = x(of: effort, in: width)
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.inset)
                    if effort == .galaxy {
                        GalaxyPixels(animated: !reduceMotion)
                            .clipShape(Capsule())
                    } else {
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.effortFillStart, Palette.effortFillEnd],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: knobX + Metrics.effortKnob / 2)
                    }
                    ForEach(stops, id: \.self) { stop in
                        marker(stop)
                            .position(x: x(of: stop, in: width), y: Metrics.effortTrackHeight / 2)
                    }
                    Knob(galaxy: effort == .galaxy, animated: !reduceMotion)
                        .position(x: knobX, y: Metrics.effortTrackHeight / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in choose(nearest(to: value.location.x, in: width)) }
                )
            }
            .frame(height: Metrics.effortTrackHeight)
            GeometryReader { geometry in
                Text(String(localized: "Recommended"))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize()
                    .position(x: max(Space.xxl + Space.s, x(of: recommended, in: geometry.size.width)), y: Space.s)
            }
            .frame(height: Space.l)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Effort"))
        .accessibilityValue(effort.title)
        .accessibilityAdjustableAction { direction in
            _ = step(direction == .increment ? 1 : -1)
        }
        .motion(Motion.reposition, value: effort)
    }

    @ViewBuilder private func marker(_ stop: Effort) -> some View {
        if stop == recommended {
            Capsule().fill(Palette.textTertiary).frame(width: 2, height: Space.s + Space.xxs)
        } else {
            Circle().fill(Palette.textTertiary.opacity(0.6)).frame(width: 3, height: 3)
        }
    }

    private func x(of stop: Effort, in width: CGFloat) -> CGFloat {
        let inset = Metrics.effortKnob / 2
        let index = CGFloat(stops.firstIndex(of: stop) ?? 0)
        return inset + index * (width - inset * 2) / CGFloat(stops.count - 1)
    }

    private func nearest(to location: CGFloat, in width: CGFloat) -> Effort {
        stops.min { abs(x(of: $0, in: width) - location) < abs(x(of: $1, in: width) - location) } ?? effort
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        guard let index = stops.firstIndex(of: effort), stops.indices.contains(index + offset) else { return .handled }
        choose(stops[index + offset])
        return .handled
    }

    private func choose(_ stop: Effort) {
        guard stop != effort else { return }
        onChange(stop)
    }
}

/// The brain on the knob: pink, glowing; at Galaxy, blue-violet with rays turning around it.
private struct Knob: View {
    let galaxy: Bool
    let animated: Bool

    var body: some View {
        ZStack {
            if galaxy {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { context in
                    Canvas { canvas, size in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                        for ray in 0..<14 {
                            let angle = Double(ray) / 14 * 2 * .pi + t * 0.35
                            let reach = 18 + 10 * (0.5 + 0.5 * sin(t * 2.1 + Double(ray) * 1.7))
                            var path = Path()
                            path.move(to: CGPoint(x: centre.x + cos(angle) * 13, y: centre.y + sin(angle) * 13))
                            path.addLine(to: CGPoint(x: centre.x + cos(angle) * reach, y: centre.y + sin(angle) * reach))
                            canvas.stroke(path, with: .color(Palette.galaxyPixels[ray % 4].opacity(0.55)), lineWidth: 0.7)
                        }
                    }
                }
                .frame(width: Metrics.effortKnob * 2.6, height: Metrics.effortKnob * 2.6)
            }
            Image(systemName: "brain.fill")
                .font(.system(size: Metrics.effortKnob * 0.72, weight: .semibold))
                .foregroundStyle(galaxy ? Palette.galaxy : Palette.effortKnob)
                .shadow(color: (galaxy ? Palette.galaxy : Palette.effortKnob).opacity(0.7), radius: 6)
                .frame(width: Metrics.effortKnob, height: Metrics.effortKnob)
        }
        .allowsHitTesting(false)
    }
}

/// Galaxy's track: small square pixels, brighter and busier toward the right, twinkling.
private struct GalaxyPixels: View {
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !animated)) { context in
            Canvas { canvas, size in
                let cell: CGFloat = 3.5
                let frame = Int(context.date.timeIntervalSinceReferenceDate * 6)
                let columns = Int(size.width / cell), rows = Int(size.height / cell)
                for column in 0..<columns {
                    let progress = Double(column) / Double(max(columns - 1, 1))
                    for row in 0..<rows {
                        var hash = UInt64(column &* 73856093) ^ UInt64(row &* 19349663) ^ UInt64(frame &* 83492791)
                        hash = (hash ^ (hash >> 13)) &* 0x5bd1e995
                        let roll = Double(hash % 1000) / 1000
                        guard roll < 0.25 + progress * 0.7 else { continue }
                        let colour = Palette.galaxyPixels[Int(hash >> 20) % (progress > 0.6 ? 4 : 5)]
                        let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell - 0.8, height: cell - 0.8)
                        canvas.fill(Path(rect), with: .color(colour.opacity(0.35 + 0.65 * progress * roll)))
                    }
                }
            }
        }
    }
}
