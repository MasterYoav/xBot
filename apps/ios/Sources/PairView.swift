import AVFoundation
import SwiftUI
import XBotRemote

/// First run: scan the code from the Mac's Settings › Devices (or open its link).
struct PairView: View {
    let client: RemoteClient
    @State private var scanning = false
    @State private var pasted = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "macbook.and.iphone")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 40)
                    VStack(spacing: 10) {
                        Text(String(localized: "Your Mac, in your pocket")).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(String(localized: "Keep working with your agents from here. They still run on your Mac; this is the remote."))
                            .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Step(number: 1, text: String(localized: "On your Mac, open xBot › Settings › Devices."))
                        Step(number: 2, text: String(localized: "Click Pair an iPhone or iPad."))
                        Step(number: 3, text: String(localized: "Scan the code it shows."))
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
                    Button { scanning = true } label: {
                        Label(String(localized: "Scan the code"), systemImage: "qrcode.viewfinder")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .fullScreenCover(isPresented: $scanning) {
                ScannerScreen { code in
                    scanning = false
                    if let url = URL(string: code), let invite = PairingInvite(url: url) {
                        client.pair(with: invite)
                    } else {
                        problem = String(localized: "That isn't an xBot pairing code.")
                    }
                }
            }
        }
    }
}

private struct Step: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)").font(.subheadline.bold()).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(Theme.accent))
            Text(text).font(.body)
        }
    }
}

/// The camera, reading QR codes.
private struct ScannerScreen: View {
    let found: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            QRScanner(found: found).ignoresSafeArea()
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
            }
            .padding()
            RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.9), lineWidth: 3)
                .frame(width: 250, height: 250)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.found = found
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var found: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        DispatchQueue.global().async { session.stopRunning() }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        MainActor.assumeIsolated {
            guard !done, let value else { return }
            done = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            found?(value)
        }
    }
}
