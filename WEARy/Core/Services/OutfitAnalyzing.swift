import Foundation
import Combine
import CryptoKit
import Darwin
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
    let candidateDistances: [Float?]
    var selectedGarmentID: UUID?
    var wasManuallyAdjusted: Bool
    let confidence: MatchConfidence
    let source: MatchSource

    init(
        id: UUID = UUID(),
        category: GarmentCategory,
        candidateIDs: [UUID],
        candidateDistances: [Float?] = [],
        selectedGarmentID: UUID?,
        wasManuallyAdjusted: Bool = false,
        confidence: MatchConfidence,
        source: MatchSource = .ai
    ) {
        self.id = id
        self.category = category
        self.candidateIDs = candidateIDs
        self.candidateDistances = Array((candidateDistances + Array(repeating: nil, count: candidateIDs.count)).prefix(candidateIDs.count))
        self.selectedGarmentID = selectedGarmentID
        self.wasManuallyAdjusted = wasManuallyAdjusted
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

enum OutfitPhotoQualityIssue: Hashable, Sendable {
    case personNotFound
    case headNotVisible
    case feetNotVisible
}

struct OutfitPhotoQualityAssessment: Equatable, Sendable {
    let issues: [OutfitPhotoQualityIssue]

    var isSuitable: Bool { issues.isEmpty }

    var warningMessage: String {
        if issues.contains(.personNotFound) {
            return "사진에서 사람의 전신을 찾지 못했어요. 머리 끝부터 발끝까지 화면 안에 담아주세요."
        }

        var missingParts: [String] = []
        if issues.contains(.headNotVisible) { missingParts.append("머리") }
        if issues.contains(.feetNotVisible) { missingParts.append("발") }
        return "\(missingParts.joined(separator: "와 ")) 위치가 선명하게 보이지 않아요. 전신을 다시 담으면 옷 추천이 더 정확해져요."
    }

    nonisolated static func evaluate(
        personDetected: Bool,
        headVisible: Bool,
        feetVisible: Bool
    ) -> Self {
        guard personDetected else {
            return Self(issues: [.personNotFound])
        }
        var issues: [OutfitPhotoQualityIssue] = []
        if !headVisible { issues.append(.headNotVisible) }
        if !feetVisible { issues.append(.feetNotVisible) }
        return Self(issues: issues)
    }
}

struct DeviceOutfitPhotoQualityChecker: Sendable {
    func assess(photoData: Data) async -> OutfitPhotoQualityAssessment {
        await Task.detached(priority: .userInitiated) {
            guard let image = DeviceOutfitAnalyzer.downsampledImage(from: photoData) else {
                return OutfitPhotoQualityAssessment.evaluate(
                    personDetected: false, headVisible: false, feetVisible: false
                )
            }

            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.max(by: {
                      Self.visiblePointCount(in: $0) < Self.visiblePointCount(in: $1)
                  }) else {
                return OutfitPhotoQualityAssessment.evaluate(
                    personDetected: false, headVisible: false, feetVisible: false
                )
            }

            let nose = try? observation.recognizedPoint(.nose)
            let ankles = [
                try? observation.recognizedPoint(.leftAnkle),
                try? observation.recognizedPoint(.rightAnkle),
            ].compactMap { $0 }
            return OutfitPhotoQualityAssessment.evaluate(
                personDetected: true,
                headVisible: (nose?.confidence ?? 0) >= 0.2,
                feetVisible: ankles.contains { $0.confidence >= 0.2 }
            )
        }.value
    }

    private nonisolated static func visiblePointCount(
        in observation: VNHumanBodyPoseObservation
    ) -> Int {
        guard let points = try? observation.recognizedPoints(.all) else { return 0 }
        return points.values.filter { $0.confidence >= 0.2 }.count
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
    nonisolated static let hatCategoryHintThreshold: Float = 0.015

    func analyze(
        photoData: Data?,
        wardrobe: [GarmentSnapshot]
    ) async throws -> [DetectedGarmentGroup] {
        guard !wardrobe.isEmpty else { throw OutfitAnalysisError.emptyWardrobe }
        let started = ContinuousClock.now
        guard let photoData else {
            let groups = try await fallback.analyze(photoData: nil, wardrobe: wardrobe)
            OutfitAnalysisDiagnostics.shared.record(started: started, performance: nil)
            return groups
        }

        do {
            let report = try await Task.detached(priority: .userInitiated) {
                do {
                    return try await DeviceVisionEngine.shared.analyze(photoData: photoData, wardrobe: wardrobe)
                } catch {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(150))
                }

                do {
                    return try await DeviceVisionEngine.shared.analyze(photoData: photoData, wardrobe: wardrobe)
                } catch {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(300))
                }

                return try await DeviceVisionEngine.shared.analyze(photoData: photoData, wardrobe: wardrobe)
            }.value
            OutfitAnalysisDiagnostics.shared.record(started: started, performance: report.performance)
            return report.groups
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let groups = try await fallback.analyze(photoData: photoData, wardrobe: wardrobe)
            OutfitAnalysisDiagnostics.shared.record(started: started, performance: nil)
            return groups
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

    /// Feature prints measure visual similarity, not object presence. Keep only
    /// distinctive matches; if none are distinctive, retain the single closest
    /// medium-confidence category so unrelated wardrobe categories are not saved.
    nonisolated static func likelyPresentGroups(
        from groups: [DetectedGarmentGroup],
        categoryHints: [GarmentCategory: Float] = [:]
    ) -> [DetectedGarmentGroup] {
        let visionGroups = groups.filter { $0.source == .vision }
        var highConfidence = visionGroups.filter { $0.confidence == .high }

        // A hat can appear anywhere when the user photographs a laid-out outfit,
        // so the fixed head crop alone is not reliable. A strong whole-image
        // classification restores the ranked wardrobe hat without discarding
        // other high-confidence garments from a full-body photo.
        if categoryHints[.hat, default: 0] >= hatCategoryHintThreshold,
           var hat = visionGroups.first(where: { $0.category == .hat }),
           !highConfidence.contains(where: { $0.category == .hat }) {
            if hat.selectedGarmentID == nil {
                hat.selectedGarmentID = hat.candidateIDs.first
            }
            highConfidence.append(hat)
        }
        if !highConfidence.isEmpty { return highConfidence }

        return visionGroups
            .filter { $0.confidence == .medium }
            .min {
                let left = $0.candidateDistances.first.flatMap { $0 } ?? .greatestFiniteMagnitude
                let right = $1.candidateDistances.first.flatMap { $0 } ?? .greatestFiniteMagnitude
                if left == right {
                    return $0.category.outfitSortOrder < $1.category.outfitSortOrder
                }
                return left < right
            }
            .map { [$0] } ?? []
    }

    nonisolated static func categoryHints(
        from classifications: [(identifier: String, confidence: Float)]
    ) -> [GarmentCategory: Float] {
        let keywords: [GarmentCategory: Set<String>] = [
            .hat: ["hat", "cap", "beanie", "bonnet", "sombrero", "headwear", "fedora"],
            .outer: ["coat", "jacket", "parka", "windbreaker", "overcoat"],
            .top: ["shirt", "jersey", "sweater", "sweatshirt", "cardigan", "blouse", "pullover"],
            .dress: ["dress", "gown"],
            .bottom: ["jean", "jeans", "trouser", "trousers", "pants", "skirt", "shorts"],
            .shoes: ["shoe", "shoes", "sneaker", "sneakers", "boot", "boots", "sandal", "loafer"],
            .bag: ["bag", "handbag", "purse", "backpack", "rucksack"],
            .accessory: ["necktie", "tie", "scarf", "belt", "watch", "necklace", "sunglasses"],
        ]
        var hints: [GarmentCategory: Float] = [:]
        for classification in classifications where classification.confidence > 0 {
            let tokens = Set(
                classification.identifier.lowercased().split { !$0.isLetter }.map(String.init)
            )
            for (category, categoryKeywords) in keywords
            where !tokens.isDisjoint(with: categoryKeywords) {
                hints[category] = max(hints[category] ?? 0, classification.confidence)
            }
        }
        return hints
    }

    fileprivate nonisolated static func categoryHints(from image: CGImage) -> [GarmentCategory: Float] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [:] }
        let classifications = (request.results ?? []).prefix(20).map {
            (identifier: $0.identifier, confidence: $0.confidence)
        }
        return categoryHints(from: classifications)
    }

    fileprivate nonisolated static func analyzeOnDevice(
        photoData: Data,
        wardrobe: [GarmentSnapshot],
        garmentFeaturePrint: (Data) throws -> VNFeaturePrintObservation
    ) throws -> [DetectedGarmentGroup] {
        guard let outfitImage = downsampledImage(from: photoData) else {
            throw OutfitAnalysisError.invalidOutfitPhoto
        }
        let bodyBounds = fullBodyBounds(from: outfitImage)

        var comparedImageCount = 0
        let groups = try DemoOutfitAnalyzer.preferredOrder.compactMap { category -> DetectedGarmentGroup? in
            let categoryGarments = wardrobe.filter { $0.category == category }
            guard !categoryGarments.isEmpty,
                  let outfitRegion = crop(outfitImage, for: category, bodyBounds: bodyBounds) else {
                return nil
            }
            let outfitPrint = try featurePrint(for: outfitRegion)

            let distances: [(id: UUID, distance: Float)] = categoryGarments.compactMap { garment in
                guard let data = garment.cutoutImageData ?? garment.imageData,
                      let garmentPrint = try? garmentFeaturePrint(data) else {
                    return nil
                }
                var distance: Float = 0
                guard (try? outfitPrint.computeDistance(&distance, to: garmentPrint)) != nil else {
                    return nil
                }
                guard distance.isFinite else { return nil }
                return (garment.id, distance)
            }
            comparedImageCount += distances.count
            let fallbackIDs = categoryGarments.map(\.id)
            let candidateIDs = rankedCandidateIDs(
                distances: distances,
                fallbackIDs: fallbackIDs
            )
            let distanceByID = distances.reduce(into: [UUID: Float]()) { $0[$1.id] = $1.distance }
            let candidateDistances = candidateIDs.map { distanceByID[$0] }
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
                candidateDistances: candidateDistances,
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

    fileprivate nonisolated static func featurePrint(
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

    fileprivate nonisolated static func downsampledImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Returns a normalized top-left-origin rectangle only when a person's head
    /// and at least one ankle are visible. Partial poses keep the legacy frame
    /// regions instead of pretending their truncated bounds describe a full body.
    fileprivate nonisolated static func fullBodyBounds(from image: CGImage) -> CGRect? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }

        return (request.results ?? []).compactMap { observation -> CGRect? in
            guard let nose = try? observation.recognizedPoint(.nose), nose.confidence >= 0.2 else {
                return nil
            }
            let ankles = [
                try? observation.recognizedPoint(.leftAnkle),
                try? observation.recognizedPoint(.rightAnkle),
            ].compactMap { $0 }.filter { $0.confidence >= 0.2 }
            guard !ankles.isEmpty,
                  let recognized = try? observation.recognizedPoints(.all) else {
                return nil
            }
            let points = recognized.values
                .filter { $0.confidence >= 0.2 }
                .map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
            guard points.count >= 6 else { return nil }

            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 1
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 1
            let width = max(maxX - minX, 0.08)
            let height = max(maxY - minY, 0.25)
            return CGRect(
                x: minX - width * 0.28,
                y: minY - height * 0.08,
                width: width * 1.56,
                height: height * 1.14
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }.max { $0.width * $0.height < $1.width * $1.height }
    }

    nonisolated static func normalizedCropRect(
        for category: GarmentCategory,
        bodyBounds: CGRect?
    ) -> CGRect {
        guard let bodyBounds, !bodyBounds.isEmpty else {
            return switch category {
            case .hat: CGRect(x: 0.12, y: 0.00, width: 0.76, height: 0.28)
            case .outer, .top, .dress: CGRect(x: 0.06, y: 0.08, width: 0.88, height: 0.58)
            case .bottom: CGRect(x: 0.10, y: 0.38, width: 0.80, height: 0.52)
            case .shoes: CGRect(x: 0.08, y: 0.70, width: 0.84, height: 0.30)
            case .bag, .accessory: CGRect(x: 0.04, y: 0.08, width: 0.92, height: 0.76)
            }
        }

        let relative: CGRect = switch category {
        case .hat:
            CGRect(x: 0.16, y: 0.00, width: 0.68, height: 0.22)
        case .outer, .top:
            CGRect(x: -0.08, y: 0.14, width: 1.16, height: 0.40)
        case .dress:
            CGRect(x: -0.08, y: 0.14, width: 1.16, height: 0.66)
        case .bottom:
            CGRect(x: 0.00, y: 0.46, width: 1.00, height: 0.40)
        case .shoes:
            CGRect(x: -0.08, y: 0.82, width: 1.16, height: 0.18)
        case .bag:
            CGRect(x: -0.32, y: 0.18, width: 1.64, height: 0.58)
        case .accessory:
            CGRect(x: -0.16, y: 0.06, width: 1.32, height: 0.52)
        }
        return CGRect(
            x: bodyBounds.minX + relative.minX * bodyBounds.width,
            y: bodyBounds.minY + relative.minY * bodyBounds.height,
            width: relative.width * bodyBounds.width,
            height: relative.height * bodyBounds.height
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private nonisolated static func crop(
        _ image: CGImage,
        for category: GarmentCategory,
        bodyBounds: CGRect?
    ) -> CGImage? {
        // CGImage pixel coordinates start at the top-left corner.
        let normalizedRect = normalizedCropRect(for: category, bodyBounds: bodyBounds)
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

/// Actor-owned LRU cache. Costs count feature payload bytes, not process memory.
struct FeaturePrintCache<Value> {
    private var entries: [String: (value: Value, cost: Int)] = [:]
    private var order: [String] = []
    let maximumCount: Int
    let maximumBytes: Int
    private(set) var payloadBytes = 0
    var count: Int { entries.count }

    init(maximumCount: Int, maximumBytes: Int) {
        self.maximumCount = max(0, maximumCount)
        self.maximumBytes = max(0, maximumBytes)
    }

    mutating func value(for key: String) -> Value? {
        guard let entry = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return entry.value
    }

    mutating func insert(_ value: Value, for key: String, cost: Int) {
        if let old = entries.removeValue(forKey: key) { payloadBytes -= old.cost }
        order.removeAll { $0 == key }
        guard maximumCount > 0, cost >= 0, cost <= maximumBytes else { return }
        while entries.count >= maximumCount || payloadBytes + cost > maximumBytes {
            guard let oldest = order.first else { break }
            order.removeFirst()
            if let old = entries.removeValue(forKey: oldest) { payloadBytes -= old.cost }
        }
        entries[key] = (value, cost)
        order.append(key)
        payloadBytes += cost
    }

    static func imageKey(_ data: Data) -> String {
        "vision-\(VNGenerateImageFeaturePrintRequest.defaultRevision)-1024-" +
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct VisionAnalysisPerformance: Sendable {
    let cacheHits: Int
    let generatedPrints: Int
    let cachedPrints: Int
    let cachedPayloadBytes: Int
}

struct VisionAnalysisReport: Sendable {
    let groups: [DetectedGarmentGroup]
    let performance: VisionAnalysisPerformance
}

/// Vision observations stay on one actor; they are never shared across workers.
private actor DeviceVisionEngine {
    static let shared = DeviceVisionEngine()
    private var cache = FeaturePrintCache<VNFeaturePrintObservation>(
        maximumCount: 128, maximumBytes: 4 * 1_024 * 1_024
    )

    func analyze(photoData: Data, wardrobe: [GarmentSnapshot]) throws -> VisionAnalysisReport {
        var hits = 0
        var generated = 0
        guard let outfitImage = DeviceOutfitAnalyzer.downsampledImage(from: photoData) else {
            throw OutfitAnalysisError.invalidOutfitPhoto
        }
        let categoryHints = DeviceOutfitAnalyzer.categoryHints(from: outfitImage)
        let comparedGroups = try DeviceOutfitAnalyzer.analyzeOnDevice(
            photoData: photoData, wardrobe: wardrobe
        ) { data in
            try Task.checkCancellation()
            let key = FeaturePrintCache<VNFeaturePrintObservation>.imageKey(data)
            if let observation = cache.value(for: key) {
                hits += 1
                return observation
            }
            guard let image = DeviceOutfitAnalyzer.downsampledImage(from: data) else {
                throw OutfitAnalysisError.noComparableGarmentImages
            }
            let observation = try DeviceOutfitAnalyzer.featurePrint(for: image)
            generated += 1
            cache.insert(observation, for: key, cost: observation.data.count)
            return observation
        }
        let groups = DeviceOutfitAnalyzer.likelyPresentGroups(
            from: comparedGroups,
            categoryHints: categoryHints
        )
        return VisionAnalysisReport(groups: groups, performance: VisionAnalysisPerformance(
            cacheHits: hits, generatedPrints: generated,
            cachedPrints: cache.count, cachedPayloadBytes: cache.payloadBytes
        ))
    }
}

@MainActor
final class OutfitAnalysisDiagnostics: ObservableObject {
    static let shared = OutfitAnalysisDiagnostics()
    @Published private(set) var elapsedMilliseconds: Double?
    @Published private(set) var performance: VisionAnalysisPerformance?

    func record(started: ContinuousClock.Instant, performance: VisionAnalysisPerformance?) {
        let duration = started.duration(to: .now).components
        elapsedMilliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        self.performance = performance
    }
}

struct VisionBenchmarkSample: Sendable {
    let milliseconds: Double
    let performance: VisionAnalysisPerformance
    let peakFootprintBytes: UInt64?
    let memorySampleCount: Int
}

struct VisionBenchmarkResult: Sendable {
    let cold: VisionBenchmarkSample
    let warm: [VisionBenchmarkSample]
    let initialFootprintBytes: UInt64?

    var warmMedianMilliseconds: Double {
        let values = warm.map(\.milliseconds).sorted()
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }
    var maximumObservedFootprintBytes: UInt64? {
        ([initialFootprintBytes, cold.peakFootprintBytes] + warm.map(\.peakFootprintBytes))
            .compactMap { $0 }.max()
    }
    var totalMemorySampleCount: Int {
        cold.memorySampleCount + warm.reduce(0) { $0 + $1.memorySampleCount }
    }
}

private actor ProcessMemoryPeakAccumulator {
    private var maximumBytes: UInt64?
    private var sampleCount = 0

    func record(_ bytes: UInt64?) {
        guard let bytes else { return }
        maximumBytes = max(maximumBytes ?? 0, bytes)
        sampleCount += 1
    }

    func snapshot() -> (maximumBytes: UInt64?, sampleCount: Int) {
        (maximumBytes, sampleCount)
    }
}

enum VisionCacheBenchmark {
    /// A fresh engine isolates this comparison from the normal recording cache.
    /// "Cold" means an empty feature cache, not a cold OS/Vision process.
    nonisolated static func run(
        photoData: Data, wardrobe: [GarmentSnapshot]
    ) async throws -> VisionBenchmarkResult {
        guard !wardrobe.isEmpty else { throw OutfitAnalysisError.emptyWardrobe }
        let engine = DeviceVisionEngine()
        let initial = memoryFootprintBytes()
        let cold = try await measure(engine: engine, photoData: photoData, wardrobe: wardrobe)
        var warm: [VisionBenchmarkSample] = []
        for _ in 0..<3 {
            try Task.checkCancellation()
            warm.append(try await measure(engine: engine, photoData: photoData, wardrobe: wardrobe))
        }
        return VisionBenchmarkResult(cold: cold, warm: warm, initialFootprintBytes: initial)
    }

    private nonisolated static func measure(
        engine: DeviceVisionEngine, photoData: Data, wardrobe: [GarmentSnapshot]
    ) async throws -> VisionBenchmarkSample {
        try Task.checkCancellation()
        let memoryPeak = ProcessMemoryPeakAccumulator()
        await memoryPeak.record(memoryFootprintBytes())
        let sampler = Task(priority: .utility) {
            while !Task.isCancelled {
                await memoryPeak.record(memoryFootprintBytes())
                do {
                    try await Task.sleep(for: .milliseconds(10))
                } catch {
                    break
                }
            }
        }
        let started = ContinuousClock.now
        let report: VisionAnalysisReport
        do {
            // No retry or Mock fallback: failed Vision comparisons must not look like measurements.
            report = try await engine.analyze(photoData: photoData, wardrobe: wardrobe)
        } catch {
            sampler.cancel()
            await sampler.value
            throw error
        }
        let duration = started.duration(to: .now).components
        await memoryPeak.record(memoryFootprintBytes())
        sampler.cancel()
        await sampler.value
        let memorySnapshot = await memoryPeak.snapshot()
        return VisionBenchmarkSample(
            milliseconds: Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15,
            performance: report.performance,
            peakFootprintBytes: memorySnapshot.maximumBytes,
            memorySampleCount: memorySnapshot.sampleCount
        )
    }

    nonisolated static func memoryFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : nil
    }
}

struct OutfitEvaluationScore: Codable, Sendable {
    let garmentID: UUID
    let category: String
    let candidateIDs: [UUID]
    let candidateDistances: [Float?]
    let usedVision: Bool
    let reportedConfidence: String?

    init(garmentID: UUID, category: String, candidateIDs: [UUID],
         candidateDistances: [Float?] = [], usedVision: Bool,
         reportedConfidence: String? = nil) {
        self.garmentID = garmentID
        self.category = category
        self.candidateIDs = candidateIDs
        self.candidateDistances = Array((candidateDistances + Array(repeating: nil, count: candidateIDs.count)).prefix(candidateIDs.count))
        self.usedVision = usedVision
        self.reportedConfidence = reportedConfidence
    }
    var topOneHit: Bool { usedVision && candidateIDs.first == garmentID }
    var topThreeHit: Bool { usedVision && candidateIDs.prefix(3).contains(garmentID) }
    var bestDistance: Float? { candidateDistances.first.flatMap { $0 } }
    var separationRatio: Float? {
        guard let best = bestDistance, best > 0,
              candidateDistances.count > 1, let second = candidateDistances[1] else { return nil }
        return second / best
    }
    var autoSelected: Bool {
        guard usedVision, let reportedConfidence else { return false }
        return reportedConfidence != MatchConfidence.none.rawValue
    }
    var autoSelectionCorrect: Bool { autoSelected && topOneHit }
}

struct OutfitEvaluationResult: Identifiable, Codable, Sendable {
    let id: UUID
    let evaluatedAt: Date
    let analyzerVersion: String
    let scores: [OutfitEvaluationScore]
    var topOneHits: Int { scores.filter(\.topOneHit).count }
    var topThreeHits: Int { scores.filter(\.topThreeHit).count }
    var visionCoveredCount: Int { scores.filter(\.usedVision).count }
    var distanceCoveredCount: Int { scores.filter { $0.bestDistance != nil }.count }
    var autoSelectedCount: Int { scores.filter(\.autoSelected).count }
    var autoSelectionCorrectCount: Int { scores.filter(\.autoSelectionCorrect).count }
    var isValidVisionRun: Bool { visionCoveredCount > 0 }
}

struct ConfidenceCalibrationSummary: Sendable {
    let sampleCount: Int
    let hitCount: Int
    let missCount: Int
    let medianHitDistance: Float?
    let medianMissDistance: Float?
    let separationSampleCount: Int
    var isReadyForExploration: Bool { sampleCount >= 20 && hitCount >= 5 && missCount >= 5 }

    nonisolated static func make(from results: [OutfitEvaluationResult]) -> Self {
        let scores = results.flatMap(\.scores).filter { $0.usedVision && $0.bestDistance != nil }
        let hits = scores.filter(\.topOneHit).compactMap(\.bestDistance)
        let misses = scores.filter { !$0.topOneHit }.compactMap(\.bestDistance)
        return Self(sampleCount: scores.count, hitCount: hits.count, missCount: misses.count,
                    medianHitDistance: median(hits), medianMissDistance: median(misses),
                    separationSampleCount: scores.compactMap(\.separationRatio).count)
    }

    private nonisolated static func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

enum OutfitEvaluationError: LocalizedError {
    case missingGroundTruth, unknownGroundTruth
    var errorDescription: String? {
        switch self {
        case .missingGroundTruth: "사진에 실제로 입은 옷을 한 개 이상 지정해 주세요."
        case .unknownGroundTruth: "정답 옷이 옷장에 없어요. 옷 목록을 다시 확인해 주세요."
        }
    }
}

enum OutfitEvaluation {
    nonisolated static func evaluate(
        groundTruthIDs: Set<UUID>, wardrobe: [GarmentSnapshot], groups: [DetectedGarmentGroup]
    ) throws -> OutfitEvaluationResult {
        guard !groundTruthIDs.isEmpty else { throw OutfitEvaluationError.missingGroundTruth }
        guard groundTruthIDs.isSubset(of: Set(wardrobe.map(\.id))) else {
            throw OutfitEvaluationError.unknownGroundTruth
        }
        let scores = groundTruthIDs.sorted { $0.uuidString < $1.uuidString }.map { id in
            let category = wardrobe.first { $0.id == id }!.category
            let group = groups.first { $0.category == category && $0.source == .vision }
            let allowedIDs = Set(wardrobe.filter { $0.category == category }.map(\.id))
            var seen = Set<UUID>()
            let pairs = zip(group?.candidateIDs ?? [], group?.candidateDistances ?? [])
                .filter { $0.1 != nil && allowedIDs.contains($0.0) && seen.insert($0.0).inserted }
                .prefix(3)
            return OutfitEvaluationScore(garmentID: id, category: category.rawValue,
                                         candidateIDs: pairs.map(\.0), candidateDistances: pairs.map(\.1),
                                         usedVision: group != nil, reportedConfidence: group?.confidence.rawValue)
        }
        return OutfitEvaluationResult(id: UUID(), evaluatedAt: .now,
            analyzerVersion: "Vision-featureprint-\(VNGenerateImageFeaturePrintRequest.defaultRevision)-crop-v1-top3-distance-v1",
            scores: scores)
    }
}

@MainActor
final class OutfitEvaluationSession: ObservableObject {
    static let shared = OutfitEvaluationSession()
    @Published private(set) var results: [OutfitEvaluationResult] = []
    private var photoResultIDs: [String: UUID] = [:]
    var truthCount: Int { results.reduce(0) { $0 + $1.scores.count } }
    var topOneHits: Int { results.reduce(0) { $0 + $1.topOneHits } }
    var topThreeHits: Int { results.reduce(0) { $0 + $1.topThreeHits } }
    var distanceCoveredCount: Int { results.reduce(0) { $0 + $1.distanceCoveredCount } }
    var autoSelectedCount: Int { results.reduce(0) { $0 + $1.autoSelectedCount } }
    var autoSelectionCorrectCount: Int { results.reduce(0) { $0 + $1.autoSelectionCorrectCount } }
    var calibration: ConfidenceCalibrationSummary { .make(from: results) }

    func append(_ result: OutfitEvaluationResult, photoKey: String? = nil) {
        guard result.isValidVisionRun, !results.contains(where: { $0.id == result.id }) else { return }
        if let photoKey, let previousID = photoResultIDs[photoKey] {
            results.removeAll { $0.id == previousID }
        }
        results.append(result)
        if let photoKey { photoResultIDs[photoKey] = result.id }
        if results.count > 50 { results.removeFirst(results.count - 50) }
        let retainedIDs = Set(results.map(\.id))
        photoResultIDs = photoResultIDs.filter { retainedIDs.contains($0.value) }
    }
    func clear() { results.removeAll(); photoResultIDs.removeAll() }
    var exportJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? String(data: encoder.encode(results), encoding: .utf8)) ?? "[]"
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
