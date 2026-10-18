@preconcurrency import AVFoundation
import Vision

struct FittingJoint: Sendable {
    /// Normalized top-left coordinates in the upright video frame (front mirrored, back unmirrored).
    let x: Double
    let y: Double
    let confidence: Float

    var isUsable: Bool {
        x.isFinite && y.isFinite && confidence.isFinite && confidence >= 0.45 && confidence <= 1
            && (0...1).contains(x) && (0...1).contains(y)
    }
}

struct FittingBodyAnchor: Equatable, Sendable {
    let rect: CGRect
    let imageSize: CGSize
    let sampledAt: TimeInterval

    func isFresh(at now: TimeInterval) -> Bool {
        now.isFinite && sampledAt.isFinite && now >= sampledAt && now - sampledAt <= 0.6
    }

    /// Matches resizeAspectFill used by the camera preview. The video output is
    /// already upright with the preview's mirroring, so don't mirror again here.
    func projected(into viewport: CGSize, at now: TimeInterval) -> CGRect? {
        guard isFresh(at: now), imageSize.width.isFinite, imageSize.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              imageSize.width > 0, imageSize.height > 0, viewport.width > 0, viewport.height > 0,
              rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else { return nil }
        let scale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let projected = CGRect(x: (viewport.width - width) / 2 + rect.minX * width,
                               y: (viewport.height - height) / 2 + rect.minY * height,
                               width: rect.width * width, height: rect.height * height)
        guard projected.intersects(CGRect(origin: .zero, size: viewport)) else { return nil }
        return projected
    }

    func smoothed(after previous: Self?) -> Self {
        guard let previous, previous.imageSize == imageSize,
              sampledAt > previous.sampledAt, sampledAt - previous.sampledAt < 0.3 else { return self }
        let weight = 0.4
        func mix(_ old: CGFloat, _ new: CGFloat) -> CGFloat { old + (new - old) * weight }
        return Self(rect: CGRect(x: mix(previous.rect.minX, rect.minX),
                                 y: mix(previous.rect.minY, rect.minY),
                                 width: mix(previous.rect.width, rect.width),
                                 height: mix(previous.rect.height, rect.height)),
                    imageSize: imageSize, sampledAt: sampledAt)
    }
}

enum FittingTrackingResult: Equatable, Sendable {
    case waiting, tracked(FittingBodyAnchor), lost, multiplePeople, unavailable

    var message: String {
        switch self {
        case .waiting: "양쪽 어깨가 보이도록 정면에 서 주세요. 상반신만 보여도 사용할 수 있어요."
        case .tracked: "몸 위치 따라가기 · 단순 이미지 배치이며 자연스러운 합성이 아니에요."
        case .lost: "몸 위치를 놓쳐 옷을 숨겼어요. 양쪽 어깨가 보이도록 서 주세요."
        case .multiplePeople: "여러 사람이 보여 옷을 숨겼어요. 한 명만 화면에 들어오세요."
        case .unavailable: "이 환경에서 신체 추적을 실행하지 못했어요. 수동 모드로 전환해 주세요."
        }
    }
}

/// A new token on every mode change rejects callbacks from a previous request,
/// including a quick off → on transition within the same camera session.
struct FittingTrackingGate {
    private(set) var token = UUID()
    private(set) var isActive = false
    private var lastSequence: UInt64 = 0
    mutating func reset(enabled: Bool) { token = UUID(); isActive = enabled; lastSequence = 0 }
    mutating func accepts(_ token: UUID, sequence: UInt64) -> Bool {
        guard isActive, self.token == token, sequence > lastSequence else { return false }
        lastSequence = sequence
        return true
    }
}

enum FittingBodyGeometry {
    static func anchor(leftShoulder: FittingJoint, rightShoulder: FittingJoint,
                       leftHip: FittingJoint, rightHip: FittingJoint,
                       imageSize: CGSize, sampledAt: TimeInterval) -> FittingBodyAnchor? {
        let joints = [leftShoulder, rightShoulder]
        guard joints.allSatisfy(\.isUsable), sampledAt.isFinite,
              imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        guard shoulderWidth >= 0.06 else { return nil }
        // Cropped upper-body frames often have no hips. Estimate only placement
        // from shoulder width in pixels, not body measurements or clothing size.
        if !leftHip.isUsable || !rightHip.isUsable {
            let height = shoulderWidth * imageSize.width / imageSize.height * 1.9
            let centerX = (leftShoulder.x + rightShoulder.x) / 2
            return FittingBodyAnchor(
                rect: CGRect(x: centerX - shoulderWidth * 0.8, y: shoulderY - height * 0.12,
                             width: shoulderWidth * 1.6, height: height),
                imageSize: imageSize, sampledAt: sampledAt)
        }
        let hipY = (leftHip.y + rightHip.y) / 2
        let torsoHeight = hipY - shoulderY
        // Reject tiny / side-on / inverted observations rather than inventing a fit.
        guard shoulderWidth >= 0.06, torsoHeight >= 0.08 else { return nil }
        let centerX = (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4
        return FittingBodyAnchor(
            rect: CGRect(x: centerX - shoulderWidth * 0.8, y: shoulderY - torsoHeight * 0.18,
                         width: shoulderWidth * 1.6, height: torsoHeight * 1.45),
            imageSize: imageSize, sampledAt: sampledAt)
    }
}

/// All mutable fields and Vision work are confined to queue. No frame or pose
/// observation is retained, stored, logged or sent over the network.
final class FittingBodyTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.weary.fitting.pose", qos: .userInitiated)
    private var enabled = false
    private var token = UUID()
    private var lastAnalysisTime: TimeInterval = 0
    private var sequence: UInt64 = 0
    private var onResult: (@Sendable (UUID, UInt64, FittingTrackingResult) -> Void)?

    func configure(onResult: @escaping @Sendable (UUID, UInt64, FittingTrackingResult) -> Void) {
        queue.async { self.onResult = onResult; self.enabled = false; self.lastAnalysisTime = 0 }
    }

    func setEnabled(_ enabled: Bool, token: UUID) {
        queue.async { self.enabled = enabled; self.token = token; self.sequence = 0; self.lastAnalysisTime = 0 }
    }

    func reportUnavailable(token: UUID) {
        queue.async { self.enabled = false; self.token = token; self.sequence = 0; self.emit(.unavailable) }
    }

    func reset() {
        queue.async { self.enabled = false; self.onResult = nil; self.lastAnalysisTime = 0 }
    }

    private func emit(_ result: FittingTrackingResult) {
        sequence &+= 1
        onResult?(token, sequence, result)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, now - lastAnalysisTime >= 0.15 else { return }
        lastAnalysisTime = now
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            emit(.lost)
            return
        }
        let request = VNDetectHumanBodyPoseRequest()
        do {
            // The capture connection rotates 90°; only front frames are mirrored.
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let observations = request.results ?? []
            guard observations.count <= 1 else { emit(.multiplePeople); return }
            guard let observation = observations.first,
                  let points = try? observation.recognizedPoints(.all) else {
                emit(.lost)
                return
            }
            func joint(_ name: VNHumanBodyPoseObservation.JointName) -> FittingJoint {
                guard let point = points[name] else { return .init(x: 0, y: 0, confidence: 0) }
                return .init(x: point.location.x, y: 1 - point.location.y, confidence: point.confidence)
            }
            let anchor = FittingBodyGeometry.anchor(
                leftShoulder: joint(.leftShoulder), rightShoulder: joint(.rightShoulder),
                leftHip: joint(.leftHip), rightHip: joint(.rightHip),
                imageSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)),
                sampledAt: now)
            emit(anchor.map(FittingTrackingResult.tracked) ?? .lost)
        } catch {
            enabled = false // Don't repeat an unavailable model request on every frame.
            emit(.unavailable)
        }
    }
}
