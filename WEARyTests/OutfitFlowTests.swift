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
}
