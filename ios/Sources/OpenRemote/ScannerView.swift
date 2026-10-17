@preconcurrency import AVFoundation
import SwiftUI

struct ScannerView: View {
    var onManual: () -> Void
    var onCode: (String, String) -> Void

    @State private var denied = false
    @State private var handled = false

    var body: some View {
        ZStack {
            ScannerPreview(active: !handled) { raw in
                guard !handled, let parsed = ConnectionCode.parse(raw) else { return }
                handled = true
                onCode(parsed.0, parsed.1)
            }
            .ignoresSafeArea()
            VStack {
                Text(denied ? L10n.cameraDenied : L10n.scanHint)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                Spacer()
                Button(L10n.enterManually, action: onManual)
                    .buttonStyle(.glassProminent)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            applyOrientation(.portrait)
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                denied = true
            }
        }
    }
}

enum ConnectionCode {
    static func parse(_ raw: String) -> (String, String)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           scheme == "openremote" || scheme == "ws" || scheme == "http" || scheme == "https" {
            guard let host = url.host, !host.isEmpty else { return nil }
            return (host, String(url.port ?? 1337))
        }
        guard !text.contains("://"), let split = text.lastIndex(of: ":") else { return nil }
        let host = String(text[..<split])
        let port = String(text[text.index(after: split)...])
        guard !host.isEmpty, UInt16(port) != nil else { return nil }
        return (host, port)
    }
}

private struct ScannerPreview: UIViewRepresentable {
    var active: Bool
    var onCode: (String) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.onCode = onCode
        view.start()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onCode = onCode
        if active { uiView.start() } else { uiView.stop() }
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Void) {
        uiView.stop()
    }
}

final class PreviewView: UIView {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let preview = AVCaptureVideoPreviewLayer()
    private let queue = DispatchQueue(label: "openremote.camera")
    private let codes = MetaDelegate()
    private var started = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.videoGravity = .resizeAspectFill
        layer.addSublayer(preview)
    }

    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPreviewRotation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        preview.frame = bounds
        applyPreviewRotation()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                guard ok else { return }
                DispatchQueue.main.async { self?.configure() }
            }
        default:
            break
        }
    }

    func stop() {
        guard started else { return }
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        started = false
    }

    private func configure() {
        guard !started else { return }
        started = true
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            started = false
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            started = false
            return
        }
        session.addOutput(output)
        codes.onCode = { [weak self] value in
            self?.onCode?(value)
        }
        output.setMetadataObjectsDelegate(codes, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]
        preview.session = session
        session.commitConfiguration()
        attachRotation(device: device)
        queue.async { [weak self, session] in
            session.startRunning()
            DispatchQueue.main.async { self?.applyPreviewRotation() }
        }
    }

    private func attachRotation(device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.applyPreviewRotation()
            }
        }
        applyPreviewRotation()
    }

    private func applyPreviewRotation() {
        guard window != nil, let coordinator = rotationCoordinator else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelPreview
        guard let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        if connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
    }
}

private final class MetaDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = code.stringValue else { return }
        onCode?(value)
    }
}
