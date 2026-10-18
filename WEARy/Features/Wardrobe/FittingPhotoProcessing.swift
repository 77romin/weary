// Still-photo fitting only; no camera session or continuous frame processing.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision

struct FittingJoint: Sendable {
    let x: Double
    let y: Double
    let confidence: Float
    var isUsable: Bool {
        x.isFinite && y.isFinite && confidence.isFinite && confidence >= 0.45 && confidence <= 1
            && (0...1).contains(x) && (0...1).contains(y)
    }
}

enum FittingBodyGeometry {
    /// Top-left normalized coordinates in an EXIF-normalized photo.
    static func rect(leftShoulder: FittingJoint, rightShoulder: FittingJoint,
                     leftHip: FittingJoint, rightHip: FittingJoint, imageSize: CGSize) -> CGRect? {
        guard leftShoulder.isUsable, rightShoulder.isUsable,
              imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let width = abs(leftShoulder.x - rightShoulder.x)
        guard width >= 0.06 else { return nil }
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        if !leftHip.isUsable || !rightHip.isUsable {
            let height = width * imageSize.width / imageSize.height * 1.9
            return CGRect(x: (leftShoulder.x + rightShoulder.x) / 2 - width * 0.8,
                          y: shoulderY - height * 0.12, width: width * 1.6, height: height)
        }
        let torsoHeight = (leftHip.y + rightHip.y) / 2 - shoulderY
        guard torsoHeight >= 0.08 else { return nil }
        let centerX = (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4
        return CGRect(x: centerX - width * 0.8, y: shoulderY - torsoHeight * 0.18,
                      width: width * 1.6, height: torsoHeight * 1.45)
    }

    static func photoFrame(imageSize: CGSize, viewport: CGSize) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0,
              viewport.width > 0, viewport.height > 0,
              [imageSize.width, imageSize.height, viewport.width, viewport.height].allSatisfy(\.isFinite) else { return nil }
        let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

enum FittingPhotoOutcome: Equatable, Sendable {
    case placed, noBody, multiplePeople, unavailable
    var message: String {
        switch self {
        case .placed: "상반신 위치에 상의를 자동 배치했어요. 필요하면 위치와 크기를 조절하세요."
        case .noBody: "양쪽 어깨를 찾지 못했어요. 한 명의 상반신 사진을 선택하거나 수동으로 배치하세요."
        case .multiplePeople: "여러 사람이 보여 자동 배치하지 않았어요. 한 명만 나온 사진을 선택하세요."
        case .unavailable: "이 환경에서 사진 분석을 실행하지 못했어요. 수동으로 배치할 수 있어요."
        }
    }
}

struct FittingPhotoResult: Sendable {
    let data: Data
    let size: CGSize
    let rect: CGRect?
    let outcome: FittingPhotoOutcome
}

enum FittingPhotoError: LocalizedError {
    case invalidImage
    var errorDescription: String? { "사진을 읽지 못했어요. 다른 사진을 선택해 주세요." }
}

enum FittingPhotoProcessor {
    /// Downsample before decoding; apply EXIF rotation/mirroring exactly once.
    /// Vision and the preview use the same upright pixels.
    static func normalizedImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw FittingPhotoError.invalidImage }
        return image
    }

    static func process(_ data: Data) throws -> FittingPhotoResult {
        let image = try normalizedImage(data)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw FittingPhotoError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FittingPhotoError.invalidImage }
        let size = CGSize(width: image.width, height: image.height)
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            let people = request.results ?? []
            guard people.count <= 1 else {
                return .init(data: output as Data, size: size, rect: nil, outcome: .multiplePeople)
            }
            guard let person = people.first, let points = try? person.recognizedPoints(.all) else {
                return .init(data: output as Data, size: size, rect: nil, outcome: .noBody)
            }
            func joint(_ name: VNHumanBodyPoseObservation.JointName) -> FittingJoint {
                guard let point = points[name] else { return .init(x: 0, y: 0, confidence: 0) }
                return .init(x: point.location.x, y: 1 - point.location.y, confidence: point.confidence)
            }
            let rect = FittingBodyGeometry.rect(leftShoulder: joint(.leftShoulder), rightShoulder: joint(.rightShoulder),
                leftHip: joint(.leftHip), rightHip: joint(.rightHip), imageSize: size)
            return .init(data: output as Data, size: size, rect: rect, outcome: rect == nil ? .noBody : .placed)
        } catch {
            return .init(data: output as Data, size: size, rect: nil, outcome: .unavailable)
        }
    }
}

/// Replacing/clearing a photo invalidates any earlier load or analysis.
struct FittingPhotoRequestGate {
    private(set) var token = UUID()
    mutating func begin() -> UUID { token = UUID(); return token }
    func accepts(_ candidate: UUID) -> Bool { candidate == token }
}
