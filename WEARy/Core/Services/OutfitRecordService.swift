import Foundation
import SwiftData

enum OutfitRecordError: LocalizedError {
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "착장에는 옷을 한 개 이상 선택해 주세요."
        }
    }
}

@MainActor
enum OutfitRecordService {
    static func update(
        _ outfit: Outfit,
        wornAt: Date,
        note: String,
        selectedGarments: [Garment],
        in context: ModelContext
    ) throws {
        var seenGarmentIDs = Set<UUID>()
        let uniqueGarments = selectedGarments.filter { garment in
            seenGarmentIDs.insert(garment.id).inserted
        }
        guard !uniqueGarments.isEmpty else { throw OutfitRecordError.emptySelection }

        let selectedIDs = Set(uniqueGarments.map(\.id))
        let existingIDs = Set(outfit.items.compactMap(\.garment?.id))
        let orderByGarmentID = Dictionary(
            uniqueKeysWithValues: uniqueGarments.enumerated().map { ($0.element.id, $0.offset) }
        )

        outfit.items
            .filter { item in
                guard let garmentID = item.garment?.id else { return true }
                return !selectedIDs.contains(garmentID)
            }
            .forEach(context.delete)

        for garment in uniqueGarments where !existingIDs.contains(garment.id) {
            context.insert(OutfitItem(
                garment: garment,
                outfit: outfit,
                source: .manual,
                confidence: .none,
                displayOrder: orderByGarmentID[garment.id]
            ))
        }

        for item in outfit.items {
            guard let garmentID = item.garment?.id else { continue }
            item.displayOrder = orderByGarmentID[garmentID]
        }

        outfit.wornAt = wornAt
        outfit.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    static func delete(
        _ outfit: Outfit,
        linkedPosts: [CommunityPost],
        in context: ModelContext
    ) throws {
        linkedPosts.forEach(context.delete)
        context.delete(outfit)
        try context.save()
    }
}
