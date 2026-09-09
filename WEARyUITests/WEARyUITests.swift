import XCTest

@MainActor
final class WEARyUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    func testCoreOutfitFlowUpdatesMyPage() throws {
        continueAfterFailure = false
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["옷장"].waitForExistence(timeout: 3))

        app.tabBars.buttons["기록"].tap()
        XCTAssertTrue(app.buttons["capture.camera"].waitForExistence(timeout: 3))
        let sampleButton = app.buttons["capture.sample"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 3))
        sampleButton.tap()

        let analyzeButton = app.buttons["capture.analyze"]
        XCTAssertTrue(analyzeButton.waitForExistence(timeout: 2))
        analyzeButton.tap()

        let saveButton = app.buttons["capture.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        XCTAssertTrue(app.staticTexts["오늘의 룩을 기록했어요"].waitForExistence(timeout: 3))

        app.tabBars.buttons["MY"].tap()
        XCTAssertTrue(app.navigationBars["MY"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["나의 착장 캘린더"].exists)
    }

    func testCommunityAndMarketTabsHaveSeedContent() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["피드"].tap()
        XCTAssertTrue(app.navigationBars["!WEARy"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["서연"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(identifier: "feed.outfitPhoto").count,
            0
        )
        app.staticTexts["서연"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["이 룩의 아이템"].waitForExistence(timeout: 3))

        app.tabBars.buttons["마켓"].tap()
        XCTAssertTrue(app.navigationBars["마켓"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["옷장에서 다음 옷장으로"].waitForExistence(timeout: 3))
        app.staticTexts["빈티지 레더 재킷"].firstMatch.tap()
        XCTAssertTrue(app.buttons["market.buyerLike"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["market.buyerChat"].exists)
        XCTAssertFalse(app.buttons["구매 요청"].exists)
    }

    func testOwnedMarketListingProvidesSellerManagement() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["마켓"].tap()

        app.staticTexts["블랙 니트 드레스"].firstMatch.tap()
        XCTAssertTrue(app.buttons["market.ownerMenu"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["market.ownerLike"].exists)
        XCTAssertTrue(app.buttons["market.ownerChat"].exists)
        XCTAssertFalse(app.buttons["market.adjustPrice"].exists)
        XCTAssertFalse(app.buttons["market.markSold"].exists)
        XCTAssertTrue(app.staticTexts["성수역 3번 출구"].exists)
        XCTAssertTrue(app.otherElements["market.meetingMap"].exists)

        app.buttons["market.ownerMenu"].tap()
        app.buttons["수정"].tap()
        XCTAssertTrue(app.navigationBars["수정"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["market.saveEdit"].exists)
        XCTAssertTrue(app.textFields["market.priceInput"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "market.priceWheel").count, 0)
        XCTAssertTrue(app.buttons["market.editPlace"].exists)
        app.buttons["market.editPlace"].tap()
        XCTAssertTrue(app.navigationBars["만날 장소"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["market.placeQuery"].exists)
        XCTAssertTrue(app.otherElements["market.placeMap"].exists)
        app.buttons["취소"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["market.editMarkSold"].waitForExistence(timeout: 3))
    }

    func testFeedComposerFilterAndFollowingConnectToMy() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["피드"].tap()

        app.buttons["feed.compose"].tap()
        XCTAssertTrue(app.navigationBars["피드 작성"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["feed.publish"].exists)
        app.buttons["취소"].tap()

        app.buttons["feed.topic.빈티지"].tap()
        XCTAssertTrue(app.staticTexts["서연"].waitForExistence(timeout: 3))
        app.buttons
            .matching(identifier: "follow.seoyeon.daily")
            .matching(NSPredicate(format: "label == %@", "팔로우"))
            .element
            .tap()

        app.tabBars.buttons["MY"].tap()
        app.buttons["profile.following"].tap()
        XCTAssertTrue(app.navigationBars["팔로잉"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(identifier: "social.user.seoyeon.daily").count,
            0
        )
    }

    func testMyCalendarCardFlipsBetweenItemsAndPhoto() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["MY"].tap()

        let today = app.buttons["calendar.today"]
        XCTAssertTrue(today.waitForExistence(timeout: 3))
        for _ in 0..<5 where !today.isHittable { app.swipeUp() }
        XCTAssertTrue(today.isHittable)
        today.tap()

        let flipButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "outfit.flip.")
        ).firstMatch
        XCTAssertTrue(flipButton.waitForExistence(timeout: 3))
        let itemFace = app.descendants(matching: .any).matching(identifier: "outfit.itemFace").firstMatch
        let photoFace = app.descendants(matching: .any).matching(identifier: "outfit.photoFace").firstMatch
        XCTAssertTrue(itemFace.exists)

        flipButton.tap()
        XCTAssertTrue(photoFace.waitForExistence(timeout: 3))
        flipButton.tap()
        XCTAssertTrue(itemFace.waitForExistence(timeout: 3))
    }

    func testUnavailableCameraShowsPhotoFallbackGuidance() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-no-camera"]
        app.launch()
        app.tabBars.buttons["기록"].tap()

        let cameraButton = app.buttons["capture.camera"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 3))
        cameraButton.tap()

        XCTAssertTrue(app.alerts["카메라를 열 수 없어요"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["이 기기에서는 카메라를 사용할 수 없어요. 사진 보관함이나 샘플 사진을 이용해 주세요."].exists)
        app.alerts.buttons["확인"].tap()
        XCTAssertTrue(app.buttons["capture.sample"].exists)
    }

    func testGarmentRegistrationUsesOneOptionalPurchaseFlow() throws {
        continueAfterFailure = false
        let app = launchApp()

        app.buttons["새 옷 등록"].tap()
        XCTAssertTrue(app.navigationBars["새 옷 등록"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["빠른 등록"].exists)
        XCTAssertFalse(app.staticTexts["새로 산 옷"].exists)

        app.buttons["garment.camera"].tap()
        XCTAssertTrue(app.alerts["카메라를 열 수 없어요"].waitForExistence(timeout: 3))
        app.alerts.buttons["확인"].tap()

        app.swipeUp()
        XCTAssertTrue(app.switches["구매일 입력"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["구매 가격 (선택)"].exists)
        XCTAssertTrue(app.textFields["사이즈 (선택)"].exists)
    }

    func testOnboardingExplainsCoreLoopAndEntersWardrobe() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-onboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["옷을 산 순간부터\n기록해요"].waitForExistence(timeout: 3))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["오늘 입은 옷을\n사진 한 장으로"].waitForExistence(timeout: 2))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["내 취향을 발견하고\n다음 옷장으로"].waitForExistence(timeout: 2))
        app.buttons["onboarding.start"].tap()

        XCTAssertTrue(app.navigationBars["옷장"].waitForExistence(timeout: 3))
    }

    func testAccessibilityTextSizeKeepsCoreNavigationUsable() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["옷장"].waitForExistence(timeout: 3))
        app.tabBars.buttons["기록"].tap()
        XCTAssertTrue(app.buttons["capture.sample"].waitForExistence(timeout: 3))
        app.tabBars.buttons["MY"].tap()
        XCTAssertTrue(app.navigationBars["MY"].waitForExistence(timeout: 3))
    }
}
