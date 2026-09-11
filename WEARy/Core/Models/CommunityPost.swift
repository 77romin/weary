import Foundation
import SwiftData

struct CommunityGarmentSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let brand: String
    let size: String
    let categoryRaw: String
    let colorHex: String
    let cutoutImageData: Data?

    init(garment: Garment) {
        id = garment.id
        name = garment.name
        brand = garment.brand
        size = garment.size
        categoryRaw = garment.categoryRaw
        colorHex = garment.colorHex
        cutoutImageData = garment.cutoutImageData
    }

    var category: GarmentCategory {
        GarmentCategory(rawValue: categoryRaw) ?? .top
    }
}

@Model
final class CommunityPost {
    @Attribute(.unique) var id: UUID
    var authorName: String
    var authorHandle: String
    var authorInitials: String
    var caption: String
    var tagsRaw: String
    var createdAt: Date
    var likeCount: Int
    var commentsRaw: String
    var isLiked: Bool
    var isSaved: Bool
    var isFollowing: Bool
    var accentHex: String
    var sourceOutfitID: UUID?
    var outfitWornAt: Date?
    @Attribute(.externalStorage) var outfitPhotoData: Data?
    @Attribute(.externalStorage) var outfitItemsData: Data?

    init(
        id: UUID = UUID(),
        authorName: String,
        authorHandle: String,
        authorInitials: String,
        caption: String,
        tags: [String] = [],
        createdAt: Date = .now,
        likeCount: Int = 0,
        comments: [String] = [],
        isLiked: Bool = false,
        isSaved: Bool = false,
        isFollowing: Bool = false,
        accentHex: String = "A7B9CE",
        outfit: Outfit? = nil
    ) {
        self.id = id
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.authorInitials = authorInitials
        self.caption = caption
        tagsRaw = tags.joined(separator: "|")
        self.createdAt = createdAt
        self.likeCount = likeCount
        commentsRaw = comments.joined(separator: "\n")
        self.isLiked = isLiked
        self.isSaved = isSaved
        self.isFollowing = isFollowing
        self.accentHex = accentHex
        captureSnapshot(from: outfit)
    }

    var tags: [String] {
        get { tagsRaw.split(separator: "|").map(String.init) }
        set { tagsRaw = newValue.joined(separator: "|") }
    }

    var comments: [String] {
        commentsRaw.split(separator: "\n").map(String.init)
    }

    func appendComment(_ comment: String) {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commentsRaw = commentsRaw.isEmpty ? trimmed : commentsRaw + "\n" + trimmed
    }

    var outfitItems: [CommunityGarmentSnapshot] {
        guard let outfitItemsData else { return [] }
        return (try? PropertyListDecoder().decode([CommunityGarmentSnapshot].self, from: outfitItemsData)) ?? []
    }

    func captureSnapshot(from outfit: Outfit?) {
        guard let outfit else { return }
        sourceOutfitID = outfit.id
        outfitWornAt = outfit.wornAt
        outfitPhotoData = outfit.photoData
        let snapshots = outfit.orderedItems.compactMap(\.garment).map(CommunityGarmentSnapshot.init)
        outfitItemsData = try? PropertyListEncoder().encode(snapshots)
    }
}
