import Foundation
import SwiftData

enum SampleDataSeeder {
    static func seedIfNeeded(in context: ModelContext) {
        let garments = loadOrCreateGarments(in: context)
        let outfits = loadOrCreateOutfits(with: garments, in: context)
        createCommunityPostsIfNeeded(outfits: outfits, in: context)
        createMarketListingsIfNeeded(garments: garments, in: context)
        try? context.save()
    }

    private static func loadOrCreateGarments(in context: ModelContext) -> [Garment] {
        if let existing = try? context.fetch(FetchDescriptor<Garment>()), !existing.isEmpty {
            guard !existing.contains(where: { $0.name == "옐로 체크 셔츠" }) else { return existing }
            let reviewSample = Garment(
                name: "옐로 체크 셔츠", brand: "VINTAGE", category: .top,
                colorName: "머스터드", colorHex: "D7B45A",
                purchaseDate: Calendar.current.date(byAdding: .month, value: -10, to: .now),
                purchasePrice: 68_000, size: "M", season: "봄 · 가을"
            )
            context.insert(reviewSample)
            return existing + [reviewSample]
        }

        let calendar = Calendar.current
        let now = Date.now
        let garments = [
            Garment(name: "빈티지 레더 재킷", brand: "MUSED", category: .outer,
                    colorName: "에스프레소", colorHex: "8D6748",
                    purchaseDate: calendar.date(byAdding: .month, value: -8, to: now),
                    purchasePrice: 248_000, size: "M", season: "봄 · 가을"),
            Garment(name: "화이트 베이비 티", brand: "NONLOCAL", category: .top,
                    colorName: "아이보리", colorHex: "E9E3D6",
                    purchaseDate: calendar.date(byAdding: .month, value: -5, to: now),
                    purchasePrice: 42_000, size: "S", season: "봄 · 여름"),
            Garment(name: "커브드 데님", brand: "ORDINARY", category: .bottom,
                    colorName: "워시드 블루", colorHex: "7392B7",
                    purchaseDate: calendar.date(byAdding: .month, value: -11, to: now),
                    purchasePrice: 109_000, size: "27"),
            Garment(name: "실버 러너 스니커즈", brand: "MOONSTAR", category: .shoes,
                    colorName: "실버", colorHex: "B9BEC2",
                    purchaseDate: calendar.date(byAdding: .month, value: -3, to: now),
                    purchasePrice: 159_000, size: "240"),
            Garment(name: "레드 미니 백", brand: "FENNEC", category: .bag,
                    colorName: "체리 레드", colorHex: "D94B43",
                    purchaseDate: calendar.date(byAdding: .month, value: -14, to: now),
                    purchasePrice: 138_000, size: "FREE", status: .stored),
            Garment(name: "블랙 니트 드레스", brand: "AMOMENTO", category: .dress,
                    colorName: "블랙", colorHex: "343434",
                    purchaseDate: calendar.date(byAdding: .year, value: -2, to: now),
                    purchasePrice: 189_000, size: "S", season: "가을 · 겨울", status: .selling),
            Garment(name: "옐로 체크 셔츠", brand: "VINTAGE", category: .top,
                    colorName: "머스터드", colorHex: "D7B45A",
                    purchaseDate: calendar.date(byAdding: .month, value: -10, to: now),
                    purchasePrice: 68_000, size: "M", season: "봄 · 가을"),
        ]
        garments.forEach(context.insert)
        return garments
    }

    private static func loadOrCreateOutfits(with garments: [Garment], in context: ModelContext) -> [Outfit] {
        if let existing = try? context.fetch(FetchDescriptor<Outfit>()), !existing.isEmpty {
            return existing.sorted { $0.wornAt > $1.wornAt }
        }
        guard garments.count >= 5 else { return [] }

        let calendar = Calendar.current
        let offsets = [0, -2, -5, -9, -16, -24]
        let outfits = offsets.enumerated().compactMap { index, offset -> Outfit? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { return nil }
            let outfit = Outfit(
                wornAt: date,
                note: index == 0 ? "월요일은 가볍고 선명하게." : "데일리 룩 기록",
                isPublished: index < 2
            )
            context.insert(outfit)
            let selected = index.isMultiple(of: 2)
                ? [garments[0], garments[1], garments[2], garments[3]]
                : [garments[1], garments[2], garments[4]]
            selected.forEach {
                context.insert(OutfitItem(
                    garment: $0,
                    outfit: outfit,
                    source: index == 0 ? .ai : .manual,
                    confidence: index == 0 ? .high : .none
                ))
            }
            return outfit
        }
        return outfits
    }

    private static func createCommunityPostsIfNeeded(outfits: [Outfit], in context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<CommunityPost>())) == 0 else { return }

        let first = CommunityPost(
            authorName: "서연", authorHandle: "seoyeon.daily", authorInitials: "SY",
            caption: "빈티지 레더와 데님의 월요일 조합. 날씨가 애매할 땐 레이어드가 답!",
            tags: ["시티보이", "가을코디", "데님"],
            createdAt: Calendar.current.date(byAdding: .minute, value: -32, to: .now) ?? .now,
            likeCount: 128, comments: ["지민: 재킷 핏 너무 예뻐요", "민서: 데님 정보 궁금해요!"],
            accentHex: "A7B9CE", outfit: outfits.first
        )
        let second = CommunityPost(
            authorName: "지민", authorHandle: "min.archive", authorInitials: "JM",
            caption: "색 하나만 강하게 넣어본 오늘의 출근 룩.",
            tags: ["미니멀", "레드포인트"],
            createdAt: Calendar.current.date(byAdding: .hour, value: -3, to: .now) ?? .now,
            likeCount: 84, comments: ["서연: 가방이 포인트네요 🍒"],
            accentHex: "E99C8D", outfit: outfits.dropFirst().first
        )
        context.insert(first)
        context.insert(second)
    }

    private static func createMarketListingsIfNeeded(garments: [Garment], in context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<MarketListing>())) == 0 else { return }

        let sampleGarments = Array(garments.prefix(4))
        let titles = ["빈티지 레더 재킷", "블랙 니트 드레스", "레드 미니 백", "실버 러너"]
        let prices = [89_000, 72_000, 48_000, 95_000]
        let colors = ["B7A08B", "464646", "D94B43", "B9BEC2"]

        for index in titles.indices {
            let garment = sampleGarments.indices.contains(index) ? sampleGarments[index] : nil
            context.insert(MarketListing(
                sellerName: index.isMultiple(of: 2) ? "한남동 옷장" : "연남 빈티지",
                title: titles[index],
                detailText: "깨끗하게 보관했고 실제 착용 횟수가 적어요. 편하게 문의해 주세요.",
                price: prices[index],
                originalPrice: garment?.purchasePrice,
                size: garment?.size ?? "FREE",
                condition: index == 0 ? .likeNew : .excellent,
                accentHex: colors[index],
                garment: garment
            ))
        }
    }
}
