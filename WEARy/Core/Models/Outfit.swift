import Foundation
import SwiftData

enum MatchSource: String, Codable {
    case ai
    case vision
    case manual
}

enum MatchConfidence: String, Codable {
    case high
    case medium
    case none
}

@Model
final class Outfit {
    var id: UUID = UUID()
    var wornAt: Date = Date.now
    var note: String = ""
    var isConfirmed: Bool = true
    var isPublished: Bool = false
    var createdAt: Date = Date.now
    var aiAnalysisAttempted: Bool = false
    var visionCandidateCount: Int = 0
    var visionAcceptedCount: Int = 0
    var visionTopOneAcceptedCount: Int = 0
    var visionAdjustedCount: Int = 0
    var aiAnalysisUsedFallback: Bool = false
    @Attribute(.externalStorage) var photoData: Data?

    @Relationship(deleteRule: .cascade, inverse: \OutfitItem.outfit)
    var items: [OutfitItem] = []

    init(
        id: UUID = UUID(),
        wornAt: Date,
        note: String = "",
        isConfirmed: Bool = true,
        isPublished: Bool = false,
        createdAt: Date = .now,
        aiAnalysisAttempted: Bool = false,
        visionCandidateCount: Int = 0,
        visionAcceptedCount: Int = 0,
        visionTopOneAcceptedCount: Int = 0,
        visionAdjustedCount: Int = 0,
        aiAnalysisUsedFallback: Bool = false,
        photoData: Data? = nil
    ) {
        self.id = id
        self.wornAt = wornAt
        self.note = note
        self.isConfirmed = isConfirmed
        self.isPublished = isPublished
        self.createdAt = createdAt
        self.aiAnalysisAttempted = aiAnalysisAttempted
        self.visionCandidateCount = visionCandidateCount
        self.visionAcceptedCount = visionAcceptedCount
        self.visionTopOneAcceptedCount = visionTopOneAcceptedCount
        self.visionAdjustedCount = visionAdjustedCount
        self.aiAnalysisUsedFallback = aiAnalysisUsedFallback
        self.photoData = photoData
    }

    var orderedItems: [OutfitItem] {
        let hasCustomOrder = items.contains { $0.displayOrder != nil }
        return items.sorted { lhs, rhs in
            if hasCustomOrder {
                let leftOrder = lhs.displayOrder ?? Int.max
                let rightOrder = rhs.displayOrder ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
            }

            let leftCategory = lhs.garment?.category.outfitSortOrder ?? Int.max
            let rightCategory = rhs.garment?.category.outfitSortOrder ?? Int.max
            if leftCategory != rightCategory { return leftCategory < rightCategory }
            return (lhs.garment?.name ?? "") < (rhs.garment?.name ?? "")
        }
    }

    func applyItemOrder(_ orderedIDs: [UUID]) {
        let positions = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        for item in items {
            item.displayOrder = positions[item.id]
        }
    }
}

@Model
final class OutfitItem {
    var id: UUID = UUID()
    var sourceRaw: String = "manual"
    var confidenceRaw: String = "none"
    var suggestedRank: Int?
    var wasManuallyAdjusted: Bool = false
    var displayOrder: Int?
    var garment: Garment?
    var outfit: Outfit?

    init(
        id: UUID = UUID(),
        garment: Garment,
        outfit: Outfit,
        source: MatchSource = .manual,
        confidence: MatchConfidence = .none,
        suggestedRank: Int? = nil,
        wasManuallyAdjusted: Bool = false,
        displayOrder: Int? = nil
    ) {
        self.id = id
        self.garment = garment
        self.outfit = outfit
        sourceRaw = source.rawValue
        confidenceRaw = confidence.rawValue
        self.suggestedRank = suggestedRank
        self.wasManuallyAdjusted = wasManuallyAdjusted
        self.displayOrder = displayOrder
    }

    var matchSource: MatchSource {
        MatchSource(rawValue: sourceRaw) ?? .manual
    }
}
