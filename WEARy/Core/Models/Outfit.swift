import Foundation
import SwiftData

enum MatchSource: String, Codable {
    case ai
    case manual
}

enum MatchConfidence: String, Codable {
    case high
    case medium
    case none
}

@Model
final class Outfit {
    @Attribute(.unique) var id: UUID
    var wornAt: Date
    var note: String
    var isConfirmed: Bool
    var isPublished: Bool
    var createdAt: Date
    var photoData: Data?

    @Relationship(deleteRule: .cascade, inverse: \OutfitItem.outfit)
    var items: [OutfitItem] = []

    init(
        id: UUID = UUID(),
        wornAt: Date,
        note: String = "",
        isConfirmed: Bool = true,
        isPublished: Bool = false,
        createdAt: Date = .now,
        photoData: Data? = nil
    ) {
        self.id = id
        self.wornAt = wornAt
        self.note = note
        self.isConfirmed = isConfirmed
        self.isPublished = isPublished
        self.createdAt = createdAt
        self.photoData = photoData
    }
}

@Model
final class OutfitItem {
    @Attribute(.unique) var id: UUID
    var sourceRaw: String
    var confidenceRaw: String
    var garment: Garment?
    var outfit: Outfit?

    init(
        id: UUID = UUID(),
        garment: Garment,
        outfit: Outfit,
        source: MatchSource = .manual,
        confidence: MatchConfidence = .none
    ) {
        self.id = id
        self.garment = garment
        self.outfit = outfit
        sourceRaw = source.rawValue
        confidenceRaw = confidence.rawValue
    }
}
