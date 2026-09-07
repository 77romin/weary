import Foundation

struct GarmentSnapshot: Sendable {
    let id: UUID
    let category: GarmentCategory
    let name: String
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
    case emptyWardrobe

    var errorDescription: String? {
        switch self {
        case .emptyWardrobe:
            "옷장에 등록된 옷이 없어요. 옷을 먼저 등록해 주세요."
        }
    }
}

@MainActor
protocol OutfitAnalyzing {
    func analyze(wardrobe: [GarmentSnapshot]) async throws -> [DetectedGarmentGroup]
}

@MainActor
struct DemoOutfitAnalyzer: OutfitAnalyzing {
    func analyze(wardrobe: [GarmentSnapshot]) async throws -> [DetectedGarmentGroup] {
        guard !wardrobe.isEmpty else { throw OutfitAnalysisError.emptyWardrobe }

        try await Task.sleep(for: .seconds(1.35))

        let preferredOrder: [GarmentCategory] = [.outer, .top, .bottom, .shoes, .bag]
        return preferredOrder.compactMap { category in
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
}

enum OutfitSelection {
    static func uniqueGarmentIDs(in groups: [DetectedGarmentGroup]) -> [UUID] {
        groups.compactMap(\.selectedGarmentID).reduce(into: []) { result, id in
            guard !result.contains(id) else { return }
            result.append(id)
        }
    }
}
