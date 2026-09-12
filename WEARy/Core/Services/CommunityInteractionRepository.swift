import Foundation
import Supabase

protocol CommunityInteractionServing: Sendable {
    func setLike(postID: UUID, isLiked: Bool) async throws
    func setBookmark(postID: UUID, isSaved: Bool) async throws
    func addComment(postID: UUID, body: String) async throws
    func setFollowing(authorID: UUID, isFollowing: Bool) async throws
    func fetchSocialGraph() async throws -> CommunitySocialGraphSnapshot
}

struct CommunitySocialGraphSnapshot: Sendable {
    let followers: [CommunitySocialUserSnapshot]
    let following: [CommunitySocialUserSnapshot]
}

struct CommunitySocialUserSnapshot: Identifiable, Sendable {
    let id: UUID
    let name: String
    let handle: String
    let initials: String
    let accentHex: String
}

actor SupabaseCommunityInteractionRepository: CommunityInteractionServing {
    static let shared = SupabaseCommunityInteractionRepository()

    func setLike(postID: UUID, isLiked: Bool) async throws {
        let (client, userID) = try await authenticatedContext()
        if isLiked {
            try await client
                .from("post_likes")
                .upsert(
                    UserPostReactionInsert(postID: postID, userID: userID),
                    onConflict: "post_id,user_id",
                    returning: .minimal,
                    ignoreDuplicates: true
                )
                .execute()
        } else {
            try await client
                .from("post_likes")
                .delete()
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
    }

    func setBookmark(postID: UUID, isSaved: Bool) async throws {
        let (client, userID) = try await authenticatedContext()
        if isSaved {
            try await client
                .from("bookmarks")
                .upsert(
                    UserPostReactionInsert(postID: postID, userID: userID),
                    onConflict: "post_id,user_id",
                    returning: .minimal,
                    ignoreDuplicates: true
                )
                .execute()
        } else {
            try await client
                .from("bookmarks")
                .delete()
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
    }

    func addComment(postID: UUID, body: String) async throws {
        let (client, userID) = try await authenticatedContext()
        try await client
            .from("comments")
            .insert(CommentInsert(postID: postID, authorID: userID, body: body))
            .execute()
    }

    func setFollowing(authorID: UUID, isFollowing: Bool) async throws {
        let (client, userID) = try await authenticatedContext()
        guard authorID != userID else { return }

        if isFollowing {
            try await client
                .from("follows")
                .upsert(
                    FollowInsert(followerID: userID, followingID: authorID),
                    onConflict: "follower_id,following_id",
                    returning: .minimal,
                    ignoreDuplicates: true
                )
                .execute()
        } else {
            try await client
                .from("follows")
                .delete()
                .eq("follower_id", value: userID.uuidString)
                .eq("following_id", value: authorID.uuidString)
                .execute()
        }
    }

    func fetchSocialGraph() async throws -> CommunitySocialGraphSnapshot {
        let (client, userID) = try await authenticatedContext()
        let blockedUserIDs = try await SupabaseContentSafetyRepository.shared.fetchBlockedUserIDs()
        let followingRows: [RemoteSocialRelation] = try await client
            .from("follows")
            .select(
                "profile:profiles!follows_following_id_fkey(id,display_name,handle,avatar_initials,accent_hex)"
            )
            .eq("follower_id", value: userID.uuidString)
            .eq("status", value: "accepted")
            .execute()
            .value
        let followerRows: [RemoteSocialRelation] = try await client
            .from("follows")
            .select(
                "profile:profiles!follows_follower_id_fkey(id,display_name,handle,avatar_initials,accent_hex)"
            )
            .eq("following_id", value: userID.uuidString)
            .eq("status", value: "accepted")
            .execute()
            .value

        return CommunitySocialGraphSnapshot(
            followers: followerRows.map(\.profile.snapshot).filter { !blockedUserIDs.contains($0.id) },
            following: followingRows.map(\.profile.snapshot).filter { !blockedUserIDs.contains($0.id) }
        )
    }

    private func authenticatedContext() async throws -> (SupabaseClient, UUID) {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        return (client, try await SupabaseSessionManager.shared.authenticatedUserID())
    }
}

private struct UserPostReactionInsert: Encodable, Sendable {
    let postID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
    }
}

private struct CommentInsert: Encodable, Sendable {
    let postID: UUID
    let authorID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case body
        case postID = "post_id"
        case authorID = "author_id"
    }
}

private struct FollowInsert: Encodable, Sendable {
    let followerID: UUID
    let followingID: UUID

    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followingID = "following_id"
    }
}

private struct RemoteSocialRelation: Decodable, Sendable {
    let profile: RemoteSocialProfile
}

private struct RemoteSocialProfile: Decodable, Sendable {
    let id: UUID
    let displayName: String
    let handle: String?
    let avatarInitials: String
    let accentHex: String

    enum CodingKeys: String, CodingKey {
        case id, handle
        case displayName = "display_name"
        case avatarInitials = "avatar_initials"
        case accentHex = "accent_hex"
    }

    var snapshot: CommunitySocialUserSnapshot {
        CommunitySocialUserSnapshot(
            id: id,
            name: displayName,
            handle: handle ?? "weary_\(id.uuidString.prefix(8))",
            initials: avatarInitials,
            accentHex: accentHex
        )
    }
}
