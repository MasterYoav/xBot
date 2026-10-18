import AVFoundation
import ImageIO
import PhotosUI
import Speech
import SwiftUI
import XBotRemote

/// A photo picked to send: already a JPEG ≤ 1600 px (the Mac keeps it as is), and a small preview.
struct PendingPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let preview: UIImage

    /// Downscales on a background thread: the longest side ≤ 1600 px, JPEG quality 0.7.
    static func make(from data: Data) async -> PendingPhoto? {
        await Task.detached(priority: .userInitiated) { () -> PendingPhoto? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            func thumbnail(_ max: Int) -> CGImage? {
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                kCGImageSourceCreateThumbnailWithTransform: true,
                                                kCGImageSourceThumbnailMaxPixelSize: max]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }
            guard let full = thumbnail(1600), let jpeg = UIImage(cgImage: full).jpegData(compressionQuality: 0.7),
                  let small = thumbnail(200) else { return nil }
            return PendingPhoto(jpeg: jpeg, preview: UIImage(cgImage: small))
        }.value
    }
}

/// The thread's composer: photos, a growing field with dictation, and send (stop while they work).
struct AgenticComposer: View {
    let client: RemoteClient
    let memberID: UUID
    let name: String
    let running: Bool
    let chatID: UUID?
    @Binding var text: String
    @Binding var photos: [PendingPhoto]
    var focused: FocusState<Bool>.Binding
    @State private var picks: [PhotosPickerItem] = []
    @State private var sending = false
    @State private var sent = 0
    @State private var dictation = Dictation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var connected: Bool { client.link == .local || client.link == .cloud }
    private var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty }
    private var canSend: Bool { hasContent && !sending && !running && connected }

    var body: some View {
        VStack(spacing: 8) {
            if !photos.isEmpty { photoStrip }
            if let problem = dictation.problem {
                Text(problem).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            }
            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    PhotosPicker(selection: $picks, maxSelectionCount: 4, matching: .images) {
                        Image(systemName: "plus").font(.system(size: 19, weight: .semibold)).foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Add photos"))
                    HStack(alignment: .bottom, spacing: 2) {
                        TextField(String(localized: "Message \(name)"), text: $text, axis: .vertical)
                            .lineLimit(1...6)
                            .focused(focused)
                            .padding(.leading, 16).padding(.vertical, 12)
                            .accessibilityIdentifier("agentic-composer")
                        Button { toggleDictation() } label: {
                            Image(systemName: dictation.isRecording ? "waveform" : "mic")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(dictation.isRecording ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                                .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording && !reduceMotion)
                                .frame(width: 40, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(dictation.isRecording ? String(localized: "Stop dictation") : String(localized: "Dictate"))
                    }
                    .padding(.trailing, 4)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 23))
                    if running && !hasContent {
                        Button { if let chatID { Task { await client.stop(chatID) } } } label: {
                            Image(systemName: "stop.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.primary)
                                .frame(width: 46, height: 46)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Stop"))
                        .transition(.scale.combined(with: .opacity))
                    } else if hasContent {
                        Button { Task { await send() } } label: {
                            Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                                .foregroundStyle(canSend ? .white : .secondary)
                                .frame(width: 46, height: 46)
                                .glassEffect(canSend ? .regular.tint(Theme.accent).interactive() : .regular, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .accessibilityLabel(String(localized: "Send"))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.2), value: hasContent)
            .animation(.spring(duration: 0.3), value: running)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .sensoryFeedback(.impact(weight: .light), trigger: sent)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            picks = []
            Task {
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self), let photo = await PendingPhoto.make(from: data) else { continue }
                    withAnimation(.snappy) { photos.append(photo) }
                }
            }
        }
        .onDisappear { dictation.stop() }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    Image(uiImage: photo.preview).resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { withAnimation(.snappy) { photos.removeAll { $0.id == photo.id } } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                            }
                            .padding(3)
                            .accessibilityLabel(String(localized: "Remove photo"))
                        }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func toggleDictation() {
        if dictation.isRecording { dictation.stop(); return }
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await dictation.start { heard in
                text = base.isEmpty ? heard : base + " " + heard
            }
        }
    }

    private func send() async {
        dictation.stop()
        let message = text, images = photos
        sending = true
        sent += 1
        text = ""
        photos = []
        let answer = await client.threadSend(memberID, text: message, images: images.map(\.jpeg))
        if !answer.ok {
            text = message
            photos = images
        }
        sending = false
    }
}

/// On-device dictation (where the device can; it never leaves it then): the live transcript goes
/// into the field until tapped again.
@MainActor @Observable
final class Dictation {
    private(set) var isRecording = false
    /// Why it can't listen, in a sentence.
    var problem: String?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start(_ heard: @escaping @MainActor (String) -> Void) async {
        problem = nil
        let speech = await withCheckedContinuation { (done: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
        guard speech == .authorized else {
            problem = String(localized: "Dictation needs Speech Recognition: allow it for xBot in Settings.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = String(localized: "Dictation needs the microphone: allow it for xBot in Settings.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            problem = String(localized: "Dictation isn't available right now.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            nonisolated(unsafe) let feed = request
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in feed.append(buffer) }
            engine.prepare()
            try engine.start()
        } catch {
            problem = String(localized: "The microphone couldn't start: \(error.localizedDescription)")
            engine.inputNode.removeTap(onBus: 0)
            return
        }
        self.request = request
        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || result?.isFinal == true
            Task { @MainActor in
                if let text { heard(text) }
                if finished { self?.stop() }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
