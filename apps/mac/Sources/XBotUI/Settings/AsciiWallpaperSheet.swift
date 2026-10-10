import SwiftUI
import XBotCore

/// Settings › Appearance › Wallpaper › Randomize: an agent draws a text-art wallpaper, still or
/// moving. The person picks the agent, model and reasoning; xBot writes the prompt.
struct AsciiWallpaperSheet: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var motion = AsciiArt.Motion.animated
    @State private var harness: HarnessKind?
    @State private var model: String?
    @State private var effort: Effort = .low
    @State private var idea = ""
    @State private var drawing: Task<Void, Never>?
    @State private var result: (art: AsciiArt, prompt: String)?
    @State private var problem: String?
    @State private var started: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Text(String(localized: "Randomize a wallpaper")).titleText()
                Spacer()
            }
            Text(String(localized: "An agent draws it in text, still or moving. xBot writes the prompt; leave the idea empty to be surprised."))
                .captionText().foregroundStyle(Palette.textSecondary)

            preview

            Grid(alignment: .leading, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
                GridRow {
                    label(String(localized: "Kind"))
                    Picker(String(localized: "Kind"), selection: $motion) {
                        Text(String(localized: "Still")).tag(AsciiArt.Motion.still)
                        Text(String(localized: "Animated")).tag(AsciiArt.Motion.animated)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                GridRow {
                    label(String(localized: "Agent"))
                    HStack(spacing: Space.s) {
                        Picker(String(localized: "Agent"), selection: $harness) {
                            ForEach(workspace.availableHarnesses, id: \.self) { Text($0.displayName).tag(HarnessKind?.some($0)) }
                        }
                        .labelsHidden().fixedSize()
                        .onChange(of: harness) { model = nil }
                        if let harness {
                            Picker(String(localized: "Model"), selection: $model) {
                                Text(String(localized: "Default model")).tag(String?.none)
                                ForEach(workspace.models(for: harness)) { Text($0.name).tag(String?.some($0.id)) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                }
                GridRow {
                    label(String(localized: "Reasoning"))
                    Picker(String(localized: "Reasoning"), selection: $effort) {
                        ForEach(Effort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                GridRow {
                    label(String(localized: "Idea"))
                    TextField(String(localized: "Idea"), text: $idea, prompt: Text(String(localized: "Optional — leave empty and xBot picks")))
                        .textFieldStyle(.roundedBorder)
                }
            }
            .disabled(drawing != nil)

            if let result {
                DisclosureGroup(String(localized: "The prompt xBot wrote")) {
                    Text(result.prompt).font(Typography.mono).foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .captionText()
            }
            if let problem {
                Text(problem).captionText().foregroundStyle(Palette.failure)
            }

            HStack {
                Button(String(localized: "Cancel")) { drawing?.cancel(); dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(result == nil ? String(localized: "Generate") : String(localized: "Another one")) { draw() }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(drawing != nil || harness == nil)
                if let result {
                    Button(String(localized: "Use as wallpaper")) {
                        do {
                            try Appearance.shared.useAscii(result.art)
                            dismiss()
                        } catch {
                            problem = String(localized: "xBot couldn't save it: \(error.localizedDescription)")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(drawing != nil)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: Metrics.sheetWidth)
        .onAppear { harness = harness ?? workspace.availableHarnesses.first }
        .onDisappear { drawing?.cancel() }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.terminalBackground)
            if let art = result?.art {
                AsciiArtView(art: art, wholePicture: true).padding(Space.s)
            } else {
                VStack(spacing: Space.s) {
                    Image(systemName: "dice").font(Typography.hero).foregroundStyle(Palette.textTertiary)
                    Text(String(localized: "Nothing drawn yet")).captionText().foregroundStyle(Palette.textTertiary)
                }
            }
            if drawing != nil {
                Rectangle().fill(.black.opacity(0.35))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: Space.s) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "\(harness?.displayName ?? "") is drawing… \(Int(context.date.timeIntervalSince(started ?? context.date)))s"))
                            .captionText().foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(height: Metrics.asciiPreviewHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline))
        if let art = result?.art, !art.title.isEmpty {
            Text(verbatim: "“\(art.title)” · \(art.frames.count == 1 ? String(localized: "still") : String(localized: "\(art.frames.count) frames"))")
                .captionText().foregroundStyle(Palette.textSecondary)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).captionText().foregroundStyle(Palette.textSecondary).gridColumnAlignment(.trailing)
    }

    private func draw() {
        guard let harness else { return }
        problem = nil
        started = .now
        let request = Workspace.WallpaperRequest(motion: motion, harness: harness, model: model, effort: effort, idea: idea)
        drawing = Task {
            do {
                let drawn = try await workspace.drawWallpaper(request)
                if !Task.isCancelled { withAnimation(.spring(duration: 0.4, bounce: 0)) { result = drawn } }
            } catch {
                if !Task.isCancelled { problem = error.localizedDescription }
            }
            drawing = nil
        }
    }
}
