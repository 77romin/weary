@preconcurrency import AVFoundation
import SwiftUI
import Combine

/// Normalized placement only. No body measurements or inferred clothing size.
struct FittingOverlayPlacement: Equatable {
    private(set) var x = 0.5
    private(set) var y = 0.42
    private(set) var scale = 0.65

    mutating func update(x: Double? = nil, y: Double? = nil, scale: Double? = nil) {
        if let x, x.isFinite { self.x = min(max(x, 0), 1) }
        if let y, y.isFinite { self.y = min(max(y, 0), 1) }
        if let scale, scale.isFinite { self.scale = min(max(scale, 0.2), 1) }
    }

    mutating func reset() { self = Self() }
}

struct VirtualFittingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let garmentName: String
    let image: UIImage
    @StateObject private var camera = FittingCameraController()
    @State private var sampleBackground = false
    @State private var placement = FittingOverlayPlacement()
    @State private var dragOrigin: FittingOverlayPlacement?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("1단계 · 수동 겹쳐보기")
                        .font(.headline)
                        .accessibilityIdentifier("fitting.stage")
                    Text("옷 사진을 화면 위에 겹치는 실험이에요. 신체 추적·자연스러운 합성·Jev는 아직 없으며 실제 사이즈나 핏을 판단할 수 없어요.")
                        .font(.caption)
                    preview
                    Text(garmentName).font(.headline)
                    Text(sampleBackground ? "샘플 배경 · 라이브 카메라가 아닙니다" : camera.state.message)
                        .font(.caption)
                        .accessibilityIdentifier("fitting.status")
                    HStack {
                        Button("카메라 켜기") {
                            sampleBackground = false
                            camera.start()
                        }
                        .disabled(camera.state == .requesting || camera.state == .preparing || camera.state == .running)
                        .accessibilityIdentifier("fitting.start")
                        Button("샘플로 체험") {
                            camera.stop()
                            sampleBackground = true
                        }
                        .accessibilityIdentifier("fitting.sample")
                        Button("중지") {
                            camera.stop()
                            sampleBackground = false
                        }
                        .accessibilityIdentifier("fitting.stop")
                    }
                    .buttonStyle(.bordered)
                    Text("옷을 끌어 위치를 맞추거나 아래 조절기를 사용하세요.")
                        .font(.caption)
                    adjustment("크기", value: Binding(get: { placement.scale }, set: { placement.update(scale: $0) }), range: 0.2...1, id: "fitting.scale")
                    adjustment("가로 위치", value: Binding(get: { placement.x }, set: { placement.update(x: $0) }), range: 0...1, id: "fitting.x")
                    adjustment("세로 위치", value: Binding(get: { placement.y }, set: { placement.update(y: $0) }), range: 0...1, id: "fitting.y")
                    Button("위치·크기 초기화") { placement.reset(); dragOrigin = nil }
                        .accessibilityIdentifier("fitting.reset")
                    Text("전면 카메라는 거울처럼 표시해요. 사진·영상은 저장하거나 서버로 전송하지 않으며, 착용 횟수에도 반영하지 않아요. 배경이 제거되지 않은 옷 사진은 배경도 함께 보여요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(WEARyTheme.canvas)
            .navigationTitle("가상 피팅 · 실험")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("완료") { camera.stop(); dismiss() }.accessibilityIdentifier("fitting.close") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || (phase == .inactive && camera.state != .requesting) {
                    camera.stop()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: camera.session)) { _ in camera.stop() }
            .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: camera.session)) { _ in camera.fail() }
            .onDisappear { camera.stop() }
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if sampleBackground {
                    Image("DemoOutfitLeather").resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else {
#if !targetEnvironment(simulator)
                    FittingCameraPreview(session: camera.session)
#endif
                    if camera.state != .running {
                        Color.black
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 80)).foregroundStyle(.gray)
                    }
                }
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(width: proxy.size.width * placement.scale)
                    .position(x: proxy.size.width * placement.x, y: proxy.size.height * placement.y)
                    .gesture(DragGesture().onChanged { value in
                        let origin = dragOrigin ?? placement
                        if dragOrigin == nil { dragOrigin = origin }
                        placement.update(x: origin.x + value.translation.width / max(proxy.size.width, 1),
                                         y: origin.y + value.translation.height / max(proxy.size.height, 1))
                    }.onEnded { _ in dragOrigin = nil })
                    .accessibilityLabel("선택한 옷 겹쳐보기")
                    .accessibilityIdentifier("fitting.overlay")
                VStack {
                    Text(sampleBackground ? "샘플 · 수동 겹쳐보기" : "합성 아님 · 수동 겹쳐보기")
                        .font(.caption.weight(.bold)).padding(8)
                        .background(.black.opacity(0.7), in: Capsule()).foregroundStyle(.white)
                    Spacer()
                }.padding(12).allowsHitTesting(false)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .frame(height: 330)
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title).accessibilityIdentifier(id)
        }
    }
}

enum FittingCameraState: Equatable, Sendable {
    case idle, requesting, preparing, running, paused, unavailable, denied, failed
    var message: String {
        switch self {
        case .idle: "카메라를 켜거나 샘플 배경으로 체험하세요."
        case .requesting: "카메라 권한을 확인하고 있어요."
        case .preparing: "카메라를 준비하고 있어요."
        case .running: "라이브 전면 카메라 · 옷 위치는 수동으로 조절해요."
        case .paused: "카메라를 중지했어요. 다시 켜려면 버튼을 누르세요."
        case .unavailable: "이 환경에서는 전면 카메라를 사용할 수 없어요. 샘플로 체험해 보세요."
        case .denied: "카메라 권한이 없어요. 설정에서 권한을 허용하거나 샘플로 체험하세요."
        case .failed: "카메라 실행을 완료하지 못했어요. 다시 시도하거나 샘플로 체험하세요."
        }
    }
}

@MainActor
private final class FittingCameraController: ObservableObject {
    @Published private(set) var state: FittingCameraState = .idle
    private let worker = FittingCameraWorker()
    private var generation = UUID()
    var session: AVCaptureSession { worker.session }

    func start() {
        guard state != .requesting, state != .preparing, state != .running else { return }
#if targetEnvironment(simulator)
        state = .unavailable
#else
        let token = UUID()
        generation = token
        state = .requesting
        Task { [weak self] in
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard let self, token == self.generation else { return }
            guard authorized else { self.state = .denied; return }
            self.state = .preparing
            self.worker.start { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.state = result
                }
            }
        }
#endif
    }

    func stop() {
        generation = UUID()
        worker.stop()
        if state == .running || state == .preparing || state == .requesting { state = .paused }
    }

    func fail() {
        guard state == .running || state == .preparing else { return }
        stop()
        state = .failed
    }
}

/// Session configuration/start/stop are serialized. Preview attachment is main-thread only.
private final class FittingCameraWorker: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.weary.fitting.camera")
    private var configured = false

    func start(completion: @escaping @Sendable (FittingCameraState) -> Void) {
        queue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .high
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                    session.commitConfiguration()
                    completion(.unavailable)
                    return
                }
                session.addInput(input)
                session.commitConfiguration()
                configured = true
            }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning ? .running : .failed)
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }
}

private struct FittingCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.layerView.session = session
        view.layerView.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: Preview, context: Context) {
        if let connection = uiView.layerView.connection {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layerView: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
