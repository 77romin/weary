import Foundation
import ImageIO
import Vision

struct GarmentSnapshot: Sendable {
    let id: UUID
    let category: GarmentCategory
    let name: String
    let imageData: Data?
    let cutoutImageData: Data?

    init(
        id: UUID,
        category: GarmentCategory,
        name: String,
        imageData: Data? = nil,
        cutoutImageData: Data? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.imageData = imageData
        self.cutoutImageData = cutoutImageData
    }
}

struct DetectedGarmentGroup: Identifiable, Sendable {
    let id: UUID
    let category: GarmentCategory
    let candidateIDs: [UUID]
    var selectedGarmentID: UUID?
    let confidence: MatchConfidence
    let source: MatchSource

    init(
        id: UUID = UUID(),
        category: GarmentCategory,
        candidateIDs: [UUID],
        selectedGarmentID: UUID?,
        confidence: MatchConfidence,
        source: MatchSource = .ai
    ) {
        self.id = id
        self.category = category
        self.candidateIDs = candidateIDs
        self.selectedGarmentID = selectedGarmentID
        self.confidence = confidence
        self.source = source
    }
}

enum OutfitAnalysisError: LocalizedError {
    case emptyWardrobe, invalidOutfitPhoto, noComparableGarmentImages

    var errorDescription: String? {
        switch self {
        case .emptyWardrobe:
            "옷장에 등록된 옷이 없어요. 옷을 먼저 등록해 주세요."
        case .invalidOutfitPhoto:
            "착장 사진을 분석할 수 없어요. 다른 사진을 사용해 주세요."
        case .noComparableGarmentImages:
            "비교할 수 있는 옷 사진이 없어요."
        }
    }
}

@MainActor
protocol OutfitAnalyzing {
    func analyze(
        photoData: Data?,
        wardrobe: [GarmentSnapshot]
    ) async throws -> [DetectedGarmentGroup]
}

@MainActor
struct DemoOutfitAnalyzer: OutfitAnalyzing {
    func analyze(
        photoData: Data? = nil,
        wardrobe: [GarmentSnapshot]
    ) async throws -> [DetectedGarmentGroup] {
        guard !wardrobe.isEmpty else { throw OutfitAnalysisError.emptyWardrobe }

        try await Task.sleep(for: .seconds(1.35))

        return Self.preferredOrder.compactMap { category in
            let candidates = wardrobe.filter { $0.category == category }
            guard let first = candidates.first else { return nil }

            return DetectedGarmentGroup(
                category: category,
                candidateIDs: Array(candidates.prefix(3).map(\.id)),
                selectedGarmentID: first.id,
                confidence: category == .bag ? .medium : .high
            )
        }
    }

    nonisolated static let preferredOrder: [GarmentCategory] = [
        .hat, .outer, .top, .dress, .bottom, .shoes, .bag, .accessory,
    ]
}

@MainActor
struct DeviceOutfitAnalyzer: OutfitAnalyzing {
    private let fallback = DemoOutfitAnalyzer()

    func analyze(
        photoData: Data?,
        wardrobe: [GarmentSnapshot]
    ) async throws -> [DetectedGarmentGroup] {
        guard !wardrobe.isEmpty else { throw OutfitAnalysisError.emptyWardrobe }
        guard let photoData else {
            return try await fallback.analyze(photoData: nil, wardrobe: wardrobe)
        }

        do {
            return try await Task.detached(priority: .userInitiated) {
                do {
                    return try Self.analyzeOnDevice(photoData: photoData, wardrobe: wardrobe)
                } catch {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(150))
                }

                do {
                    return try Self.analyzeOnDevice(photoData: photoData, wardrobe: wardrobe)
                } catch {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(300))
                }

                return try Self.analyzeOnDevice(photoData: photoData, wardrobe: wardrobe)
            }.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.analyze(photoData: photoData, wardrobe: wardrobe)
        }
    }

    nonisolated static func rankedCandidateIDs(
        distances: [(id: UUID, distance: Float)],
        fallbackIDs: [UUID]
    ) -> [UUID] {
        let ranked = distances
            .sorted {
                if $0.distance == $1.distance { return $0.id.uuidString < $1.id.uuidString }
                return $0.distance < $1.distance
            }
            .map(\.id)
        return Array((ranked + fallbackIDs.filter { !ranked.contains($0) }).prefix(3))
    }

    private nonisolated static func analyzeOnDevice(
        photoData: Data,
        wardrobe: [GarmentSnapshot]
    ) throws -> [DetectedGarmentGroup] {
        guard let outfitImage = downsampledImage(from: photoData) else {
            throw OutfitAnalysisError.invalidOutfitPhoto
        }

        var comparedImageCount = 0
        let groups = try DemoOutfitAnalyzer.preferredOrder.compactMap { category -> DetectedGarmentGroup? in
            let categoryGarments = wardrobe.filter { $0.category == category }
            guard !categoryGarments.isEmpty,
                  let outfitRegion = crop(outfitImage, for: category) else {
                return nil
            }
            let outfitPrint = try featurePrint(for: outfitRegion)

            let distances: [(id: UUID, distance: Float)] = categoryGarments.compactMap { garment in
                guard let data = garment.cutoutImageData ?? garment.imageData,
                      let garmentImage = downsampledImage(from: data),
                      let garmentPrint = try? featurePrint(for: garmentImage) else {
                    return nil
                }
                var distance: Float = 0
                guard (try? outfitPrint.computeDistance(&distance, to: garmentPrint)) != nil else {
                    return nil
                }
                return (garment.id, distance)
            }
            comparedImageCount += distances.count
            let fallbackIDs = categoryGarments.map(\.id)
            let candidateIDs = rankedCandidateIDs(
                distances: distances,
                fallbackIDs: fallbackIDs
            )
            guard let firstCandidateID = candidateIDs.first else { return nil }
            guard !distances.isEmpty else {
                return DetectedGarmentGroup(
                    category: category,
                    candidateIDs: candidateIDs,
                    selectedGarmentID: firstCandidateID,
                    confidence: .none,
                    source: .ai
                )
            }
            let matchConfidence = confidence(for: distances)

            return DetectedGarmentGroup(
                category: category,
                candidateIDs: candidateIDs,
                selectedGarmentID: matchConfidence == .none ? nil : firstCandidateID,
                confidence: matchConfidence,
                source: .vision
            )
        }

        guard comparedImageCount > 0 else {
            throw OutfitAnalysisError.noComparableGarmentImages
        }
        return groups
    }

    private nonisolated static func featurePrint(
        for image: CGImage
    ) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw OutfitAnalysisError.invalidOutfitPhoto
        }
        return observation
    }

    private nonisolated static func downsampledImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private nonisolated static func crop(
        _ image: CGImage,
        for category: GarmentCategory
    ) -> CGImage? {
        // CGImage pixel coordinates start at the top-left corner.
        let normalizedRect: CGRect = switch category {
        case .hat:
            CGRect(x: 0.12, y: 0.00, width: 0.76, height: 0.28)
        case .outer, .top, .dress:
            CGRect(x: 0.06, y: 0.08, width: 0.88, height: 0.58)
        case .bottom:
            CGRect(x: 0.10, y: 0.38, width: 0.80, height: 0.52)
        case .shoes:
            CGRect(x: 0.08, y: 0.70, width: 0.84, height: 0.30)
        case .bag, .accessory:
            CGRect(x: 0.04, y: 0.08, width: 0.92, height: 0.76)
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixelRect = CGRect(
            x: normalizedRect.minX * bounds.width,
            y: normalizedRect.minY * bounds.height,
            width: normalizedRect.width * bounds.width,
            height: normalizedRect.height * bounds.height
        ).integral.intersection(bounds)
        guard !pixelRect.isEmpty else { return nil }
        return image.cropping(to: pixelRect)
    }

    private nonisolated static func confidence(
        for distances: [(id: UUID, distance: Float)]
    ) -> MatchConfidence {
        let sorted = distances.map(\.distance).sorted()
        guard let best = sorted.first else { return .none }
        guard best < 8 else { return .none }
        guard let second = sorted.dropFirst().first else {
            return .medium
        }
        return second > best * 1.25 ? .high : .medium
    }
}

enum OutfitSelection {
    static func uniqueGarmentIDs(in groups: [DetectedGarmentGroup]) -> [UUID] {
        groups.compactMap(\.selectedGarmentID).reduce(into: []) { result, id in
            guard !result.contains(id) else { return }
            result.append(id)
        }
    }
}
