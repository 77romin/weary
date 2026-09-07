import Foundation
import SwiftData

enum GarmentCategory: String, CaseIterable, Codable, Identifiable {
    case top = "상의"
    case bottom = "하의"
    case outer = "아우터"
    case dress = "원피스"
    case shoes = "신발"
    case bag = "가방"
    case accessory = "액세서리"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .top: "tshirt"
        case .bottom: "figure.stand.dress"
        case .outer: "jacket"
        case .dress: "figure.dress.line.vertical.figure"
        case .shoes: "shoe"
        case .bag: "handbag"
        case .accessory: "sunglasses"
        }
    }
}

enum GarmentStatus: String, CaseIterable, Codable, Identifiable {
    case active = "입는 중"
    case keep = "유지"
    case stored = "보관"
    case selling = "판매 예정"
    case sold = "판매 완료"

    var id: String { rawValue }
}

@Model
final class Garment {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String
    var categoryRaw: String
    var colorName: String
    var colorHex: String
    var purchaseDate: Date?
    var purchasePrice: Int?
    var size: String
    var season: String
    var statusRaw: String
    var createdAt: Date
    var imageData: Data?

    @Relationship(deleteRule: .cascade, inverse: \OutfitItem.garment)
    var outfitItems: [OutfitItem] = []

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        category: GarmentCategory,
        colorName: String,
        colorHex: String,
        purchaseDate: Date? = nil,
        purchasePrice: Int? = nil,
        size: String = "",
        season: String = "사계절",
        status: GarmentStatus = .active,
        createdAt: Date = .now,
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        categoryRaw = category.rawValue
        self.colorName = colorName
        self.colorHex = colorHex
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.size = size
        self.season = season
        statusRaw = status.rawValue
        self.createdAt = createdAt
        self.imageData = imageData
    }

    var category: GarmentCategory {
        get { GarmentCategory(rawValue: categoryRaw) ?? .top }
        set { categoryRaw = newValue.rawValue }
    }

    var status: GarmentStatus {
        get { GarmentStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var confirmedOutfitItems: [OutfitItem] {
        outfitItems.filter { $0.outfit?.isConfirmed == true }
    }

    var wearCount: Int { confirmedOutfitItems.count }

    var wearDayCount: Int {
        Set(confirmedOutfitItems.compactMap { item in
            item.outfit.map { Calendar.current.startOfDay(for: $0.wornAt) }
        }).count
    }

    var lastWornAt: Date? {
        confirmedOutfitItems.compactMap(\.outfit?.wornAt).max()
    }

    var costPerWear: Int? {
        guard let purchasePrice, wearCount > 0 else { return nil }
        return purchasePrice / wearCount
    }
}
