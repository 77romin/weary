import Foundation
import Supabase
import SwiftData

protocol CommunityFeedRepository: Sendable {
    func fetchFeed(limit: Int) async throws -> [CommunityFeedPostSnapshot]
}

struct CommunityFeedPostSnapshot: Identifiable, Sendable {
    let id: UUID
    let authorID: UUID
    let authorName: String
    let authorHandle: String
    let authorInitials: String
    let authorAccentHex: String
    let caption: String
    let tags: [String]
    let createdAt: Date
    let likeCount: Int
    let comments: [String]
    let isLiked: Bool
    let isSaved: Bool
    let isFollowing: Bool
    let sourceOutfitID: UUID?
    let outfitPhotoData: Data?
    let outfitItems: [CommunityGarmentSnapshot]
}

actor SupabaseCommunityFeedRepository: CommunityFeedRepository {
    static let shared = SupabaseCommunityFeedRepository()

    private let bucket = "community-media"

    func fetchFeed(limit: Int = 30) async throws -> [CommunityFeedPostSnapshot] {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }

        let currentUserID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let records: [RemotePostRecord] = try await client
            .from("posts")
            .select(
                """
                id,
                author_id,
                source_private_id,
                caption,
                tags,
                created_at,
                author:profiles!posts_author_id_fkey(display_name,handle,avatar_initials,accent_hex),
                media:post_media(storage_path,sort_order),
                items:post_items(id,source_private_id,name_snapshot,brand_snapshot,category_snapshot,size_snapshot,color_hex_snapshot,image_storage_path,sort_order),
                comments(body,created_at,author:profiles!comments_author_id_fkey(display_name)),
                likes:post_likes(user_id),
                saved:bookmarks(user_id)
                """
            )
            .eq("status", value: "active")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let followingRecords: [RemoteFollowRecord] = try await client
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: currentUserID.uuidString)
            .eq("status", value: "accepted")
            .execute()
            .value
        let followingIDs = Set(followingRecords.map(\.followingID))

        var snapshots: [CommunityFeedPostSnapshot] = []
        snapshots.reserveCapacity(records.count)

        for record in records {
            let isCurrentUser = record.authorID == currentUserID
            let mediaPath = record.media.min(by: { $0.sortOrder < $1.sortOrder })?.storagePath
            let photoData = await download(path: mediaPath, using: client)
            var garments: [CommunityGarmentSnapshot] = []

            for item in record.items.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let cutoutData = await download(path: item.imageStoragePath, using: client)
                garments.append(CommunityGarmentSnapshot(
                    id: item.sourcePrivateID ?? item.id,
                    name: item.nameSnapshot,
                    brand: item.brandSnapshot,
                    size: item.sizeSnapshot,
                    categoryRaw: item.categorySnapshot,
                    colorHex: item.colorHexSnapshot,
                    cutoutImageData: cutoutData
                ))
            }

            let comments = record.comments
                .sorted(by: { $0.createdAt < $1.createdAt })
                .map { "\($0.author.displayName): \($0.body)" }

            snapshots.append(CommunityFeedPostSnapshot(
                id: record.id,
                authorID: record.authorID,
                authorName: isCurrentUser ? "나" : record.author.displayName,
                authorHandle: isCurrentUser ? "my.weary" : (record.author.handle ?? "weary"),
                authorInitials: isCurrentUser ? "ME" : record.author.avatarInitials,
                authorAccentHex: record.author.accentHex,
                caption: record.caption,
                tags: record.tags,
                createdAt: record.createdAt,
                likeCount: record.likes.count,
                comments: comments,
                isLiked: record.likes.contains { $0.userID == currentUserID },
                isSaved: !record.saved.isEmpty,
                isFollowing: followingIDs.contains(record.authorID),
                sourceOutfitID: record.sourcePrivateID,
                outfitPhotoData: photoData,
                outfitItems: garments
            ))
        }

        return snapshots
    }

    private func download(path: String?, using client: SupabaseClient) async -> Data? {
        guard let path, !path.isEmpty else { return nil }
        return try? await client.storage.from(bucket).download(path: path)
    }
}

struct RemotePostRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let sourcePrivateID: UUID?
    let caption: String
    let tags: [String]
    let createdAt: Date
    let author: RemoteProfileRecord
    let media: [RemotePostMediaRecord]
    let items: [RemotePostItemRecord]
    let comments: [RemoteCommentRecord]
    let likes: [RemoteUserReactionRecord]
    let saved: [RemoteUserReactionRecord]

    enum CodingKeys: String, CodingKey {
        case id, caption, tags, author, media, items, comments, likes, saved
        case authorID = "author_id"
        case sourcePrivateID = "source_private_id"
        case createdAt = "created_at"
    }
}

struct RemoteProfileRecord: Decodable, Sendable {
    let displayName: String
    let handle: String?
    let avatarInitials: String
    let accentHex: String

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case avatarInitials = "avatar_initials"
        case accentHex = "accent_hex"
    }
}

struct RemotePostMediaRecord: Decodable, Sendable {
    let storagePath: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
    }
}

struct RemotePostItemRecord: Decodable, Sendable {
    let id: UUID
    let sourcePrivateID: UUID?
    let nameSnapshot: String
    let brandSnapshot: String
    let categorySnapshot: String
    let sizeSnapshot: String
    let colorHexSnapshot: String
    let imageStoragePath: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case sourcePrivateID = "source_private_id"
        case nameSnapshot = "name_snapshot"
        case brandSnapshot = "brand_snapshot"
        case categorySnapshot = "category_snapshot"
        case sizeSnapshot = "size_snapshot"
        case colorHexSnapshot = "color_hex_snapshot"
        case imageStoragePath = "image_storage_path"
        case sortOrder = "sort_order"
    }
}

struct RemoteCommentRecord: Decodable, Sendable {
    let body: String
    let createdAt: Date
    let author: RemoteCommentAuthorRecord

    enum CodingKeys: String, CodingKey {
        case body, author
        case createdAt = "created_at"
    }
}

struct RemoteCommentAuthorRecord: Decodable, Sendable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct RemoteUserReactionRecord: Decodable, Sendable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

struct RemoteFollowRecord: Decodable, Sendable {
    let followingID: UUID

    enum CodingKeys: String, CodingKey {
        case followingID = "following_id"
    }
}

@MainActor
enum CommunityFeedCacheStore {
    static func replaceRemoteWindow(
        with snapshots: [CommunityFeedPostSnapshot],
        in modelContext: ModelContext
    ) throws {
        let cachedRemotePosts = try modelContext.fetch(
            FetchDescriptor<CommunityPost>(predicate: #Predicate { $0.isSyncedFromServer == true })
        )
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedRemotePosts.map { ($0.id, $0) })
        let receivedIDs = Set(snapshots.map(\.id))

        for snapshot in snapshots {
            if let cachedPost = cachedByID[snapshot.id] {
                cachedPost.applyServerSnapshot(snapshot)
            } else {
                let post = CommunityPost(
                    id: snapshot.id,
                    authorName: snapshot.authorName,
                    authorHandle: snapshot.authorHandle,
                    authorInitials: snapshot.authorInitials,
                    caption: snapshot.caption,
                    tags: snapshot.tags,
                    createdAt: snapshot.createdAt,
                    accentHex: snapshot.authorAccentHex,
                    isSyncedFromServer: true,
                    serverAuthorID: snapshot.authorID
                )
                post.applyServerSnapshot(snapshot)
                modelContext.insert(post)
            }
        }

        for cachedPost in cachedRemotePosts where !receivedIDs.contains(cachedPost.id) {
            modelContext.delete(cachedPost)
        }

        try modelContext.save()
    }
}
