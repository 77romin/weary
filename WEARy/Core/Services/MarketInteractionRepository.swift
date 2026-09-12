import Foundation
import Supabase

protocol MarketInteractionServing: Sendable {
    func setFavorite(listingID: UUID, isFavorite: Bool) async throws
}

actor SupabaseMarketInteractionRepository: MarketInteractionServing {
    static let shared = SupabaseMarketInteractionRepository()

    func setFavorite(listingID: UUID, isFavorite: Bool) async throws {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        let userID = try await SupabaseSessionManager.shared.authenticatedUserID()

        if isFavorite {
            try await client
                .from("market_listing_favorites")
                .upsert(
                    MarketFavoriteInsert(listingID: listingID, userID: userID),
                    onConflict: "listing_id,user_id",
                    returning: .minimal,
                    ignoreDuplicates: true
                )
                .execute()
        } else {
            try await client
                .from("market_listing_favorites")
                .delete()
                .eq("listing_id", value: listingID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
    }
}

actor SupabaseMarketRealtimeRepository {
    static let shared = SupabaseMarketRealtimeRepository()

    private var channel: RealtimeChannelV2?
    private var subscriptions: [RealtimeSubscription] = []
    private var continuation: AsyncStream<Void>.Continuation?

    func events() async throws -> AsyncStream<Void> {
        await stop()
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        _ = try await SupabaseSessionManager.shared.authenticatedUserID()

        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let channel = client.channel("market-feed-\(UUID().uuidString)")
        let tables = [
            "profiles",
            "market_listings",
            "market_listing_media",
            "market_listing_verifications",
            "market_listing_favorites",
            "market_conversations",
            "user_blocks",
        ]

        subscriptions = tables.map { table in
            channel.onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: table
            ) { _ in
                continuation.yield()
            }
        }
        self.channel = channel
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }

        do {
            try await channel.subscribeWithError()
            return stream
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        if let channel, let client = SupabaseService.client {
            await client.removeChannel(channel)
        }
        channel = nil
    }
}

private struct MarketFavoriteInsert: Encodable, Sendable {
    let listingID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case listingID = "listing_id"
        case userID = "user_id"
    }
}
