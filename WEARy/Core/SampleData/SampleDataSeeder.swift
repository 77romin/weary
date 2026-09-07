import Foundation
import SwiftData

enum SampleDataSeeder {
    static func seedIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Garment>()
        guard (try? context.fetchCount(descriptor)) == 0 else { return }

        let calendar = Calendar.current
        let now = Date.now

        let garments = [
            Garment(
                name: "빈티지 레더 재킷",
                brand: "MUSED",
                category: .outer,
                colorName: "에스프레소",
                colorHex: "8D6748",
                purchaseDate: calendar.date(byAdding: .month, value: -8, to: now),
                purchasePrice: 248_000,
                size: "M",
                season: "봄 · 가을"
            ),
            Garment(
                name: "화이트 베이비 티",
                brand: "NONLOCAL",
                category: .top,
                colorName: "아이보리",
                colorHex: "E9E3D6",
                purchaseDate: calendar.date(byAdding: .month, value: -5, to: now),
                purchasePrice: 42_000,
                size: "S",
                season: "봄 · 여름"
            ),
            Garment(
                name: "커브드 데님",
                brand: "ORDINARY",
                category: .bottom,
                colorName: "워시드 블루",
                colorHex: "7392B7",
                purchaseDate: calendar.date(byAdding: .month, value: -11, to: now),
                purchasePrice: 109_000,
                size: "27",
                season: "사계절"
            ),
            Garment(
                name: "실버 러너 스니커즈",
                brand: "MOONSTAR",
                category: .shoes,
                colorName: "실버",
                colorHex: "B9BEC2",
                purchaseDate: calendar.date(byAdding: .month, value: -3, to: now),
                purchasePrice: 159_000,
                size: "240",
                season: "사계절"
            ),
            Garment(
                name: "레드 미니 백",
                brand: "FENNEC",
                category: .bag,
                colorName: "체리 레드",
                colorHex: "D94B43",
                purchaseDate: calendar.date(byAdding: .month, value: -14, to: now),
                purchasePrice: 138_000,
                size: "FREE",
                season: "사계절",
                status: .stored
            ),
            Garment(
                name: "블랙 니트 드레스",
                brand: "AMOMENTO",
                category: .dress,
                colorName: "블랙",
                colorHex: "343434",
                purchaseDate: calendar.date(byAdding: .year, value: -2, to: now),
                purchasePrice: 189_000,
                size: "S",
                season: "가을 · 겨울",
                status: .selling
            ),
        ]

        garments.forEach(context.insert)

        let outfitOffsets = [0, -2, -5, -9, -16, -24]
        for (index, offset) in outfitOffsets.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let outfit = Outfit(
                wornAt: date,
                note: index == 0 ? "월요일은 가볍고 선명하게." : "데일리 룩 기록",
                isPublished: index < 2
            )
            context.insert(outfit)

            let selected = index.isMultiple(of: 2)
                ? [garments[0], garments[1], garments[2], garments[3]]
                : [garments[1], garments[2], garments[4]]

            for garment in selected {
                let item = OutfitItem(
                    garment: garment,
                    outfit: outfit,
                    source: index == 0 ? .ai : .manual,
                    confidence: index == 0 ? .high : .none
                )
                context.insert(item)
            }
        }

        try? context.save()
    }
}
