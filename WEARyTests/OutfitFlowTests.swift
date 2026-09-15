import CoreGraphics
import Foundation
import SwiftData
import Testing
import UIKit
@testable import WEARy

@Suite("착장 기록 핵심 규칙")
struct OutfitFlowTests {
    @Test("소셜 데이터 모드는 실서버와 데모를 명확히 구분한다")
    func socialContentModesAreDistinct() {
        #expect(SocialContentMode.live.title == "실서버")
        #expect(SocialContentMode.demo.title == "데모")
        #expect(SocialContentMode.live.description != SocialContentMode.demo.description)
    }

    @Test("누끼 이미지는 보이는 옷 영역에 맞춰 투명 여백을 자른다")
    func cutoutImageCropsTransparentMargins() throws {
        let width = 100
        let height = 100
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 30, y: 20, width: 20, height: 40))
        let sourceImage = try #require(context.makeImage())

        let croppedImage = try #require(GarmentCutoutService.cropToVisibleContent(sourceImage))

        #expect(croppedImage.width == 24)
        #expect(croppedImage.height == 44)
    }

    @Test("데모 분석기는 카테고리별 후보를 반환한다")
    @MainActor
    func analyzerReturnsCategoryGroups() async throws {
        let topID = UUID()
        let bottomID = UUID()
        let wardrobe = [
            GarmentSnapshot(id: topID, category: .top, name: "티셔츠"),
            GarmentSnapshot(id: bottomID, category: .bottom, name: "데님"),
        ]

        let result = try await DemoOutfitAnalyzer().analyze(photoData: nil, wardrobe: wardrobe)

        #expect(result.map(\.category) == [.top, .bottom])
        #expect(result.map(\.selectedGarmentID) == [topID, bottomID])
    }

    @Test("기기 분석기는 Vision 또는 안전한 fallback으로 후보를 반환한다")
    @MainActor
    func deviceAnalyzerUsesVisionFeaturePrints() async throws {
        let garmentID = UUID()
        let imageData = try #require(solidImageData(red: 0.18, green: 0.42, blue: 0.76))
        let wardrobe = [GarmentSnapshot(
            id: garmentID,
            category: .bag,
            name: "Vision 테스트 가방",
            imageData: imageData,
            cutoutImageData: imageData
        )]

        let result = try await DeviceOutfitAnalyzer().analyze(
            photoData: imageData,
            wardrobe: wardrobe
        )
        let group = try #require(result.first)

#if targetEnvironment(simulator)
        #expect(group.source == .vision || group.source == .ai)
#else
        #expect(group.source == .vision)
#endif
        #expect(group.candidateIDs == [garmentID])
        if group.source == .vision && group.confidence == .none {
            #expect(group.selectedGarmentID == nil)
        } else {
            #expect(group.selectedGarmentID == garmentID)
        }
    }

    @Test("Vision 후보는 특징 거리가 가까운 순서로 최대 세 개를 고른다")
    func deviceAnalyzerRanksNearestCandidates() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let fallback = UUID()

        let result = DeviceOutfitAnalyzer.rankedCandidateIDs(
            distances: [
                (id: second, distance: 4.2),
                (id: third, distance: 8.7),
                (id: first, distance: 1.1),
            ],
            fallbackIDs: [fallback]
        )

        #expect(result == [first, second, third])
    }

    @Test("빈 옷장은 분석 실패 이유를 제공한다")
    @MainActor
    func analyzerReportsEmptyWardrobe() async {
        do {
            _ = try await DemoOutfitAnalyzer().analyze(photoData: nil, wardrobe: [])
            Issue.record("빈 옷장 분석은 실패해야 합니다")
        } catch {
            #expect(error.localizedDescription.contains("옷장"))
        }
    }

    @Test("같은 옷이 여러 그룹에 선택되어도 한 번만 저장한다")
    func duplicateSelectionsAreDeduplicated() {
        let garmentID = UUID()
        let groups = [
            DetectedGarmentGroup(
                category: .top,
                candidateIDs: [garmentID],
                selectedGarmentID: garmentID,
                confidence: .high
            ),
            DetectedGarmentGroup(
                category: .outer,
                candidateIDs: [garmentID],
                selectedGarmentID: garmentID,
                confidence: .medium
            ),
        ]

        #expect(OutfitSelection.uniqueGarmentIDs(in: groups) == [garmentID])
    }

    @Test("제외한 후보는 저장 대상에 포함하지 않는다")
    func excludedSelectionIsIgnored() {
        let groups = [
            DetectedGarmentGroup(
                category: .shoes,
                candidateIDs: [],
                selectedGarmentID: nil,
                confidence: .none
            ),
        ]

        #expect(OutfitSelection.uniqueGarmentIDs(in: groups).isEmpty)
    }

    @Test("게시물 좋아요와 댓글 상태를 변경할 수 있다")
    func communityPostInteractionsUpdate() {
        let post = CommunityPost(
            authorName: "테스터",
            authorHandle: "test", authorInitials: "T",
            caption: "테스트 룩", likeCount: 3
        )

        post.isLiked = true
        post.likeCount += 1
        post.appendComment("나: 멋진 룩이에요")

        #expect(post.likeCount == 4)
        #expect(post.comments == ["나: 멋진 룩이에요"])
    }

    @Test("커뮤니티 게시물은 개인 착장 대신 게시 시점 스냅샷을 보존한다")
    func communityPostCapturesOutfitSnapshot() {
        let photo = Data([0x01, 0x02])
        let cutout = Data([0x03, 0x04])
        let garment = Garment(
            name: "레더 재킷", brand: "WEARY", category: .outer,
            colorName: "브라운", colorHex: "8D6748", size: "M",
            cutoutImageData: cutout
        )
        let outfit = Outfit(wornAt: Date(timeIntervalSince1970: 100), photoData: photo)
        outfit.items = [OutfitItem(garment: garment, outfit: outfit, displayOrder: 0)]

        let post = CommunityPost(
            authorName: "나", authorHandle: "my.weary", authorInitials: "ME",
            caption: "오늘의 룩", outfit: outfit
        )
        garment.name = "이름 변경"
        outfit.photoData = Data([0xFF])

        #expect(post.sourceOutfitID == outfit.id)
        #expect(post.outfitPhotoData == photo)
        #expect(post.outfitItems.map(\.name) == ["레더 재킷"])
        #expect(post.outfitItems.first?.cutoutImageData == cutout)
    }

    @Test("원격 커뮤니티 스냅샷을 로컬 피드 캐시에 반영한다")
    func communityPostAppliesServerSnapshot() {
        let postID = UUID()
        let authorID = UUID()
        let outfitID = UUID()
        let photo = Data([0x01, 0x02])
        let cutout = Data([0x03, 0x04])
        let garment = CommunityGarmentSnapshot(
            id: UUID(),
            name: "서버 재킷",
            brand: "WEARy",
            size: "M",
            categoryRaw: GarmentCategory.outer.rawValue,
            colorHex: "8D6748",
            cutoutImageData: cutout
        )
        let snapshot = CommunityFeedPostSnapshot(
            id: postID,
            authorID: authorID,
            authorName: "서버 사용자",
            authorHandle: "remote.user",
            authorInitials: "RU",
            authorAccentHex: "C7F25B",
            caption: "서버에서 가져온 룩",
            tags: ["오늘의룩", "서버"],
            createdAt: Date(timeIntervalSince1970: 300),
            likeCount: 7,
            comments: ["친구: 멋져요"],
            isLiked: true,
            isSaved: true,
            isFollowing: true,
            sourceOutfitID: outfitID,
            outfitPhotoData: photo,
            outfitItems: [garment]
        )
        let post = CommunityPost(
            id: postID,
            authorName: "이전 사용자",
            authorHandle: "old",
            authorInitials: "O",
            caption: "이전 내용"
        )

        post.applyServerSnapshot(snapshot)

        #expect(post.authorName == "서버 사용자")
        #expect(post.caption == "서버에서 가져온 룩")
        #expect(post.tags == ["오늘의룩", "서버"])
        #expect(post.likeCount == 7)
        #expect(post.comments == ["친구: 멋져요"])
        #expect(post.isLiked && post.isSaved && post.isFollowing)
        #expect(post.sourceOutfitID == outfitID)
        #expect(post.outfitPhotoData == photo)
        #expect(post.outfitItems == [garment])
        #expect(post.isSyncedFromServer == true)
        #expect(post.serverAuthorID == authorID)
    }

    @Test("원격 피드 캐시는 최신 서버 목록으로 교체하고 로컬 게시물은 보존한다")
    @MainActor
    func remoteFeedCacheReplacesOnlyServerPosts() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Garment.self, Outfit.self, OutfitItem.self, CommunityPost.self, MarketListing.self,
            configurations: configuration
        )
        let context = container.mainContext
        let localPost = CommunityPost(
            authorName: "나", authorHandle: "local", authorInitials: "ME", caption: "로컬 게시물"
        )
        let staleRemotePost = CommunityPost(
            authorName: "서버", authorHandle: "stale", authorInitials: "ST",
            caption: "삭제된 원격 게시물", isSyncedFromServer: true
        )
        context.insert(localPost)
        context.insert(staleRemotePost)
        try context.save()

        let remoteID = UUID()
        let snapshot = CommunityFeedPostSnapshot(
            id: remoteID,
            authorID: UUID(),
            authorName: "새 서버 사용자",
            authorHandle: "remote",
            authorInitials: "RS",
            authorAccentHex: "C7F25B",
            caption: "최신 원격 게시물",
            tags: ["오늘의룩"],
            createdAt: .now,
            likeCount: 0,
            comments: [],
            isLiked: false,
            isSaved: false,
            isFollowing: false,
            sourceOutfitID: nil,
            outfitPhotoData: nil,
            outfitItems: []
        )

        try CommunityFeedCacheStore.replaceRemoteWindow(with: [snapshot], in: context)

        let posts = try context.fetch(FetchDescriptor<CommunityPost>())
        #expect(posts.contains { $0.id == localPost.id })
        #expect(posts.contains { $0.id == remoteID && $0.isSyncedFromServer == true })
        #expect(!posts.contains { $0.id == staleRemotePost.id })
    }

    @Test("다음 원격 페이지를 합칠 때 기존 원격·로컬 게시물을 보존한다")
    @MainActor
    func remoteFeedCacheMergesAdditionalPages() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Garment.self, Outfit.self, OutfitItem.self, CommunityPost.self, MarketListing.self,
            configurations: configuration
        )
        let context = container.mainContext
        let localPost = CommunityPost(
            authorName: "나", authorHandle: "local", authorInitials: "ME", caption: "로컬 게시물"
        )
        let existingRemotePost = CommunityPost(
            authorName: "서버", authorHandle: "first", authorInitials: "FR",
            caption: "첫 페이지", isSyncedFromServer: true
        )
        context.insert(localPost)
        context.insert(existingRemotePost)
        try context.save()

        let nextRemoteID = UUID()
        let snapshot = CommunityFeedPostSnapshot(
            id: nextRemoteID,
            authorID: UUID(),
            authorName: "다음 서버 사용자",
            authorHandle: "next",
            authorInitials: "NX",
            authorAccentHex: "C7F25B",
            caption: "다음 페이지",
            tags: [],
            createdAt: .now,
            likeCount: 0,
            comments: [],
            isLiked: false,
            isSaved: false,
            isFollowing: false,
            sourceOutfitID: nil,
            outfitPhotoData: nil,
            outfitItems: []
        )

        try CommunityFeedCacheStore.mergeRemotePage([snapshot], in: context)

        let posts = try context.fetch(FetchDescriptor<CommunityPost>())
        #expect(posts.contains { $0.id == localPost.id })
        #expect(posts.contains { $0.id == existingRemotePost.id })
        #expect(posts.contains { $0.id == nextRemoteID && $0.isSyncedFromServer == true })
    }

    @Test("착장 아이템은 카테고리 기본 순서와 게시자 지정 순서를 따른다")
    func outfitItemsSupportDefaultAndCustomOrder() {
        let outfit = Outfit(wornAt: .now)
        let shoes = Garment(name: "스니커즈", category: .shoes, colorName: "실버", colorHex: "CCCCCC")
        let hat = Garment(name: "비니", category: .hat, colorName: "블랙", colorHex: "111111")
        let bottom = Garment(name: "데님", category: .bottom, colorName: "블루", colorHex: "7392B7")
        let outer = Garment(name: "재킷", category: .outer, colorName: "브라운", colorHex: "8D6748")
        let items = [
            OutfitItem(garment: shoes, outfit: outfit),
            OutfitItem(garment: bottom, outfit: outfit),
            OutfitItem(garment: hat, outfit: outfit),
            OutfitItem(garment: outer, outfit: outfit),
        ]
        outfit.items = items

        #expect(outfit.orderedItems.compactMap(\.garment?.category) == [.hat, .outer, .bottom, .shoes])

        outfit.applyItemOrder([items[0].id, items[1].id, items[3].id, items[2].id])
        #expect(outfit.orderedItems.compactMap(\.garment?.category) == [.shoes, .bottom, .outer, .hat])
    }

    @Test("마켓 상태를 판매 중에서 예약 중으로 변경할 수 있다")
    func marketListingStatusUpdates() {
        let listing = MarketListing(
            sellerName: "판매자", title: "재킷", detailText: "상세",
            price: 50_000
        )

        listing.status = .reserved

        #expect(listing.status == .reserved)
    }

    @Test("내 매물은 장소와 채팅 인원 및 판매 상태를 관리한다")
    func ownedMarketListingManagementValues() {
        let listing = MarketListing(
            sellerName: "나의 WEARy",
            title: "재킷",
            detailText: "직접 작성한 설명",
            price: 50_000,
            meetingPlace: "성수역 3번 출구",
            meetingAddress: "서울 성동구 아차산로 18",
            meetingLatitude: 37.54458,
            meetingLongitude: 127.05596,
            chatCount: 3
        )

        listing.price = 45_000
        listing.status = .sold

        #expect(listing.isOwnedByCurrentUser)
        #expect(listing.displayedMeetingPlace == "성수역 3번 출구")
        #expect(listing.hasPinnedMeetingPlace)
        #expect(listing.meetingLatitude == 37.54458)
        #expect(listing.displayedChatCount == 3)
        #expect(listing.price == 45_000)
        #expect(listing.status == .sold)
    }

    @Test("판매 가격 변경은 직전 가격 대비 증감액을 보존한다")
    func marketListingTracksPriceChange() {
        let listing = MarketListing(
            sellerName: "나의 WEARy",
            title: "재킷",
            detailText: "상세",
            price: 50_000
        )

        listing.updatePrice(to: 56_000)
        #expect(listing.previousPrice == 50_000)
        #expect(listing.priceChange == 6_000)

        listing.updatePrice(to: 49_000)
        #expect(listing.previousPrice == 56_000)
        #expect(listing.priceChange == -7_000)
    }

    @Test("판매 사진과 옷장 데이터 인증 공개 여부를 저장한다")
    func marketListingStoresGalleryAndVerificationChoice() {
        let firstImage = Data([0x01, 0x02])
        let secondImage = Data([0x03, 0x04])
        let listing = MarketListing(
            sellerName: "나의 WEARy",
            title: "재킷",
            detailText: "상세",
            price: 50_000,
            galleryImages: [firstImage],
            showsWardrobeVerification: true
        )

        #expect(listing.galleryImages == [firstImage])
        #expect(listing.showsWardrobeVerification)

        listing.updateGalleryImages([firstImage, secondImage])
        listing.showsWardrobeVerification = false

        #expect(listing.galleryImages == [firstImage, secondImage])
        #expect(!listing.showsWardrobeVerification)
    }

    @Test("마켓 매물은 공개를 선택한 옷장 데이터를 게시 시점 스냅샷으로 보존한다")
    func marketListingCapturesWardrobeSnapshot() {
        let cutout = Data([0x01, 0x02])
        let garment = Garment(
            name: "니트", category: .top, colorName: "블랙", colorHex: "111111",
            purchasePrice: 90_000, size: "M", cutoutImageData: cutout
        )
        let outfit = Outfit(wornAt: Date(timeIntervalSince1970: 200))
        garment.outfitItems = [OutfitItem(garment: garment, outfit: outfit)]

        let listing = MarketListing(
            sellerName: "나의 WEARy", title: "니트", detailText: "상세",
            price: 45_000, showsWardrobeVerification: true, garment: garment
        )
        garment.purchasePrice = 100_000

        #expect(listing.sourceGarmentID == garment.id)
        #expect(listing.garmentNameSnapshot == "니트")
        #expect(listing.garmentCutoutImageDataSnapshot == cutout)
        #expect(listing.verificationPurchasePrice == 90_000)
        #expect(listing.verificationWearCount == 1)
    }

    @Test("원격 마켓 캐시는 서버 목록으로 교체하고 로컬 매물은 보존한다")
    @MainActor
    func remoteMarketCacheReplacesOnlyServerListings() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Garment.self, Outfit.self, OutfitItem.self, CommunityPost.self, MarketListing.self,
            configurations: configuration
        )
        let context = container.mainContext
        let localListing = MarketListing(
            sellerName: "나", title: "로컬 재킷", detailText: "로컬 매물", price: 30_000
        )
        let staleRemoteListing = MarketListing(
            sellerName: "서버", title: "사라진 재킷", detailText: "이전 원격 매물",
            price: 40_000, isSyncedFromServer: true, serverSellerID: UUID()
        )
        context.insert(localListing)
        context.insert(staleRemoteListing)
        try context.save()

        let remoteID = UUID()
        let sellerID = UUID()
        let gallery = Data([0x01, 0x02])
        let cutout = Data([0x03, 0x04])
        let snapshot = MarketListingSnapshot(
            id: remoteID,
            sellerID: sellerID,
            sellerName: "원격 판매자",
            title: "원격 코트",
            detailText: "서버 상세",
            price: 55_000,
            previousPrice: 60_000,
            size: "M",
            condition: .likeNew,
            status: .reserved,
            createdAt: .now,
            isLiked: true,
            accentHex: "112233",
            meetingPlace: "성수역",
            meetingAddress: "서울 성동구",
            meetingLatitude: 37.5,
            meetingLongitude: 127.0,
            chatCount: 0,
            galleryImages: [gallery],
            showsWardrobeVerification: true,
            sourceGarmentID: UUID(),
            garmentNameSnapshot: "옷장 코트",
            garmentBrandSnapshot: "WEARy",
            garmentCategoryRawSnapshot: GarmentCategory.outer.rawValue,
            garmentColorHexSnapshot: "112233",
            garmentCutoutImageDataSnapshot: cutout,
            verificationPurchasePrice: 120_000,
            verificationLastWornAt: Date(timeIntervalSince1970: 100),
            verificationWearCount: 4,
            isOwnedByCurrentUser: false
        )

        try MarketListingCacheStore.replaceRemoteListings(with: [snapshot], in: context)

        let listings = try context.fetch(FetchDescriptor<MarketListing>())
        let remote = try #require(listings.first { $0.id == remoteID })
        #expect(listings.contains { $0.id == localListing.id })
        #expect(!listings.contains { $0.id == staleRemoteListing.id })
        #expect(remote.serverSellerID == sellerID)
        #expect(remote.isSyncedFromServer == true)
        #expect(remote.priceChange == -5_000)
        #expect(remote.status == .reserved)
        #expect(remote.galleryImages == [gallery])
        #expect(remote.garmentCutoutImageDataSnapshot == cutout)
        #expect(remote.showsWardrobeVerification)
        #expect(!remote.isOwnedByCurrentUser)
    }

    @Test("정리 추천은 기준일보다 오래된 활성 옷만 포함한다")
    func reviewCandidatesRespectStatusAndThreshold() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oldDate = Calendar.current.date(byAdding: .day, value: -200, to: now)
        let active = Garment(
            name: "오래된 셔츠", category: .top, colorName: "블루", colorHex: "0000FF",
            purchaseDate: oldDate
        )
        let kept = Garment(
            name: "유지할 재킷", category: .outer, colorName: "블랙", colorHex: "000000",
            purchaseDate: oldDate, status: .keep
        )

        let result = WardrobeInsights.reviewCandidates(
            garments: [active, kept], thresholdDays: 180, now: now
        )

        #expect(result.map(\.id) == [active.id])
    }

    @Test("확정된 착장만 기간별 착용 횟수에 반영한다")
    func usageCountsConfirmedOutfitsOnly() {
        let garment = Garment(
            name: "데님", category: .bottom, colorName: "블루", colorHex: "7392B7"
        )
        let confirmed = Outfit(wornAt: .now, isConfirmed: true)
        let draft = Outfit(wornAt: .now, isConfirmed: false)
        let confirmedItem = OutfitItem(garment: garment, outfit: confirmed)
        let draftItem = OutfitItem(garment: garment, outfit: draft)
        garment.outfitItems = [confirmedItem, draftItem]

        let usage = WardrobeInsights.usage(garments: [garment], period: .thirtyDays)

        #expect(usage.first?.count == 1)
        #expect(garment.wearCount == 1)
    }

    @Test("AI 추천 지표는 새로 분석한 확정 착장만 집계한다")
    func aiRecommendationSummaryUsesConfirmedAnalyzedOutfits() {
        let top = Garment(name: "셔츠", category: .top, colorName: "화이트", colorHex: "FFFFFF")
        let bottom = Garment(name: "데님", category: .bottom, colorName: "블루", colorHex: "7392B7")
        let shoes = Garment(name: "스니커즈", category: .shoes, colorName: "화이트", colorHex: "FFFFFF")
        let first = Outfit(
            wornAt: .now,
            aiAnalysisAttempted: true,
            visionCandidateCount: 3,
            visionAcceptedCount: 2,
            visionTopOneAcceptedCount: 1,
            visionAdjustedCount: 1
        )
        first.items = [
            OutfitItem(garment: top, outfit: first, source: .vision, suggestedRank: 1),
            OutfitItem(
                garment: bottom,
                outfit: first,
                source: .vision,
                suggestedRank: 2,
                wasManuallyAdjusted: true
            ),
        ]
        let second = Outfit(
            wornAt: .now,
            aiAnalysisAttempted: true,
            visionCandidateCount: 2,
            visionAcceptedCount: 1,
            visionAdjustedCount: 2,
            aiAnalysisUsedFallback: true
        )
        second.items = [
            OutfitItem(
                garment: shoes,
                outfit: second,
                source: .vision,
                wasManuallyAdjusted: true
            ),
        ]
        let legacy = Outfit(wornAt: .now)
        let draft = Outfit(
            wornAt: .now,
            isConfirmed: false,
            aiAnalysisAttempted: true,
            visionCandidateCount: 99
        )

        let summary = WardrobeInsights.aiRecommendationSummary(
            outfits: [first, second, legacy, draft]
        )

        #expect(summary.analyzedOutfitCount == 2)
        #expect(summary.visionCandidateCount == 5)
        #expect(summary.visionAcceptedCount == 3)
        #expect(summary.acceptanceRate == 60)
        #expect(summary.topOneRate == 33)
        #expect(summary.adjustmentRate == 60)
        #expect(summary.fallbackOutfitCount == 1)
        first.items = []
        #expect(WardrobeInsights.aiRecommendationSummary(outfits: [first, second]) == summary)
    }

    @Test("착장 수정은 선택한 옷과 메모를 갱신한다")
    @MainActor
    func outfitEditingUpdatesItemsAndNote() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Garment.self, Outfit.self, OutfitItem.self, CommunityPost.self, MarketListing.self,
            configurations: configuration
        )
        let context = container.mainContext
        let top = Garment(name: "티셔츠", category: .top, colorName: "화이트", colorHex: "FFFFFF")
        let bottom = Garment(name: "데님", category: .bottom, colorName: "블루", colorHex: "7392B7")
        let outfit = Outfit(wornAt: .now)
        context.insert(top)
        context.insert(bottom)
        context.insert(outfit)
        context.insert(OutfitItem(garment: top, outfit: outfit, source: .ai, confidence: .high))
        try context.save()

        try OutfitRecordService.update(
            outfit,
            wornAt: outfit.wornAt,
            note: "비 오는 날",
            selectedGarments: [bottom],
            in: context
        )

        #expect(outfit.note == "비 오는 날")
        #expect(outfit.items.compactMap(\.garment?.id) == [bottom.id])
        #expect(bottom.wearCount == 1)
    }

    @Test("착장 수정은 사용자가 지정한 아이템 순서를 저장한다")
    @MainActor
    func outfitEditingPreservesCustomItemOrder() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Garment.self, Outfit.self, OutfitItem.self, CommunityPost.self, MarketListing.self,
            configurations: configuration
        )
        let context = container.mainContext
        let hat = Garment(name: "비니", category: .hat, colorName: "블랙", colorHex: "111111")
        let shoes = Garment(name: "스니커즈", category: .shoes, colorName: "화이트", colorHex: "FFFFFF")
        let outfit = Outfit(wornAt: .now)
        context.insert(hat)
        context.insert(shoes)
        context.insert(outfit)
        context.insert(OutfitItem(garment: hat, outfit: outfit))
        context.insert(OutfitItem(garment: shoes, outfit: outfit))
        try context.save()

        try OutfitRecordService.update(
            outfit,
            wornAt: outfit.wornAt,
            note: "신발을 먼저 보여주기",
            selectedGarments: [shoes, hat],
            in: context
        )

        #expect(outfit.orderedItems.compactMap(\.garment?.id) == [shoes.id, hat.id])
    }

    @Test("회원 아이디는 허용된 형식만 통과한다")
    func validatesAccountHandle() {
        #expect(AccountInputValidator.isValidHandle("weary.user_01"))
        #expect(!AccountInputValidator.isValidHandle("WEARy"))
        #expect(!AccountInputValidator.isValidHandle("두글자"))
        #expect(!AccountInputValidator.isValidHandle("ab"))
        #expect(!AccountInputValidator.isValidHandle("space user"))
    }

    @Test("로그인은 이메일과 유효한 아이디를 모두 허용한다")
    func validatesLoginIdentifier() {
        #expect(AccountInputValidator.isValidLoginIdentifier("hello@example.com"))
        #expect(AccountInputValidator.isValidLoginIdentifier("admin"))
        #expect(AccountInputValidator.isValidLoginIdentifier("weary.user_01"))
        #expect(!AccountInputValidator.isValidLoginIdentifier("ab"))
        #expect(!AccountInputValidator.isValidLoginIdentifier("한글아이디"))
    }

    @Test("새 매물은 닉네임과 무관하게 내 매물로 식별한다")
    func recognizesOwnedListingWithCustomNickname() {
        let listing = MarketListing(
            sellerName: "새 닉네임",
            title: "재킷",
            detailText: "설명",
            price: 30_000,
            isOwnedByCurrentUser: true
        )

        #expect(listing.isOwnedByCurrentUser)
    }

    @Test("개인 옷장과 서비스 캐시는 서로 다른 저장소를 사용한다")
    @MainActor
    func separatesPersonalDataFromServiceCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "weary-persistence-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyStoreURL = directory.appending(path: "default.store")
        do {
            let legacyConfiguration = ModelConfiguration(
                "Legacy",
                schema: AppModelContainerFactory.appSchema,
                url: legacyStoreURL,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: AppModelContainerFactory.appSchema,
                configurations: [legacyConfiguration]
            )
            let legacyContext = legacyContainer.mainContext
            legacyContext.insert(Garment(
                name: "기존 개인 옷",
                category: .top,
                colorName: "화이트",
                colorHex: "FFFFFF"
            ))
            legacyContext.insert(CommunityPost(
                authorName: "기존 캐시 사용자",
                authorHandle: "legacy-cache-user",
                authorInitials: "기",
                caption: "분리 전 서비스 캐시"
            ))
            try legacyContext.save()
        }

        let container = try AppModelContainerFactory.make(
            isStoredInMemoryOnly: false,
            baseDirectoryURL: directory,
            cloudKitEnabled: false
        )
        let context = container.mainContext
        context.insert(CommunityPost(
            authorName: "캐시 사용자",
            authorHandle: "cache-user",
            authorInitials: "캐",
            caption: "서비스 캐시"
        ))
        try context.save()

        let configurationNames = Set(container.configurations.map(\.name))
        #expect(configurationNames == ["Personal", "ServiceCache"])
        #expect(FileManager.default.fileExists(atPath: legacyStoreURL.path()))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "service-cache.store").path()))
        #expect(try context.fetchCount(FetchDescriptor<Garment>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CommunityPost>()) == 1)
    }

    @Test("개인 CloudKit 모델은 고유 제약 없이 기본값과 역관계를 갖는다")
    func personalSchemaMeetsCloudKitRequirements() {
        for entity in AppModelContainerFactory.personalSchema.entities {
            #expect(entity.uniquenessConstraints.isEmpty)
            for attribute in entity.attributes {
                #expect(attribute.isOptional || attribute.defaultValue != nil)
            }
            for relationship in entity.relationships {
                #expect(relationship.inverseName != nil)
                #expect((relationship.minimumModelCount ?? 0) == 0)
            }
        }
    }

    @Test("계정 변경 캐시 정리는 개인 데이터와 데모를 보존한다")
    @MainActor
    func clearingRemoteCachePreservesPersonalDataAndDemo() throws {
        let container = try AppModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let garment = Garment(name: "내 셔츠", category: .top, colorName: "화이트", colorHex: "FFFFFF")
        let outfit = Outfit(wornAt: .now)
        context.insert(garment)
        context.insert(outfit)
        let remotePost = CommunityPost(authorName: "이전 계정", authorHandle: "old", authorInitials: "O", caption: "원격")
        remotePost.isSyncedFromServer = true
        context.insert(remotePost)
        context.insert(CommunityPost(authorName: "데모", authorHandle: "demo", authorInitials: "D", caption: "샘플"))
        context.insert(MarketListing(sellerName: "이전 계정", title: "원격", detailText: "", price: 1000, isSyncedFromServer: true))
        context.insert(MarketListing(sellerName: "데모", title: "샘플", detailText: "", price: 2000))
        try context.save()

        try ServiceCacheBoundary.clearRemoteCache(in: context)
        try ServiceCacheBoundary.clearRemoteCache(in: context)

        #expect(try context.fetchCount(FetchDescriptor<Garment>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Outfit>()) == 1)
        let posts = try context.fetch(FetchDescriptor<CommunityPost>())
        #expect(posts.count == 1)
        #expect(posts.first?.authorHandle == "demo")
        let listings = try context.fetch(FetchDescriptor<MarketListing>())
        #expect(listings.count == 1)
        #expect(listings.first?.title == "샘플")
    }

    @Test("옷 저장 실패 복원은 기존 구매 정보와 사진을 유지한다")
    @MainActor
    func garmentMutationBackupRestoresOriginalValues() {
        let image = Data([1, 2, 3])
        let garment = Garment(name: "원래 이름", brand: "브랜드", category: .top,
                              colorName: "화이트", colorHex: "FFFFFF", purchasePrice: 45000,
                              size: "M", imageData: image, cutoutImageData: image)
        let backup = GarmentMutationBackup(garment)
        garment.name = "수정 이름"
        garment.category = .bottom
        garment.purchasePrice = nil
        garment.imageData = nil
        garment.cutoutImageData = nil
        backup.restore()
        #expect(garment.name == "원래 이름")
        #expect(garment.category == .top)
        #expect(garment.purchasePrice == 45000)
        #expect(garment.imageData == image)
        #expect(garment.cutoutImageData == image)
    }
}

private func solidImageData(red: CGFloat, green: CGFloat, blue: CGFloat) -> Data? {
    let size = CGSize(width: 480, height: 640)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor.white.setFill()
        context.fill(CGRect(x: 110, y: 150, width: 260, height: 340))
    }.pngData()
}
