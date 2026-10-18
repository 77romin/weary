import XCTest

@MainActor
final class WEARyUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    private func scrollFittingMargin(_ app: XCUIApplication, up: Bool) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.35))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
        (up ? bottom : top).press(forDuration: 0.05, thenDragTo: up ? top : bottom)
    }

    func testVirtualFittingManualPreviewAndReset() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["옷장"].tap()
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("화이트 베이비 티")
        let garment = app.buttons["wardrobe.garment.화이트 베이비 티"]
        XCTAssertTrue(garment.waitForExistence(timeout: 3))
        garment.tap()
        let entry = app.buttons["garment.tryOn"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertTrue(entry.isEnabled)
        entry.tap()
        XCTAssertTrue(app.navigationBars["가상 피팅 · 실험"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["fitting.stage"].exists)
        XCTAssertTrue(app.buttons["fitting.selectPhoto"].exists)
        XCTAssertFalse(app.buttons["fitting.start"].exists)
        XCTAssertFalse(app.buttons["fitting.switchCamera"].exists)
        app.buttons["fitting.sample"].tap()
        XCTAssertTrue(app.staticTexts["샘플 사진 · 합성 아님"].waitForExistence(timeout: 3))
        let finished = NSPredicate { _, _ in
            app.images["fitting.overlay"].exists || app.buttons["fitting.manual"].exists
        }
        expectation(for: finished, evaluatedWith: nil)
        waitForExpectations(timeout: 15)
        // Simulator pose runtime may be unavailable; explicit manual recovery is
        // not evidence of automatic fitting success (covered separately in unit tests).
        if app.buttons["fitting.manual"].exists { app.buttons["fitting.manual"].tap() }
        XCTAssertTrue(app.images["fitting.overlay"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "photo-fitting-sample-not-live"
        attachment.lifetime = .keepAlways
        add(attachment)

        let scale = app.sliders["fitting.scale"]
        for _ in 0..<6 {
            if scale.isHittable && scale.frame.maxY < app.frame.maxY - 100 { break }
            scrollFittingMargin(app, up: true)
        }
        XCTAssertLessThan(scale.frame.maxY, app.frame.maxY - 100)
        let initialScale = scale.value as? String
        scale.adjust(toNormalizedSliderPosition: 0.95)
        XCTAssertNotEqual(scale.value as? String, initialScale)
        for _ in 0..<4 where !app.buttons["fitting.reset"].isHittable { scrollFittingMargin(app, up: true) }
        app.buttons["fitting.reset"].tap()
        XCTAssertEqual(scale.value as? String, initialScale)
        for _ in 0..<5 where !app.buttons["fitting.clear"].isHittable { scrollFittingMargin(app, up: false) }
        app.buttons["fitting.clear"].tap()
        XCTAssertFalse(app.images["fitting.overlay"].exists)
        app.buttons["fitting.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.tap()
        XCTAssertTrue(app.staticTexts["한 명의 양쪽 어깨가 보이는 사진을 선택해 주세요. 상반신만 나와도 괜찮아요."].waitForExistence(timeout: 3))
        app.buttons["fitting.close"].tap()
    }

    func testVirtualFittingIsDisabledForNonTopGarment() throws {
        let app = launchApp()
        app.tabBars.buttons["옷장"].tap()
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("커브드 데님")
        app.buttons["wardrobe.garment.커브드 데님"].tap()
        let entry = app.buttons["garment.tryOn"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertFalse(entry.isEnabled)
        XCTAssertTrue(app.staticTexts["현재는 사진이 있는 상의만 지원해요."].exists)
    }

    func testSignedOutLaunchShowsAuthenticationOptions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-authentication"]
        app.launch()

        XCTAssertTrue(app.otherElements["auth.login"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["auth.email"].exists)
        XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        XCTAssertTrue(app.buttons["아이디 / 비밀번호 찾기"].exists)
        XCTAssertTrue(app.buttons["auth.oauth.google"].exists)
        XCTAssertTrue(app.buttons["auth.oauth.kakao"].exists)
        XCTAssertTrue(app.buttons["auth.oauth.apple"].exists)
        XCTAssertTrue(app.buttons["auth.openSignUp"].exists)

        app.buttons["아이디 / 비밀번호 찾기"].tap()
        XCTAssertTrue(app.navigationBars["계정 찾기"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["recovery.email"].exists)
        XCTAssertTrue(app.buttons["recovery.handle"].exists)
        XCTAssertTrue(app.buttons["recovery.password"].exists)
        app.navigationBars["계정 찾기"].buttons["완료"].tap()

        app.buttons["auth.openSignUp"].tap()
        XCTAssertTrue(app.navigationBars["회원가입"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["signup.handle"].exists)
        XCTAssertTrue(app.textFields["signup.nickname"].exists)
        XCTAssertTrue(app.textFields["signup.email"].exists)
        XCTAssertTrue(app.buttons["signup.checkAvailability"].exists)
        XCTAssertTrue(app.buttons["signup.submit"].exists)
    }

    func testCoreOutfitFlowUpdatesMyPage() throws {
        continueAfterFailure = false
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["!WEARy"].waitForExistence(timeout: 3))

        app.tabBars.buttons["기록"].tap()
        XCTAssertTrue(app.buttons["capture.camera"].waitForExistence(timeout: 3))
        let sampleButton = app.buttons["capture.sample"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 3))
        sampleButton.tap()

        let analyzeButton = app.buttons["capture.analyze"]
        XCTAssertTrue(analyzeButton.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["capture.reset"].isHittable)
        analyzeButton.tap()

        let saveButton = app.buttons["capture.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        XCTAssertTrue(app.staticTexts["오늘의 룩을 기록했어요"].waitForExistence(timeout: 3))

        app.tabBars.buttons["MY"].tap()
        XCTAssertTrue(app.navigationBars["MY"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["나의 착장 캘린더"].exists)
    }

    func testCapturePublicPostRequiresPhotoConsent() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["기록"].tap()
        XCTAssertTrue(app.buttons["capture.sample"].waitForExistence(timeout: 3))
        app.buttons["capture.sample"].tap()
        XCTAssertTrue(app.buttons["capture.analyze"].waitForExistence(timeout: 2))
        app.buttons["capture.analyze"].tap()

        let saveButton = app.buttons["capture.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["capture.publishToFeed"].exists)
        app.switches["capture.publishToFeed"].tap()
        XCTAssertFalse(saveButton.isEnabled)

        for _ in 0..<5 where !app.switches["photoConsent.publicUpload"].exists { app.swipeUp() }
        let uploadConsent = app.switches["photoConsent.publicUpload"]
        let rightsConsent = app.switches["photoConsent.publicationRights"]
        XCTAssertTrue(uploadConsent.waitForExistence(timeout: 2))
        XCTAssertTrue(rightsConsent.exists)
        uploadConsent.tap()
        XCTAssertFalse(saveButton.isEnabled)
        rightsConsent.tap()
        XCTAssertTrue(saveButton.isEnabled)
    }

    func testMyAccountProvidesSanctionAndAppealHistory() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["MY"].tap()
        app.buttons["profile.account"].tap()
        XCTAssertTrue(app.navigationBars["내 정보"].waitForExistence(timeout: 3))
        for _ in 0..<4 where !app.buttons["profile.accountSanctions"].exists { app.swipeUp() }
        app.buttons["profile.accountSanctions"].tap()
        XCTAssertTrue(app.navigationBars["계정 제재·이의 제기"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["계정 제재 내역이 없어요"].exists)
    }

    func testMyProvidesLocalVisionBenchmark() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["MY"].tap()
        for _ in 0..<8 where !app.buttons["profile.visionBenchmark"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["profile.visionBenchmark"].waitForExistence(timeout: 3))
        app.buttons["profile.visionBenchmark"].tap()
        XCTAssertTrue(app.navigationBars["Vision 성능 비교"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["착장 사진 선택하고 비교"].exists)
    }

    func testMyProvidesGroundTruthEvaluation() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["MY"].tap()
        for _ in 0..<8 where !app.buttons["profile.visionEvaluation"].exists { app.swipeUp() }
        app.buttons["profile.visionEvaluation"].tap()
        XCTAssertTrue(app.navigationBars["정답 기반 추천 평가"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["평가할 착장 사진 선택"].exists)
        XCTAssertFalse(app.buttons["지정한 정답으로 평가"].isEnabled)
        for _ in 0..<4 where !app.buttons["evaluation.share"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["evaluation.share"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["evaluation.share"].isEnabled)
    }

    func testMyProvidesCategoryVisibilityEvaluation() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["MY"].tap()
        for _ in 0..<10 where !app.buttons["profile.visibilityEvaluation"].isHittable { app.swipeUp() }
        app.buttons["profile.visibilityEvaluation"].tap()
        XCTAssertTrue(app.navigationBars["보이는 옷 종류 평가"].waitForExistence(timeout: 3))
        for _ in 0..<5 where !app.buttons["visibility.evaluate"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["visibility.evaluate"].exists)
        XCTAssertFalse(app.buttons["visibility.evaluate"].isEnabled)
        for _ in 0..<6 where !app.buttons["visibility.share"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["visibility.share"].exists)
        XCTAssertFalse(app.buttons["visibility.share"].isEnabled)
    }

    func testCategoryVisibilitySampleUsesRealAnalysisAndDoesNotEnterPhotoMetrics() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["MY"].tap()
        for _ in 0..<10 where !app.buttons["profile.visibilityEvaluation"].isHittable { app.swipeUp() }
        app.buttons["profile.visibilityEvaluation"].tap()
        XCTAssertTrue(app.navigationBars["보이는 옷 종류 평가"].waitForExistence(timeout: 3))
        app.buttons["visibility.sample"].tap()
        XCTAssertTrue(app.images["visibility.preview"].exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "category-visibility-photo-preview"
        preview.lifetime = .keepAlways
        add(preview)
        for _ in 0..<5 where !app.switches["상의"].isHittable { app.swipeUp() }
        app.switches["상의"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["상의"].value as? String, "1")
        let confirmation = app.switches["추천을 보기 전에 정답을 확인했어요"]
        for _ in 0..<5 where !confirmation.isHittable { app.swipeUp() }
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(confirmation.value as? String, "1")
        for _ in 0..<5 where !app.buttons["visibility.evaluate"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["visibility.evaluate"].isEnabled)
        app.buttons["visibility.evaluate"].tap()
        XCTAssertTrue(app.staticTexts["visibility.completed"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["visibility.error"].exists)
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "category-visibility-sample-result"
        result.lifetime = .keepAlways
        add(result)
        for _ in 0..<6 where !app.buttons["visibility.share"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["평가 사진 0장"].exists)
        XCTAssertFalse(app.buttons["visibility.share"].isEnabled)
    }

    func testCommunityAndMarketTabsHaveSeedContent() throws {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["피드"].tap()
        XCTAssertTrue(app.navigationBars["!WEARy"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(identifier: "feed.contentMode").count,
            0
        )
        XCTAssertTrue(app.buttons["feed.logo"].exists)
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

    func testFeedLogoScrollsToTopAndPullGestureRefreshes() throws {
        continueAfterFailure = false
        let app = launchApp()
        let logo = app.buttons["feed.logo"]
        let topTopic = app.buttons["feed.topic.전체"]
        XCTAssertTrue(logo.waitForExistence(timeout: 3))

        app.swipeUp()
        XCTAssertFalse(topTopic.isHittable)
        logo.tap()
        let returnedToTop = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: topTopic
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returnedToTop], timeout: 3), .completed)
        XCTAssertEqual(logo.value as? String, "새로고침 0회")

        logo.tap()
        XCTAssertEqual(logo.value as? String, "새로고침 0회")

        let feedScrollView = app.scrollViews["feed.scrollView"]
        XCTAssertTrue(feedScrollView.waitForExistence(timeout: 2))
        let pullStart = feedScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let pullEnd = feedScrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        pullStart.press(forDuration: 0.1, thenDragTo: pullEnd)
        let didRefresh = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "새로고침 1회"),
            object: logo
        )
        XCTAssertEqual(XCTWaiter.wait(for: [didRefresh], timeout: 2), .completed)
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
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(identifier: "market.photoGallery").count,
            0
        )
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(identifier: "market.verifiedBadge").count,
            0
        )

        app.buttons["market.ownerMenu"].tap()
        app.buttons["수정"].tap()
        XCTAssertTrue(app.navigationBars["수정"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["market.saveEdit"].exists)
        XCTAssertTrue(app.buttons["market.addPhotos"].exists)
        XCTAssertTrue(app.switches["market.editVerification"].exists)
        for _ in 0..<4 where !app.buttons["market.editPlace"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["market.editPlace"].exists)
        app.buttons["market.editPlace"].tap()
        XCTAssertTrue(app.navigationBars["만날 장소"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["market.placeQuery"].exists)
        XCTAssertTrue(app.otherElements["market.placeMap"].exists)
        app.navigationBars["만날 장소"].buttons["취소"].tap()
        for _ in 0..<4 where !app.textFields["market.priceInput"].exists { app.swipeUp() }
        XCTAssertTrue(app.textFields["market.priceInput"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "market.priceWheel").count, 0)
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
        for _ in 0..<5 where !app.switches["photoConsent.publicUpload"].exists { app.swipeUp() }
        XCTAssertTrue(app.switches["photoConsent.publicUpload"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["photoConsent.publicationRights"].exists)
        XCTAssertFalse(app.buttons["feed.publish"].isEnabled)
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
        for _ in 0..<5 where !today.exists { app.swipeUp() }
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

        app.tabBars.buttons["옷장"].tap()
        app.buttons["새 옷 등록"].tap()
        XCTAssertTrue(app.navigationBars["새 옷 등록"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["빠른 등록"].exists)
        XCTAssertFalse(app.staticTexts["새로 산 옷"].exists)
        XCTAssertFalse(app.switches["저장 후 다음 옷 등록"].exists)

        app.buttons["garment.camera"].tap()
        XCTAssertTrue(app.alerts["카메라를 열 수 없어요"].waitForExistence(timeout: 3))
        app.alerts.buttons["확인"].tap()

        app.swipeUp()
        XCTAssertTrue(app.switches["구매일 입력"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["구매 가격 (선택)"].exists)
        XCTAssertTrue(app.textFields["사이즈 (선택)"].exists)
    }

    func testOnboardingExplainsCoreLoopAndEntersFeed() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-onboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["옷을 산 순간부터\n기록해요"].waitForExistence(timeout: 8))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["오늘 입은 옷을\n사진 한 장으로"].waitForExistence(timeout: 2))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["내 취향을 발견하고\n다음 옷장으로"].waitForExistence(timeout: 2))
        app.buttons["onboarding.start"].tap()

        XCTAssertTrue(app.navigationBars["!WEARy"].waitForExistence(timeout: 3))
    }

    func testFirstLaunchShowsOnboardingBeforeLogin() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-signed-out"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["auth.login"].exists)
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertEqual(app.buttons["onboarding.start"].label, "!WEARy 시작하기")
        app.buttons["onboarding.start"].tap()
        XCTAssertTrue(app.otherElements["auth.login"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["auth.login"].exists)
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

        XCTAssertTrue(app.navigationBars["!WEARy"].waitForExistence(timeout: 3))
        app.tabBars.buttons["기록"].tap()
        XCTAssertTrue(app.buttons["capture.sample"].waitForExistence(timeout: 3))
        app.tabBars.buttons["MY"].tap()
        XCTAssertTrue(app.navigationBars["MY"].waitForExistence(timeout: 3))
    }
}
