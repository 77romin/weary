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

        app.tabBars.buttons["마켓"].tap()
        XCTAssertTrue(app.navigationBars["마켓"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["옷장에서 다음 옷장으로"].waitForExistence(timeout: 3))
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
