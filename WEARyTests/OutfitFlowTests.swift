import Foundation
import Testing
@testable import WEARy

@Suite("착장 기록 핵심 규칙")
struct OutfitFlowTests {
    @Test("데모 분석기는 카테고리별 후보를 반환한다")
    @MainActor
    func analyzerReturnsCategoryGroups() async throws {
        let topID = UUID()
        let bottomID = UUID()
        let wardrobe = [
            GarmentSnapshot(id: topID, category: .top, name: "티셔츠"),
            GarmentSnapshot(id: bottomID, category: .bottom, name: "데님"),
        ]

        let result = try await DemoOutfitAnalyzer().analyze(wardrobe: wardrobe)

        #expect(result.map(\.category) == [.top, .bottom])
        #expect(result.map(\.selectedGarmentID) == [topID, bottomID])
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

    @Test("마켓 상태를 판매 중에서 예약 중으로 변경할 수 있다")
    func marketListingStatusUpdates() {
        let listing = MarketListing(
            sellerName: "판매자", title: "재킷", detailText: "상세",
            price: 50_000
        )

        listing.status = .reserved

        #expect(listing.status == .reserved)
    }
}
