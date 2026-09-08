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
