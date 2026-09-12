import Foundation
import SwiftData

struct CommunityGarmentSnapshot: Codable, Identifiable, Equatable, Sendable {
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

    init(
        id: UUID,
        name: String,
        brand: String,
        size: String,
        categoryRaw: String,
        colorHex: String,
        cutoutImageData: Data?
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.size = size
        self.categoryRaw = categoryRaw
        self.colorHex = colorHex
        self.cutoutImageData = cutoutImageData
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
    var isSyncedFromServer: Bool?
    var serverAuthorID: UUID?
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
        outfit: Outfit? = nil,
        isSyncedFromServer: Bool = false,
        serverAuthorID: UUID? = nil
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
        self.isSyncedFromServer = isSyncedFromServer
        self.serverAuthorID = serverAuthorID
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

    func applyServerSnapshot(_ snapshot: CommunityFeedPostSnapshot) {
        authorName = snapshot.authorName
        authorHandle = snapshot.authorHandle
        authorInitials = snapshot.authorInitials
        caption = snapshot.caption
        tags = snapshot.tags
        createdAt = snapshot.createdAt
        likeCount = snapshot.likeCount
        commentsRaw = snapshot.comments.joined(separator: "\n")
        isLiked = snapshot.isLiked
        isSaved = snapshot.isSaved
        isFollowing = snapshot.isFollowing
        accentHex = snapshot.authorAccentHex
        sourceOutfitID = snapshot.sourceOutfitID
        outfitPhotoData = snapshot.outfitPhotoData
        outfitItemsData = try? PropertyListEncoder().encode(snapshot.outfitItems)
        isSyncedFromServer = true
        serverAuthorID = snapshot.authorID
    }
}
