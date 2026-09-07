import Foundation
import SwiftData

enum ListingCondition: String, CaseIterable, Identifiable {
    case likeNew = "새 상품에 가까워요"
    case excellent = "사용감이 거의 없어요"
    case good = "사용감이 조금 있어요"

    var id: String { rawValue }
}

enum ListingStatus: String, CaseIterable, Identifiable {
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
    var originalPrice: Int?
    var size: String
    var conditionRaw: String
    var statusRaw: String
    var createdAt: Date
    var isLiked: Bool
    var accentHex: String
    var garment: Garment?

    init(
        id: UUID = UUID(),
        sellerName: String,
        title: String,
        detailText: String,
        price: Int,
        originalPrice: Int? = nil,
        size: String = "",
        condition: ListingCondition = .excellent,
        status: ListingStatus = .active,
        createdAt: Date = .now,
        isLiked: Bool = false,
        accentHex: String = "B7A08B",
        garment: Garment? = nil
    ) {
        self.id = id
        self.sellerName = sellerName
        self.title = title
        self.detailText = detailText
        self.price = price
        self.originalPrice = originalPrice
        self.size = size
        conditionRaw = condition.rawValue
        statusRaw = status.rawValue
        self.createdAt = createdAt
        self.isLiked = isLiked
        self.accentHex = accentHex
        self.garment = garment
    }

    var condition: ListingCondition {
        get { ListingCondition(rawValue: conditionRaw) ?? .excellent }
        set { conditionRaw = newValue.rawValue }
    }

    var status: ListingStatus {
        get { ListingStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}
