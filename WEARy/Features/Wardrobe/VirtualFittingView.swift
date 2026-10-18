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
    @State private var trackingEnabled = false
    @State private var trackingScale = 1.0

    private var automaticActive: Bool { trackingEnabled && camera.state == .running && !sampleBackground }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("2단계 · 몸 위치 보조 추적")
                        .font(.headline)
                        .accessibilityIdentifier("fitting.stage")
                    Text("옷 사진을 화면 위에 겹치는 실험이에요. 실제 카메라에서는 몸 위치를 따라갈 수 있지만 자연스러운 합성·Jev는 없으며 실제 사이즈나 핏을 판단할 수 없어요.")
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
                    Button {
                        trackingEnabled = false
                        camera.switchCamera()
                    } label: {
                        Label("카메라 전환 · 현재 \(camera.facing.title)", systemImage: "arrow.triangle.2.circlepath.camera")
                    }
                    .buttonStyle(.bordered)
                    .disabled(sampleBackground || camera.state != .running)
                    .accessibilityIdentifier("fitting.switchCamera")
                    Toggle("몸 위치 따라가기", isOn: $trackingEnabled)
                        .disabled(sampleBackground || camera.state != .running)
                        .accessibilityIdentifier("fitting.tracking")
                    Text(automaticActive ? camera.tracking.message : "한 명의 양쪽 어깨가 보이면 상반신만으로 추적할 수 있어요. 카메라 전환 후에는 따라가기를 다시 켜 주세요. 샘플 배경에서는 수동으로 조절하세요.")
                        .font(.caption)
                        .accessibilityIdentifier("fitting.trackingStatus")
                    if automaticActive {
                        adjustment("추적 크기 보정 · 실제 치수 아님", value: $trackingScale, range: 0.7...1.4, id: "fitting.trackingScale")
                    } else {
                        Text("옷을 끌어 위치를 맞추거나 아래 조절기를 사용하세요.").font(.caption)
                        adjustment("크기", value: Binding(get: { placement.scale }, set: { placement.update(scale: $0) }), range: 0.2...1, id: "fitting.scale")
                        adjustment("가로 위치", value: Binding(get: { placement.x }, set: { placement.update(x: $0) }), range: 0...1, id: "fitting.x")
                        adjustment("세로 위치", value: Binding(get: { placement.y }, set: { placement.update(y: $0) }), range: 0...1, id: "fitting.y")
                    }
                    Button("위치·크기 초기화") { placement.reset(); dragOrigin = nil; trackingScale = 1 }
                        .accessibilityIdentifier("fitting.reset")
                    Text("전면은 거울처럼, 후면은 반전 없이 표시해요. 사진·영상은 저장하거나 서버로 전송하지 않으며, 착용 횟수에도 반영하지 않아요. 배경이 제거되지 않은 옷 사진은 배경도 함께 보여요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(WEARyTheme.canvas)
            .navigationTitle("가상 피팅 · 실험")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("완료") { camera.stop(); dismiss() }.accessibilityIdentifier("fitting.close") }
            .onChange(of: trackingEnabled) { _, enabled in
                dragOrigin = nil
                camera.setTrackingEnabled(enabled)
            }
            .onChange(of: camera.state) { _, state in
                if state != .running { trackingEnabled = false }
            }
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
                    FittingCameraPreview(session: camera.session, mirrored: camera.facing.isMirrored)
#endif
                    if camera.state != .running {
                        Color.black
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 80)).foregroundStyle(.gray)
                    }
                }
                if let rect = overlayRect(in: proxy.size) {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(DragGesture().onChanged { value in
                        guard !automaticActive else { return }
                        let origin = dragOrigin ?? placement
                        if dragOrigin == nil { dragOrigin = origin }
                        placement.update(x: origin.x + value.translation.width / max(proxy.size.width, 1),
                                         y: origin.y + value.translation.height / max(proxy.size.height, 1))
                    }.onEnded { _ in dragOrigin = nil })
                    .accessibilityLabel("선택한 옷 겹쳐보기")
                    .accessibilityIdentifier("fitting.overlay")
                }
                VStack {
                    Text(sampleBackground ? "샘플 · 수동 겹쳐보기" : (automaticActive ? "몸 위치 추적 · 합성 아님" : "합성 아님 · 수동 겹쳐보기"))
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

    private func overlayRect(in size: CGSize) -> CGRect? {
        if automaticActive {
            guard case let .tracked(anchor) = camera.tracking,
                  let rect = anchor.projected(into: size, at: ProcessInfo.processInfo.systemUptime) else { return nil }
            return CGRect(x: rect.midX - rect.width * trackingScale / 2,
                          y: rect.midY - rect.height * trackingScale / 2,
                          width: rect.width * trackingScale, height: rect.height * trackingScale)
        }
        let width = size.width * placement.scale
        let height = width * image.size.height / max(image.size.width, 1)
        return CGRect(x: size.width * placement.x - width / 2,
                      y: size.height * placement.y - height / 2, width: width, height: height)
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title).accessibilityIdentifier(id)
        }
    }
}

enum FittingCameraFacing: Sendable {
    case front, back
    var title: String { self == .front ? "전면" : "후면" }
    var isMirrored: Bool { self == .front }
    var position: AVCaptureDevice.Position { self == .front ? .front : .back }
    var toggled: Self { self == .front ? .back : .front }
}

enum FittingCameraState: Equatable, Sendable {
    case idle, requesting, preparing, running, paused, unavailable, denied, failed
    var message: String {
        switch self {
        case .idle: "카메라를 켜거나 샘플 배경으로 체험하세요."
        case .requesting: "카메라 권한을 확인하고 있어요."
        case .preparing: "카메라를 준비하고 있어요."
        case .running: "라이브 카메라 · 수동 또는 몸 위치 따라가기를 선택하세요."
        case .paused: "카메라를 중지했어요. 다시 켜려면 버튼을 누르세요."
        case .unavailable: "이 환경에서는 선택한 카메라를 사용할 수 없어요. 샘플로 체험해 보세요."
        case .denied: "카메라 권한이 없어요. 설정에서 권한을 허용하거나 샘플로 체험하세요."
        case .failed: "카메라 실행을 완료하지 못했어요. 다시 시도하거나 샘플로 체험하세요."
        }
    }
}

@MainActor
private final class FittingCameraController: ObservableObject {
    @Published private(set) var state: FittingCameraState = .idle
    @Published private(set) var tracking: FittingTrackingResult = .waiting
    @Published private(set) var facing: FittingCameraFacing = .front
    private let worker = FittingCameraWorker()
    private var generation = UUID()
    private var trackingGate = FittingTrackingGate()
    private var trackingWatchdog: Task<Void, Never>?
    var session: AVCaptureSession { worker.session }

    func start() {
        guard state != .requesting, state != .preparing, state != .running else { return }
#if targetEnvironment(simulator)
        state = .unavailable
#else
        let token = UUID()
        generation = token
        let selectedFacing = facing
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
            self.worker.start(facing: selectedFacing, completion: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.state = result
                }
            }, onTracking: { [weak self] trackingToken, sequence, result in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token,
                          self.trackingGate.accepts(trackingToken, sequence: sequence), self.state == .running else { return }
                    if case let .tracked(anchor) = result {
                        guard anchor.isFresh(at: ProcessInfo.processInfo.systemUptime) else { self.tracking = .lost; return }
                        let previous: FittingBodyAnchor?
                        if case let .tracked(old) = self.tracking { previous = old } else { previous = nil }
                        self.tracking = .tracked(anchor.smoothed(after: previous))
                    } else {
                        self.tracking = result
                        if result == .unavailable {
                            self.trackingGate.reset(enabled: false)
                            self.trackingWatchdog?.cancel()
                            self.trackingWatchdog = nil
                        }
                    }
                }
            })
        }
#endif
    }

    func stop() {
        generation = UUID()
        setTrackingEnabled(false)
        worker.stop()
        if state == .running || state == .preparing || state == .requesting { state = .paused }
    }

    func switchCamera() {
        guard state == .running else { return }
        stop() // Invalidates pending pose results before the input/mirroring changes.
        facing = facing.toggled
        start()
    }

    func setTrackingEnabled(_ enabled: Bool) {
        trackingGate.reset(enabled: enabled && state == .running)
        tracking = .waiting
        trackingWatchdog?.cancel()
        trackingWatchdog = nil
        worker.setTrackingEnabled(trackingGate.isActive, token: trackingGate.token)
        guard trackingGate.isActive else { return }
        trackingWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard let self, self.trackingGate.isActive, self.state == .running else { return }
                if case let .tracked(anchor) = self.tracking,
                   !anchor.isFresh(at: ProcessInfo.processInfo.systemUptime) { self.tracking = .lost }
            }
        }
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
    private let videoOutput = AVCaptureVideoDataOutput()
    private let tracker = FittingBodyTracker()
    private var canTrack = false

    func start(facing: FittingCameraFacing, completion: @escaping @Sendable (FittingCameraState) -> Void,
               onTracking: @escaping @Sendable (UUID, UInt64, FittingTrackingResult) -> Void) {
        queue.async { [self] in
            tracker.configure(onResult: onTracking)
            do {
                if session.isRunning { session.stopRunning() }
                canTrack = false
                session.beginConfiguration()
                for input in session.inputs { session.removeInput(input) }
                for output in session.outputs { session.removeOutput(output) }
                session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: facing.position),
                      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                    session.commitConfiguration()
                    completion(.unavailable)
                    return
                }
                session.addInput(input)
                if session.canAddOutput(videoOutput) {
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    session.addOutput(videoOutput)
                    if let connection = videoOutput.connection(with: .video),
                       connection.isVideoRotationAngleSupported(90), connection.isVideoMirroringSupported {
                        connection.videoRotationAngle = 90
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = facing.isMirrored
                        canTrack = true
                        videoOutput.setSampleBufferDelegate(tracker, queue: tracker.queue)
                    }
                }
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning ? .running : .failed)
        }
    }

    func stop() {
        queue.async { [self] in tracker.reset(); if session.isRunning { session.stopRunning() } }
    }

    func setTrackingEnabled(_ enabled: Bool, token: UUID) {
        queue.async { [self] in
            if enabled && !canTrack { tracker.reportUnavailable(token: token) }
            else { tracker.setEnabled(enabled, token: token) }
        }
    }
}

private struct FittingCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
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
                connection.isVideoMirrored = mirrored
            }
        }
    }
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layerView: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
