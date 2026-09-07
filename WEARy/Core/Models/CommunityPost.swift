import Foundation
import SwiftData

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
    var outfit: Outfit?

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
        self.outfit = outfit
    }

    var tags: [String] {
        tagsRaw.split(separator: "|").map(String.init)
    }

    var comments: [String] {
        commentsRaw.split(separator: "\n").map(String.init)
    }

    func appendComment(_ comment: String) {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commentsRaw = commentsRaw.isEmpty ? trimmed : commentsRaw + "\n" + trimmed
    }
}
