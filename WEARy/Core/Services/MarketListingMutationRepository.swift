import Foundation
import Supabase

struct MarketListingMutationDraft: Sendable {
    let sourceGarmentID: UUID?
    let title: String
    let detailText: String
    let price: Int
    let brand: String
    let categoryRaw: String
    let size: String
    let colorHex: String
    let condition: ListingCondition
    let status: ListingStatus
    let meetingPlace: String
    let meetingAddress: String
    let meetingLatitude: Double?
    let meetingLongitude: Double?
    let galleryImages: [Data]
    let showsWardrobeVerification: Bool
    let garmentName: String?
    let cutoutImageData: Data?
    let purchasePrice: Int?
    let lastWornAt: Date?
    let wearCount: Int?
}

actor SupabaseMarketListingMutationRepository {
    static let shared = SupabaseMarketListingMutationRepository()

    private let bucket = "market-media"
    private let maximumFileSize = 10 * 1_024 * 1_024

    func create(_ draft: MarketListingMutationDraft) async throws -> UUID {
        let (client, userID) = try await clientAndUserID()
        try validate(draft)
        let listingID = UUID()
        var uploadedPaths: [String] = []
        var didCreateDraft = false

        do {
            try await client.from("market_listings").insert(MarketListingInsert(
                id: listingID,
                sellerID: userID,
                sourcePrivateID: draft.sourceGarmentID,
                title: draft.title,
                description: draft.detailText,
                price: draft.price,
                brandSnapshot: draft.brand,
                categorySnapshot: draft.categoryRaw,
                sizeSnapshot: draft.size,
                colorHexSnapshot: draft.colorHex,
                condition: draft.condition.backendValue,
                status: "hidden",
                meetingName: draft.meetingPlace.nilIfEmpty,
                meetingAddress: draft.meetingAddress.nilIfEmpty,
                meetingLatitude: draft.meetingLatitude,
                meetingLongitude: draft.meetingLongitude
            )).execute()
            didCreateDraft = true

            let content = try await uploadContent(
                draft,
                listingID: listingID,
                userID: userID,
                client: client
            )
            uploadedPaths = content.uploadedPaths
            try await replace(
                listingID: listingID,
                draft: draft,
                status: .active,
                content: content,
                client: client
            )
            return listingID
        } catch {
            if !uploadedPaths.isEmpty {
                _ = try? await client.storage.from(bucket).remove(paths: uploadedPaths)
            }
            if didCreateDraft {
                _ = try? await client.from("market_listings").delete()
                    .eq("id", value: listingID.uuidString).execute()
            }
            throw error
        }
    }

    func update(listingID: UUID, draft: MarketListingMutationDraft) async throws {
        let (client, userID) = try await clientAndUserID()
        try validate(draft)
        let oldPaths = try await storedPaths(listingID: listingID, client: client)
        let content = try await uploadContent(
            draft,
            listingID: listingID,
            userID: userID,
            client: client
        )

        do {
            try await replace(
                listingID: listingID,
                draft: draft,
                status: draft.status,
                content: content,
                client: client
            )
            if !oldPaths.isEmpty {
                _ = try? await client.storage.from(bucket).remove(paths: oldPaths)
            }
        } catch {
            if !content.uploadedPaths.isEmpty {
                _ = try? await client.storage.from(bucket).remove(paths: content.uploadedPaths)
            }
            throw error
        }
    }

    func updateStatus(listingID: UUID, status: ListingStatus) async throws {
        let (client, _) = try await clientAndUserID()
        try await client.from("market_listings")
            .update(MarketListingStatusUpdate(status: status.backendValue))
            .eq("id", value: listingID.uuidString)
            .execute()
    }

    func delete(listingID: UUID) async throws {
        let (client, _) = try await clientAndUserID()
        let paths = try await storedPaths(listingID: listingID, client: client)
        try await client.from("market_listings").delete()
            .eq("id", value: listingID.uuidString).execute()
        if !paths.isEmpty {
            _ = try? await client.storage.from(bucket).remove(paths: paths)
        }
    }

    private func clientAndUserID() async throws -> (SupabaseClient, UUID) {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        return (client, try await SupabaseSessionManager.shared.authenticatedUserID())
    }

    private func validate(_ draft: MarketListingMutationDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarketListingMutationError.missingTitle
        }
        guard draft.price > 0 else { throw MarketListingMutationError.invalidPrice }
        guard draft.galleryImages.count <= 8 else { throw MarketListingMutationError.tooManyImages }
        guard (draft.meetingLatitude == nil) == (draft.meetingLongitude == nil) else {
            throw MarketListingMutationError.incompleteMeetingPlace
        }
    }

    private func uploadContent(
        _ draft: MarketListingMutationDraft,
        listingID: UUID,
        userID: UUID,
        client: SupabaseClient
    ) async throws -> UploadedMarketContent {
        let revision = UUID().uuidString
        var paths: [String] = []
        var media: [MarketMediaParameter] = []

        do {
            for (index, data) in draft.galleryImages.enumerated() {
                let file = try mediaFile(from: data)
                let path = "\(userID.uuidString)/\(listingID.uuidString)/gallery/\(revision)-\(index).\(file.fileExtension)"
                try await upload(file, path: path, client: client)
                paths.append(path)
                media.append(MarketMediaParameter(storagePath: path, sortOrder: index))
            }

            var verification: MarketVerificationParameter?
            if draft.showsWardrobeVerification,
               let sourceID = draft.sourceGarmentID,
               let garmentName = draft.garmentName {
                var cutoutPath: String?
                if let data = draft.cutoutImageData {
                    let file = try mediaFile(from: data)
                    let path = "\(userID.uuidString)/\(listingID.uuidString)/verification/\(revision).\(file.fileExtension)"
                    try await upload(file, path: path, client: client)
                    paths.append(path)
                    cutoutPath = path
                }
                verification = MarketVerificationParameter(
                    sourcePrivateID: sourceID,
                    garmentNameSnapshot: garmentName,
                    purchasePrice: draft.purchasePrice,
                    lastWornAt: draft.lastWornAt,
                    wearCount: draft.wearCount,
                    cutoutStoragePath: cutoutPath,
                    isVisible: true
                )
            }
            return UploadedMarketContent(media: media, verification: verification, uploadedPaths: paths)
        } catch {
            if !paths.isEmpty { _ = try? await client.storage.from(bucket).remove(paths: paths) }
            throw error
        }
    }

    private func replace(
        listingID: UUID,
        draft: MarketListingMutationDraft,
        status: ListingStatus,
        content: UploadedMarketContent,
        client: SupabaseClient
    ) async throws {
        try await client.rpc("replace_market_listing", params: MarketReplaceParameters(
            listingID: listingID,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.detailText.trimmingCharacters(in: .whitespacesAndNewlines),
            price: draft.price,
            condition: draft.condition.backendValue,
            status: status.backendValue,
            meetingName: draft.meetingPlace,
            meetingAddress: draft.meetingAddress,
            meetingLatitude: draft.meetingLatitude,
            meetingLongitude: draft.meetingLongitude,
            media: content.media,
            verification: content.verification
        )).execute()
    }

    private func storedPaths(listingID: UUID, client: SupabaseClient) async throws -> [String] {
        let media: [MarketStoredMedia] = try await client.from("market_listing_media")
            .select("storage_path").eq("listing_id", value: listingID.uuidString).execute().value
        let verifications: [MarketStoredVerification] = try await client
            .from("market_listing_verifications").select("cutout_storage_path")
            .eq("listing_id", value: listingID.uuidString).execute().value
        return media.map(\.storagePath) + verifications.compactMap(\.cutoutStoragePath)
    }

    private func upload(_ file: MarketMediaFile, path: String, client: SupabaseClient) async throws {
        guard file.data.count <= maximumFileSize else { throw MarketListingMutationError.imageTooLarge }
        try await client.storage.from(bucket).upload(
            path, data: file.data,
            options: FileOptions(contentType: file.contentType, upsert: false)
        )
    }

    private func mediaFile(from data: Data) throws -> MarketMediaFile {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .init(data: data, fileExtension: "jpg", contentType: "image/jpeg")
        }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .init(data: data, fileExtension: "png", contentType: "image/png")
        }
        if bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" {
            return .init(data: data, fileExtension: "webp", contentType: "image/webp")
        }
        if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            return .init(data: data, fileExtension: ["mif1", "msf1"].contains(brand) ? "heif" : "heic", contentType: ["mif1", "msf1"].contains(brand) ? "image/heif" : "image/heic")
        }
        throw MarketListingMutationError.unsupportedImageFormat
    }
}

private extension ListingCondition {
    var backendValue: String {
        switch self { case .likeNew: "like_new"; case .excellent: "excellent"; case .good: "good" }
    }
}

private extension ListingStatus {
    var backendValue: String {
        switch self { case .active: "active"; case .reserved: "reserved"; case .sold: "sold" }
    }
}

private extension String { var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self } }
private struct MarketMediaFile: Sendable { let data: Data; let fileExtension: String; let contentType: String }
private struct UploadedMarketContent: Sendable { let media: [MarketMediaParameter]; let verification: MarketVerificationParameter?; let uploadedPaths: [String] }
private struct MarketListingStatusUpdate: Encodable, Sendable { let status: String }
private struct MarketStoredMedia: Decodable, Sendable { let storagePath: String; enum CodingKeys: String, CodingKey { case storagePath = "storage_path" } }
private struct MarketStoredVerification: Decodable, Sendable { let cutoutStoragePath: String?; enum CodingKeys: String, CodingKey { case cutoutStoragePath = "cutout_storage_path" } }

private struct MarketListingInsert: Encodable, Sendable {
    let id: UUID; let sellerID: UUID; let sourcePrivateID: UUID?; let title: String; let description: String; let price: Int
    let brandSnapshot: String; let categorySnapshot: String; let sizeSnapshot: String; let colorHexSnapshot: String
    let condition: String; let status: String; let meetingName: String?; let meetingAddress: String?
    let meetingLatitude: Double?; let meetingLongitude: Double?
    enum CodingKeys: String, CodingKey {
        case id, title, description, price, condition, status
        case sellerID = "seller_id"; case sourcePrivateID = "source_private_id"; case brandSnapshot = "brand_snapshot"
        case categorySnapshot = "category_snapshot"; case sizeSnapshot = "size_snapshot"; case colorHexSnapshot = "color_hex_snapshot"
        case meetingName = "meeting_name"; case meetingAddress = "meeting_address"; case meetingLatitude = "meeting_latitude"; case meetingLongitude = "meeting_longitude"
    }
}

private struct MarketMediaParameter: Encodable, Sendable {
    let storagePath: String; let sortOrder: Int
    enum CodingKeys: String, CodingKey { case storagePath = "storage_path"; case sortOrder = "sort_order" }
}
private struct MarketVerificationParameter: Encodable, Sendable {
    let sourcePrivateID: UUID; let garmentNameSnapshot: String; let purchasePrice: Int?; let lastWornAt: Date?; let wearCount: Int?; let cutoutStoragePath: String?; let isVisible: Bool
    enum CodingKeys: String, CodingKey {
        case sourcePrivateID = "source_private_id"; case garmentNameSnapshot = "garment_name_snapshot"; case purchasePrice = "purchase_price"
        case lastWornAt = "last_worn_at"; case wearCount = "wear_count"; case cutoutStoragePath = "cutout_storage_path"; case isVisible = "is_visible"
    }
}
private struct MarketReplaceParameters: Encodable, Sendable {
    let listingID: UUID; let title: String; let description: String; let price: Int; let condition: String; let status: String
    let meetingName: String; let meetingAddress: String; let meetingLatitude: Double?; let meetingLongitude: Double?
    let media: [MarketMediaParameter]; let verification: MarketVerificationParameter?
    enum CodingKeys: String, CodingKey {
        case listingID = "p_listing_id"; case title = "p_title"; case description = "p_description"; case price = "p_price"
        case condition = "p_condition"; case status = "p_status"; case meetingName = "p_meeting_name"; case meetingAddress = "p_meeting_address"
        case meetingLatitude = "p_meeting_latitude"; case meetingLongitude = "p_meeting_longitude"; case media = "p_media"; case verification = "p_verification"
    }
}

enum MarketListingMutationError: LocalizedError {
    case missingTitle, invalidPrice, tooManyImages, incompleteMeetingPlace, imageTooLarge, unsupportedImageFormat
    var errorDescription: String? {
        switch self {
        case .missingTitle: "상품명을 입력해 주세요."
        case .invalidPrice: "판매 가격을 확인해 주세요."
        case .tooManyImages: "판매 사진은 최대 8장까지 등록할 수 있습니다."
        case .incompleteMeetingPlace: "만날 장소 좌표를 다시 선택해 주세요."
        case .imageTooLarge: "사진 한 장은 10MB 이하여야 합니다."
        case .unsupportedImageFormat: "지원하지 않는 사진 형식입니다."
        }
    }
}
