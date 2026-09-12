import Foundation
import Supabase
import SwiftData

protocol MarketListingRepository: Sendable {
    func fetchListings(limit: Int) async throws -> [MarketListingSnapshot]
}

struct MarketListingSnapshot: Identifiable, Sendable {
    let id: UUID
    let sellerID: UUID
    let sellerName: String
    let title: String
    let detailText: String
    let price: Int
    let previousPrice: Int?
    let size: String
    let condition: ListingCondition
    let status: ListingStatus
    let createdAt: Date
    let isLiked: Bool
    let accentHex: String
    let meetingPlace: String?
    let meetingAddress: String?
    let meetingLatitude: Double?
    let meetingLongitude: Double?
    let chatCount: Int
    let galleryImages: [Data]
    let showsWardrobeVerification: Bool
    let sourceGarmentID: UUID?
    let garmentNameSnapshot: String?
    let garmentBrandSnapshot: String?
    let garmentCategoryRawSnapshot: String?
    let garmentColorHexSnapshot: String?
    let garmentCutoutImageDataSnapshot: Data?
    let verificationPurchasePrice: Int?
    let verificationLastWornAt: Date?
    let verificationWearCount: Int?
    let isOwnedByCurrentUser: Bool
}

actor SupabaseMarketListingRepository: MarketListingRepository {
    static let shared = SupabaseMarketListingRepository()

    private let bucket = "market-media"

    func fetchListings(limit: Int = 30) async throws -> [MarketListingSnapshot] {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }

        let currentUserID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let safeLimit = min(max(limit, 1), 100)
        let records: [RemoteMarketListingRecord] = try await client
            .from("market_listings")
            .select(
                """
                id,
                seller_id,
                source_private_id,
                title,
                description,
                price,
                previous_price,
                brand_snapshot,
                category_snapshot,
                size_snapshot,
                color_hex_snapshot,
                condition,
                status,
                meeting_name,
                meeting_address,
                meeting_latitude,
                meeting_longitude,
                created_at,
                seller:profiles!market_listings_seller_id_fkey(display_name),
                media:market_listing_media(storage_path,sort_order),
                favorites:market_listing_favorites(user_id),
                conversations:market_conversations(id)
                """
            )
            .in("status", values: ["active", "reserved", "sold"])
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(safeLimit)
            .execute()
            .value

        guard !records.isEmpty else { return [] }
        let listingIDs = records.map { $0.id.uuidString }
        let verifications: [RemoteMarketVerificationRecord] = try await client
            .from("market_listing_verifications")
            .select(
                "listing_id,source_private_id,garment_name_snapshot,purchase_price,last_worn_at,wear_count,cutout_storage_path,is_visible"
            )
            .in("listing_id", values: listingIDs)
            .execute()
            .value
        let verificationByListingID = Dictionary(
            uniqueKeysWithValues: verifications.map { ($0.listingID, $0) }
        )

        var snapshots: [MarketListingSnapshot] = []
        snapshots.reserveCapacity(records.count)

        for record in records {
            let verification = verificationByListingID[record.id]
            var galleryImages: [Data] = []
            for media in record.media.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                if let image = await download(path: media.storagePath, using: client) {
                    galleryImages.append(image)
                }
            }
            let cutoutImage = await download(path: verification?.cutoutStoragePath, using: client)
            let isOwned = record.sellerID == currentUserID

            snapshots.append(MarketListingSnapshot(
                id: record.id,
                sellerID: record.sellerID,
                sellerName: record.seller.displayName,
                title: record.title,
                detailText: record.description,
                price: record.price,
                previousPrice: record.previousPrice,
                size: record.sizeSnapshot,
                condition: record.listingCondition,
                status: record.listingStatus,
                createdAt: record.createdAt,
                isLiked: record.favorites.contains { $0.userID == currentUserID },
                accentHex: record.colorHexSnapshot,
                meetingPlace: record.meetingName,
                meetingAddress: record.meetingAddress,
                meetingLatitude: record.meetingLatitude,
                meetingLongitude: record.meetingLongitude,
                chatCount: isOwned ? record.conversations.count : 0,
                galleryImages: galleryImages,
                showsWardrobeVerification: verification?.isVisible ?? false,
                sourceGarmentID: verification?.sourcePrivateID ?? (isOwned ? record.sourcePrivateID : nil),
                garmentNameSnapshot: verification?.garmentNameSnapshot,
                garmentBrandSnapshot: record.brandSnapshot,
                garmentCategoryRawSnapshot: record.categorySnapshot,
                garmentColorHexSnapshot: record.colorHexSnapshot,
                garmentCutoutImageDataSnapshot: cutoutImage,
                verificationPurchasePrice: verification?.purchasePrice,
                verificationLastWornAt: verification?.lastWornAt,
                verificationWearCount: verification?.wearCount,
                isOwnedByCurrentUser: isOwned
            ))
        }

        return snapshots
    }

    private func download(path: String?, using client: SupabaseClient) async -> Data? {
        guard let path, !path.isEmpty else { return nil }
        return try? await client.storage.from(bucket).download(path: path)
    }
}

private struct RemoteMarketListingRecord: Decodable, Sendable {
    let id: UUID
    let sellerID: UUID
    let sourcePrivateID: UUID?
    let title: String
    let description: String
    let price: Int
    let previousPrice: Int?
    let brandSnapshot: String
    let categorySnapshot: String
    let sizeSnapshot: String
    let colorHexSnapshot: String
    let condition: String
    let status: String
    let meetingName: String?
    let meetingAddress: String?
    let meetingLatitude: Double?
    let meetingLongitude: Double?
    let createdAt: Date
    let seller: RemoteMarketSellerRecord
    let media: [RemoteMarketMediaRecord]
    let favorites: [RemoteMarketFavoriteRecord]
    let conversations: [RemoteMarketConversationReference]

    var listingCondition: ListingCondition {
        switch condition {
        case "like_new": .likeNew
        case "good": .good
        default: .excellent
        }
    }

    var listingStatus: ListingStatus {
        switch status {
        case "reserved": .reserved
        case "sold": .sold
        default: .active
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, price, condition, status, seller, media, favorites, conversations
        case sellerID = "seller_id"
        case sourcePrivateID = "source_private_id"
        case previousPrice = "previous_price"
        case brandSnapshot = "brand_snapshot"
        case categorySnapshot = "category_snapshot"
        case sizeSnapshot = "size_snapshot"
        case colorHexSnapshot = "color_hex_snapshot"
        case meetingName = "meeting_name"
        case meetingAddress = "meeting_address"
        case meetingLatitude = "meeting_latitude"
        case meetingLongitude = "meeting_longitude"
        case createdAt = "created_at"
    }
}

private struct RemoteMarketSellerRecord: Decodable, Sendable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct RemoteMarketMediaRecord: Decodable, Sendable {
    let storagePath: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
    }
}

private struct RemoteMarketFavoriteRecord: Decodable, Sendable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

private struct RemoteMarketConversationReference: Decodable, Sendable {
    let id: UUID
}

private struct RemoteMarketVerificationRecord: Decodable, Sendable {
    let listingID: UUID
    let sourcePrivateID: UUID
    let garmentNameSnapshot: String
    let purchasePrice: Int?
    let lastWornAt: Date?
    let wearCount: Int?
    let cutoutStoragePath: String?
    let isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case listingID = "listing_id"
        case sourcePrivateID = "source_private_id"
        case garmentNameSnapshot = "garment_name_snapshot"
        case purchasePrice = "purchase_price"
        case lastWornAt = "last_worn_at"
        case wearCount = "wear_count"
        case cutoutStoragePath = "cutout_storage_path"
        case isVisible = "is_visible"
    }
}

@MainActor
enum MarketListingCacheStore {
    static func replaceRemoteListings(
        with snapshots: [MarketListingSnapshot],
        in modelContext: ModelContext
    ) throws {
        let cachedRemoteListings = try modelContext.fetch(
            FetchDescriptor<MarketListing>(predicate: #Predicate { $0.isSyncedFromServer == true })
        )
        let cachedByID = Dictionary(
            uniqueKeysWithValues: cachedRemoteListings.map { ($0.id, $0) }
        )
        let receivedIDs = Set(snapshots.map(\.id))

        for snapshot in snapshots {
            if let cachedListing = cachedByID[snapshot.id] {
                cachedListing.applyServerSnapshot(snapshot)
            } else {
                let listing = MarketListing(
                    id: snapshot.id,
                    sellerName: snapshot.sellerName,
                    title: snapshot.title,
                    detailText: snapshot.detailText,
                    price: snapshot.price,
                    isSyncedFromServer: true,
                    serverSellerID: snapshot.sellerID
                )
                listing.applyServerSnapshot(snapshot)
                modelContext.insert(listing)
            }
        }

        for cachedListing in cachedRemoteListings where !receivedIDs.contains(cachedListing.id) {
            modelContext.delete(cachedListing)
        }

        try modelContext.save()
    }
}
