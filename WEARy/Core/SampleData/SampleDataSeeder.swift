import Foundation
import SwiftData
import UIKit

enum SampleDataSeeder {
    static func seedIfNeeded(in context: ModelContext) {
        let garments = loadOrCreateGarments(in: context)
        applyDemoImagesIfNeeded(to: garments)
        let outfits = loadOrCreateOutfits(with: garments, in: context)
        applyDemoOutfitPhotosIfNeeded(to: outfits)
        createCommunityPostsIfNeeded(outfits: outfits, in: context)
        expandCommunityPostsIfNeeded(outfits: outfits, in: context)
        createMarketListingsIfNeeded(garments: garments, in: context)
        applyMarketDemoDetailsIfNeeded(in: context)
        try? context.save()
    }

    private static func applyDemoImagesIfNeeded(to garments: [Garment]) {
        let assetsByName = [
            "빈티지 레더 재킷": "DemoLeatherJacket",
            "화이트 베이비 티": "DemoWhiteTee",
            "커브드 데님": "DemoCurvedDenim",
            "실버 러너 스니커즈": "DemoSilverSneakers",
            "레드 미니 백": "DemoRedBag",
            "블랙 니트 드레스": "DemoBlackDress",
            "옐로 체크 셔츠": "DemoYellowShirt",
        ]

        for garment in garments where garment.cutoutImageData == nil {
            guard let assetName = assetsByName[garment.name],
                  let data = UIImage(named: assetName)?.pngData() else { continue }
            garment.cutoutImageData = data
        }
    }

    private static func applyDemoOutfitPhotosIfNeeded(to outfits: [Outfit]) {
        let assetsByNote = [
            "월요일은 가볍고 선명하게.": "DemoOutfitLeather",
            "레드 백으로 포인트를 준 출근 룩.": "DemoOutfitRedBag",
            "자주 손이 가는 데님 조합.": "DemoOutfitCheck",
            "블랙 드레스에 편한 스니커즈.": "DemoOutfitBlackDress",
        ]

        for outfit in outfits where outfit.photoData == nil {
            guard let assetName = assetsByNote[outfit.note],
                  let data = UIImage(named: assetName)?.jpegData(compressionQuality: 0.84) else { continue }
            outfit.photoData = data
        }
    }

    @MainActor
    static func resetDemoData(in context: ModelContext) throws {
        try context.delete(model: CommunityPost.self)
        try context.delete(model: MarketListing.self)
        try context.delete(model: OutfitItem.self)
        try context.delete(model: Outfit.self)
        try context.delete(model: Garment.self)
        try context.save()
        seedIfNeeded(in: context)
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
        let offsets = [0, -1, -2, -4, -6, -9, -13, -17, -22, -28]
        let outfits = offsets.enumerated().compactMap { index, offset -> Outfit? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { return nil }
            let outfit = Outfit(
                wornAt: date,
                note: outfitNote(at: index),
                isPublished: index < 2
            )
            context.insert(outfit)
            let selected = selectedGarments(at: index, from: garments)
            selected.enumerated().forEach { itemIndex, garment in
                context.insert(OutfitItem(
                    garment: garment,
                    outfit: outfit,
                    source: index == 0 ? .ai : .manual,
                    confidence: index == 0 ? .high : .none,
                    displayOrder: itemIndex
                ))
            }
            return outfit
        }
        return outfits
    }

    private static func selectedGarments(at index: Int, from garments: [Garment]) -> [Garment] {
        let byName = Dictionary(uniqueKeysWithValues: garments.map { ($0.name, $0) })
        let names: [String]
        switch index % 4 {
        case 0:
            names = ["빈티지 레더 재킷", "화이트 베이비 티", "커브드 데님", "실버 러너 스니커즈"]
        case 1:
            names = ["화이트 베이비 티", "커브드 데님", "레드 미니 백"]
        case 2:
            names = ["빈티지 레더 재킷", "화이트 베이비 티", "커브드 데님"]
        default:
            names = ["블랙 니트 드레스", "실버 러너 스니커즈", "레드 미니 백"]
        }
        return names.compactMap { byName[$0] }
    }

    private static func outfitNote(at index: Int) -> String {
        [
            "월요일은 가볍고 선명하게.",
            "레드 백으로 포인트를 준 출근 룩.",
            "자주 손이 가는 데님 조합.",
            "블랙 드레스에 편한 스니커즈.",
        ][index % 4]
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

    private static func expandCommunityPostsIfNeeded(outfits: [Outfit], in context: ModelContext) {
        let existingPosts = (try? context.fetch(FetchDescriptor<CommunityPost>())) ?? []
        let existingHandles = Set(existingPosts.map(\.authorHandle))

        existingPosts.first(where: { $0.authorHandle == "seoyeon.daily" })?.tags = ["오늘의룩", "빈티지", "시티보이", "데님"]
        existingPosts.first(where: { $0.authorHandle == "min.archive" })?.tags = ["오늘의룩", "미니멀", "출근룩", "컬러포인트"]

        let samples: [(String, String, String, String, [String], String, Int, Int)] = [
            ("유나", "retro.yuna", "YN", "체크 셔츠와 워시드 데님으로 만든 편안한 빈티지 룩.", ["오늘의룩", "빈티지", "체크셔츠"], "D7B45A", -6, 61),
            ("하윤", "office.hayoon", "HY", "회의가 있는 날의 단정한 출근 룩. 스니커즈로 힘을 뺐어요.", ["오늘의룩", "출근룩", "미니멀"], "A7B9CE", -11, 96),
            ("민서", "color.minseo", "MS", "무채색 사이에 레드 백 하나. 오늘의 컬러 포인트!", ["오늘의룩", "컬러포인트", "가방"], "FF765F", -18, 143),
        ]

        for (index, sample) in samples.enumerated() where !existingHandles.contains(sample.1) {
            let post = CommunityPost(
                authorName: sample.0,
                authorHandle: sample.1,
                authorInitials: sample.2,
                caption: sample.3,
                tags: sample.4,
                createdAt: Calendar.current.date(byAdding: .hour, value: sample.6, to: .now) ?? .now,
                likeCount: sample.7,
                comments: [],
                accentHex: sample.5,
                outfit: outfits.indices.contains(index + 2) ? outfits[index + 2] : outfits.first
            )
            context.insert(post)
        }
    }

    private static func createMarketListingsIfNeeded(garments: [Garment], in context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<MarketListing>())) == 0 else { return }

        let blackDress = garments.first { $0.name == "블랙 니트 드레스" }
        let listings = [
            MarketListing(
                sellerName: "나의 WEARy", title: "블랙 니트 드레스", detailText: "구매 후 몇 번 입지 않아 판매해요. 착용 기록과 사이즈를 확인해 주세요.",
                price: 72_000, originalPrice: blackDress?.purchasePrice, size: blackDress?.size ?? "S",
                condition: .excellent, accentHex: "464646", garment: blackDress
            ),
            MarketListing(
                sellerName: "한남동 옷장", title: "빈티지 레더 재킷", detailText: "부드러운 브라운 컬러의 빈티지 레더 재킷이에요.",
                price: 89_000, originalPrice: 210_000, size: "M", condition: .likeNew, accentHex: "B7A08B"
            ),
            MarketListing(
                sellerName: "연남 빈티지", title: "레드 미니 백", detailText: "코디에 포인트 주기 좋은 체리 레드 컬러입니다.",
                price: 48_000, originalPrice: 120_000, size: "FREE", condition: .excellent, accentHex: "D94B43"
            ),
            MarketListing(
                sellerName: "성수 러너", title: "실버 러너 스니커즈", detailText: "가볍고 편해서 데일리로 신기 좋아요.",
                price: 95_000, originalPrice: 159_000, size: "240", condition: .good, accentHex: "B9BEC2"
            ),
        ]
        listings.forEach(context.insert)
    }

    private static func applyMarketDemoDetailsIfNeeded(in context: ModelContext) {
        let listings = (try? context.fetch(FetchDescriptor<MarketListing>())) ?? []
        let defaults: [String: (place: String, address: String, latitude: Double, longitude: Double, chats: Int)] = [
            "블랙 니트 드레스": ("성수역 3번 출구", "서울 성동구 아차산로 18", 37.54458, 127.05596, 3),
            "빈티지 레더 재킷": ("한남동 주민센터 앞", "서울 용산구 대사관로5길 1", 37.53454, 127.00004, 5),
            "레드 미니 백": ("연남동 경의선숲길 입구", "서울 마포구 동교로 190", 37.56155, 126.92463, 2),
            "실버 러너 스니커즈": ("성수역 개찰구", "서울 성동구 아차산로 100", 37.54458, 127.05596, 4),
        ]
        for listing in listings {
            guard let values = defaults[listing.title] else { continue }
            if listing.meetingPlace == nil { listing.meetingPlace = values.place }
            if listing.meetingAddress == nil { listing.meetingAddress = values.address }
            if listing.meetingLatitude == nil { listing.meetingLatitude = values.latitude }
            if listing.meetingLongitude == nil { listing.meetingLongitude = values.longitude }
            if listing.chatCount == nil { listing.chatCount = values.chats }
        }
    }
}
