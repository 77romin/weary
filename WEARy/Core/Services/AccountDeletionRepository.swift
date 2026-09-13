import Foundation
import Supabase

struct AccountDeletionSummary: Sendable {
    let communityFileCount: Int
    let marketFileCount: Int
}

actor SupabaseAccountDeletionRepository {
    static let shared = SupabaseAccountDeletionRepository()

    func deleteCurrentAccount() async throws -> AccountDeletionSummary {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        let userID = try await SupabaseSessionManager.shared.authenticatedUserID()

        async let communityPaths = ownedCommunityPaths(userID: userID, client: client)
        async let marketPaths = ownedMarketPaths(userID: userID, client: client)
        let (resolvedCommunityPaths, resolvedMarketPaths) = try await (
            communityPaths,
            marketPaths
        )

        try await remove(
            paths: resolvedCommunityPaths,
            bucket: "community-media",
            client: client
        )
        try await remove(
            paths: resolvedMarketPaths,
            bucket: "market-media",
            client: client
        )
        try await client.rpc("delete_current_user").execute()

        return AccountDeletionSummary(
            communityFileCount: resolvedCommunityPaths.count,
            marketFileCount: resolvedMarketPaths.count
        )
    }

    private func ownedCommunityPaths(
        userID: UUID,
        client: SupabaseClient
    ) async throws -> [String] {
        let posts: [OwnedCommunityPost] = try await client
            .from("posts")
            .select(
                "media:post_media(storage_path),items:post_items(image_storage_path)"
            )
            .eq("author_id", value: userID.uuidString)
            .execute()
            .value
        return Array(Set(
            posts.flatMap { post in
                post.media.map(\.storagePath) + post.items.compactMap(\.imageStoragePath)
            }
        ))
    }

    private func ownedMarketPaths(
        userID: UUID,
        client: SupabaseClient
    ) async throws -> [String] {
        let listings: [OwnedMarketListing] = try await client
            .from("market_listings")
            .select(
                "media:market_listing_media(storage_path),verification:market_listing_verifications(cutout_storage_path)"
            )
            .eq("seller_id", value: userID.uuidString)
            .execute()
            .value
        return Array(Set(
            listings.flatMap { listing in
                listing.media.map(\.storagePath)
                    + listing.verification.compactMap(\.cutoutStoragePath)
            }
        ))
    }

    private func remove(
        paths: [String],
        bucket: String,
        client: SupabaseClient
    ) async throws {
        guard !paths.isEmpty else { return }
        for startIndex in stride(from: 0, to: paths.count, by: 100) {
            let endIndex = min(startIndex + 100, paths.count)
            try await client.storage.from(bucket).remove(
                paths: Array(paths[startIndex..<endIndex])
            )
        }
    }
}

private struct OwnedCommunityPost: Decodable, Sendable {
    let media: [OwnedStoragePath]
    let items: [OwnedCommunityItemPath]
}

private struct OwnedMarketListing: Decodable, Sendable {
    let media: [OwnedStoragePath]
    let verification: [OwnedMarketVerificationPath]
}

private struct OwnedStoragePath: Decodable, Sendable {
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case storagePath = "storage_path"
    }
}

private struct OwnedCommunityItemPath: Decodable, Sendable {
    let imageStoragePath: String?

    enum CodingKeys: String, CodingKey {
        case imageStoragePath = "image_storage_path"
    }
}

private struct OwnedMarketVerificationPath: Decodable, Sendable {
    let cutoutStoragePath: String?

    enum CodingKeys: String, CodingKey {
        case cutoutStoragePath = "cutout_storage_path"
    }
}
