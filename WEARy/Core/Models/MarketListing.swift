import Foundation
import SwiftData

enum ListingCondition: String, CaseIterable, Codable, Identifiable, Sendable {
    case likeNew = "새 상품에 가까워요"
    case excellent = "사용감이 거의 없어요"
    case good = "사용감이 조금 있어요"

    var id: String { rawValue }
}

enum ListingStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case active = "판매 중"
    case reserved = "예약 중"
    case sold = "판매 완료"

    var id: String { rawValue }
}

@Model
final class MarketListing {
    @Attribute(.unique) var id: UUID
    var sellerName: String
    var title: String
    var detailText: String
    var price: Int
    var previousPrice: Int?
    var originalPrice: Int?
    var size: String
    var conditionRaw: String
    var statusRaw: String
    var createdAt: Date
    var isLiked: Bool
    var accentHex: String
    var meetingPlace: String?
    var meetingAddress: String?
    var meetingLatitude: Double?
    var meetingLongitude: Double?
    var chatCount: Int?
    @Attribute(.externalStorage) var galleryData: Data?
    var wardrobeVerificationVisible: Bool?
    var sourceGarmentID: UUID?
    var garmentNameSnapshot: String?
    var garmentCategoryRawSnapshot: String?
    var garmentColorHexSnapshot: String?
    @Attribute(.externalStorage) var garmentCutoutImageDataSnapshot: Data?
    var verificationPurchasePrice: Int?
    var verificationLastWornAt: Date?
    var verificationWearCount: Int?
    var ownedByCurrentUser: Bool?
    var isSyncedFromServer: Bool?
    var serverSellerID: UUID?

    init(
        id: UUID = UUID(),
        sellerName: String,
        title: String,
        detailText: String,
        price: Int,
        previousPrice: Int? = nil,
        originalPrice: Int? = nil,
        size: String = "",
        condition: ListingCondition = .excellent,
        status: ListingStatus = .active,
        createdAt: Date = .now,
        isLiked: Bool = false,
        accentHex: String = "B7A08B",
        meetingPlace: String? = nil,
        meetingAddress: String? = nil,
        meetingLatitude: Double? = nil,
        meetingLongitude: Double? = nil,
        chatCount: Int? = nil,
        galleryImages: [Data] = [],
        showsWardrobeVerification: Bool = false,
        garment: Garment? = nil,
        isOwnedByCurrentUser: Bool? = nil,
        isSyncedFromServer: Bool = false,
        serverSellerID: UUID? = nil
    ) {
        self.id = id
        self.sellerName = sellerName
        self.title = title
        self.detailText = detailText
        self.price = price
        self.previousPrice = previousPrice
        self.originalPrice = originalPrice
        self.size = size
        conditionRaw = condition.rawValue
        statusRaw = status.rawValue
        self.createdAt = createdAt
        self.isLiked = isLiked
        self.accentHex = accentHex
        self.meetingPlace = meetingPlace
        self.meetingAddress = meetingAddress
        self.meetingLatitude = meetingLatitude
        self.meetingLongitude = meetingLongitude
        self.chatCount = chatCount
        galleryData = try? PropertyListEncoder().encode(galleryImages)
        wardrobeVerificationVisible = showsWardrobeVerification
        ownedByCurrentUser = isOwnedByCurrentUser
        self.isSyncedFromServer = isSyncedFromServer
        self.serverSellerID = serverSellerID
        captureSnapshot(from: garment)
    }

    var condition: ListingCondition {
        get { ListingCondition(rawValue: conditionRaw) ?? .excellent }
        set { conditionRaw = newValue.rawValue }
    }

    var status: ListingStatus {
        get { ListingStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isOwnedByCurrentUser: Bool {
        ownedByCurrentUser ?? (sellerName == "나의 WEARy" || sellerName == "나의 옷장")
    }

    var displayedMeetingPlace: String {
        let trimmed = meetingPlace?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "장소 협의" : trimmed
    }

    var displayedChatCount: Int {
        max(0, chatCount ?? 0)
    }

    var hasPinnedMeetingPlace: Bool {
        meetingLatitude != nil && meetingLongitude != nil
    }

    var galleryImages: [Data] {
        guard let galleryData else { return [] }
        return (try? PropertyListDecoder().decode([Data].self, from: galleryData)) ?? []
    }

    var showsWardrobeVerification: Bool {
        get { wardrobeVerificationVisible ?? false }
        set { wardrobeVerificationVisible = newValue }
    }

    func updateGalleryImages(_ images: [Data]) {
        galleryData = try? PropertyListEncoder().encode(images)
    }

    var priceChange: Int? {
        guard let previousPrice, previousPrice != price else { return nil }
        return price - previousPrice
    }

    func updatePrice(to newPrice: Int) {
        guard newPrice > 0, newPrice != price else { return }
        previousPrice = price
        price = newPrice
    }

    var hasWardrobeSnapshot: Bool {
        sourceGarmentID != nil
    }

    var garmentCategorySnapshot: GarmentCategory {
        GarmentCategory(rawValue: garmentCategoryRawSnapshot ?? "") ?? .top
    }

    func captureSnapshot(from garment: Garment?) {
        guard let garment else { return }
        sourceGarmentID = garment.id
        garmentNameSnapshot = garment.name
        garmentCategoryRawSnapshot = garment.categoryRaw
        garmentColorHexSnapshot = garment.colorHex
        garmentCutoutImageDataSnapshot = garment.cutoutImageData
        verificationPurchasePrice = garment.purchasePrice
        verificationLastWornAt = garment.lastWornAt
        verificationWearCount = garment.wearCount
    }

    func applyServerSnapshot(_ snapshot: MarketListingSnapshot) {
        sellerName = snapshot.sellerName
        title = snapshot.title
        detailText = snapshot.detailText
        price = snapshot.price
        previousPrice = snapshot.previousPrice
        originalPrice = snapshot.verificationPurchasePrice
        size = snapshot.size
        condition = snapshot.condition
        status = snapshot.status
        createdAt = snapshot.createdAt
        isLiked = snapshot.isLiked
        accentHex = snapshot.accentHex
        meetingPlace = snapshot.meetingPlace
        meetingAddress = snapshot.meetingAddress
        meetingLatitude = snapshot.meetingLatitude
        meetingLongitude = snapshot.meetingLongitude
        chatCount = snapshot.chatCount
        updateGalleryImages(snapshot.galleryImages)
        wardrobeVerificationVisible = snapshot.showsWardrobeVerification
        sourceGarmentID = snapshot.sourceGarmentID
        garmentNameSnapshot = snapshot.garmentNameSnapshot
        garmentCategoryRawSnapshot = snapshot.garmentCategoryRawSnapshot
        garmentColorHexSnapshot = snapshot.garmentColorHexSnapshot
        garmentCutoutImageDataSnapshot = snapshot.garmentCutoutImageDataSnapshot
        verificationPurchasePrice = snapshot.verificationPurchasePrice
        verificationLastWornAt = snapshot.verificationLastWornAt
        verificationWearCount = snapshot.verificationWearCount
        ownedByCurrentUser = snapshot.isOwnedByCurrentUser
        isSyncedFromServer = true
        serverSellerID = snapshot.sellerID
    }

    func sourceGarment(in context: ModelContext) -> Garment? {
        guard let sourceGarmentID else { return nil }
        var descriptor = FetchDescriptor<Garment>(
            predicate: #Predicate { $0.id == sourceGarmentID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
