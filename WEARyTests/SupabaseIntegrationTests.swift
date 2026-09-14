import Foundation
import Supabase
import Testing
@testable import WEARy

@Suite("Supabase 수동 통합 검증", .serialized)
struct SupabaseIntegrationTests {
    @Test("계정 중복 확인은 동작하고 아이디의 이메일 조회는 외부에 노출하지 않는다")
    func checksAccountAvailabilityWithoutExposingLoginEmail() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else {
            return
        }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }

        let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let response: IntegrationAccountAvailability = try await client.functions.invoke(
            "account-auth",
            options: FunctionInvokeOptions(body: IntegrationAccountAvailabilityRequest(
                action: "availability",
                email: "\(marker)@example.com",
                handle: "u\(marker.prefix(19))",
                nickname: "통합검증\(marker.prefix(8))"
            ))
        )
        #expect(response.emailAvailable)
        #expect(response.handleAvailable)
        #expect(response.nicknameAvailable)

        var privateLookupWasDenied = false
        do {
            let _: String? = try await client
                .rpc("login_email_for_handle", params: ["p_handle": "missing-user"])
                .execute()
                .value
        } catch {
            privateLookupWasDenied = true
        }
        #expect(privateLookupWasDenied)
    }

    @Test("게시물과 이미지를 업로드한 뒤 원격 피드에서 읽는다")
    func publishesPostAndReadsItFromRemoteFeed() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else {
            return
        }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }

        let outfitID = UUID()
        let garmentID = UUID()
        let pixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        let marker = "Swift publish integration \(UUID().uuidString)"
        let draft = CommunityPostPublishDraft(
            sourceOutfitID: outfitID,
            caption: marker,
            tags: ["integration"],
            photoData: pixelPNG,
            items: [CommunityPostPublishItem(
                sourceGarmentID: garmentID,
                name: "통합 테스트 재킷",
                brand: "WEARy",
                categoryRaw: GarmentCategory.outer.rawValue,
                size: "M",
                colorHex: "222222",
                imageData: pixelPNG
            )]
        )

        let postID = try await SupabaseCommunityPostPublisher.shared.publish(draft)
        let userID = try await SupabaseSessionManager.shared.authenticatedUserID()
        var capturedError: Error?

        do {
            let feed = try await SupabaseCommunityFeedRepository.shared.fetchFeed(limit: 100)
            let published = try #require(feed.first { $0.id == postID })
            #expect(published.caption == marker)
            #expect(published.sourceOutfitID == outfitID)
            #expect(published.outfitPhotoData == pixelPNG)
            #expect(published.outfitItems.count == 1)
            #expect(published.outfitItems.first?.id == garmentID)
            #expect(published.outfitItems.first?.cutoutImageData == pixelPNG)
        } catch {
            capturedError = error
        }

        let basePath = "\(userID.uuidString)/\(postID.uuidString)"
        _ = try? await client.storage.from("community-media").remove(paths: [
            "\(basePath)/look.png",
            "\(basePath)/items/\(garmentID.uuidString).png",
        ])
        _ = try? await client
            .from("posts")
            .delete()
            .eq("id", value: postID.uuidString)
            .execute()

        if let capturedError { throw capturedError }
    }

    @Test("소셜 상호작용을 저장한 뒤 피드와 팔로우 목록에서 읽는다")
    func writesAndReadsCommunityInteractions() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else {
            return
        }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }

        let configuration = try supabaseConfiguration()
        let author = try await createAnonymousSession(configuration: configuration)
        let currentUserID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let postID = UUID()
        let comment = "Swift interaction integration \(UUID().uuidString)"
        try await restRequest(
            method: "POST",
            path: "/rest/v1/posts",
            configuration: configuration,
            token: author.token,
            body: [
                "id": postID.uuidString,
                "author_id": author.userID.uuidString,
                "caption": "Interaction repository test",
                "visibility": "public",
            ]
        )

        let interactions = SupabaseCommunityInteractionRepository.shared
        var capturedError: Error?
        do {
            try await interactions.setLike(postID: postID, isLiked: true)
            try await interactions.setBookmark(postID: postID, isSaved: true)
            try await interactions.addComment(postID: postID, body: comment)
            try await interactions.setFollowing(authorID: author.userID, isFollowing: true)

            let feed = try await SupabaseCommunityFeedRepository.shared.fetchFeed(limit: 100)
            let post = try #require(feed.first { $0.id == postID })
            #expect(post.isLiked)
            #expect(post.isSaved)
            #expect(post.isFollowing)
            #expect(post.comments.contains { $0.contains(comment) })

            let graph = try await interactions.fetchSocialGraph()
            #expect(graph.following.contains { $0.id == author.userID })
        } catch {
            capturedError = error
        }

        _ = try? await interactions.setLike(postID: postID, isLiked: false)
        _ = try? await interactions.setBookmark(postID: postID, isSaved: false)
        _ = try? await interactions.setFollowing(authorID: author.userID, isFollowing: false)
        _ = try? await client
            .from("comments")
            .delete()
            .eq("post_id", value: postID.uuidString)
            .eq("author_id", value: currentUserID.uuidString)
            .execute()
        _ = try? await restRequest(
            method: "DELETE",
            path: "/rest/v1/posts?id=eq.\(postID.uuidString)",
            configuration: configuration,
            token: author.token
        )

        if let capturedError { throw capturedError }
    }

    @Test("원격 피드를 커서로 나누어 읽으면 게시물이 중복되지 않는다")
    func readsRemoteFeedWithCursorPagination() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else {
            return
        }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }

        let userID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let baseDate = Date().addingTimeInterval(30)
        let rows = (0..<4).map { index in
            IntegrationPostInsert(
                id: UUID(),
                authorID: userID,
                caption: "Cursor integration \(index)",
                visibility: "public",
                createdAt: baseDate.addingTimeInterval(Double(index))
            )
        }
        try await client.from("posts").insert(rows).execute()

        var capturedError: Error?
        do {
            let firstPage = try await SupabaseCommunityFeedRepository.shared.fetchPage(
                before: nil,
                limit: 2
            )
            let cursor = try #require(firstPage.nextCursor)
            let secondPage = try await SupabaseCommunityFeedRepository.shared.fetchPage(
                before: cursor,
                limit: 2
            )
            let expectedIDs = rows.reversed().map(\.id)

            #expect(firstPage.posts.map(\.id) == Array(expectedIDs.prefix(2)))
            #expect(secondPage.posts.map(\.id) == Array(expectedIDs.dropFirst(2)))
            #expect(firstPage.hasMore)
            #expect(Set(firstPage.posts.map(\.id)).isDisjoint(with: secondPage.posts.map(\.id)))
        } catch {
            capturedError = error
        }

        for row in rows {
            _ = try? await client
                .from("posts")
                .delete()
                .eq("id", value: row.id.uuidString)
                .execute()
        }

        if let capturedError { throw capturedError }
    }

    @Test("새 커뮤니티 게시물은 Realtime 변경 이벤트를 발생시킨다")
    func receivesRealtimeEventForNewPost() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else {
            return
        }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }

        let userID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let post = IntegrationPostInsert(
            id: UUID(),
            authorID: userID,
            caption: "Realtime integration \(UUID().uuidString)",
            visibility: "public",
            createdAt: .now
        )
        let events = try await SupabaseCommunityFeedRealtimeRepository.shared.events()
        let eventTask = Task { await receivesFirstEvent(from: events, timeout: .seconds(8)) }

        var capturedError: Error?
        var receivedEvent = false
        do {
            try await client.from("posts").insert(post).execute()
            receivedEvent = await eventTask.value
            #expect(receivedEvent)
        } catch {
            capturedError = error
        }

        eventTask.cancel()
        await SupabaseCommunityFeedRealtimeRepository.shared.stop()
        _ = try? await client
            .from("posts")
            .delete()
            .eq("id", value: post.id.uuidString)
            .execute()

        if let capturedError { throw capturedError }
    }

    @Test("마켓 매물과 private 이미지를 원격 Repository에서 복원한다")
    func readsMarketListingAndImagesFromRemoteRepository() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else {
            return
        }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }

        let userID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let listingID = UUID()
        let sourceGarmentID = UUID()
        let pixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        let galleryPath = "\(userID.uuidString)/\(listingID.uuidString)/gallery/0.png"
        let cutoutPath = "\(userID.uuidString)/\(listingID.uuidString)/verification/cutout.png"
        let marker = "Market repository integration \(UUID().uuidString)"

        try await client.from("market_listings").insert(IntegrationMarketListingInsert(
            id: listingID,
            sellerID: userID,
            sourcePrivateID: sourceGarmentID,
            title: marker,
            description: "서버 매물 상세",
            price: 50_000,
            brandSnapshot: "WEARy",
            categorySnapshot: GarmentCategory.outer.rawValue,
            sizeSnapshot: "M",
            colorHexSnapshot: "223344",
            condition: "like_new",
            meetingName: "성수역",
            meetingAddress: "서울 성동구",
            meetingLatitude: 37.5445,
            meetingLongitude: 127.0559
        )).execute()

        var capturedError: Error?
        do {
            try await client.storage.from("market-media").upload(
                galleryPath,
                data: pixelPNG,
                options: FileOptions(contentType: "image/png", upsert: false)
            )
            try await client.storage.from("market-media").upload(
                cutoutPath,
                data: pixelPNG,
                options: FileOptions(contentType: "image/png", upsert: false)
            )
            try await client.from("market_listing_media").insert(IntegrationMarketMediaInsert(
                listingID: listingID,
                storagePath: galleryPath,
                sortOrder: 0
            )).execute()
            try await client.from("market_listing_verifications").insert(
                IntegrationMarketVerificationInsert(
                    listingID: listingID,
                    sourcePrivateID: sourceGarmentID,
                    garmentNameSnapshot: "통합 테스트 코트",
                    purchasePrice: 120_000,
                    wearCount: 3,
                    cutoutStoragePath: cutoutPath,
                    isVisible: true
                )
            ).execute()
            try await client.from("market_listing_favorites").insert(
                IntegrationMarketFavoriteInsert(listingID: listingID, userID: userID)
            ).execute()
            try await client
                .from("market_listings")
                .update(IntegrationMarketPriceUpdate(price: 45_000))
                .eq("id", value: listingID.uuidString)
                .execute()

            let listings = try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
            var listing = try #require(listings.first { $0.id == listingID })
            #expect(listing.sellerID == userID)
            #expect(listing.title == marker)
            #expect(listing.price == 45_000)
            #expect(listing.previousPrice == 50_000)
            #expect(listing.condition == .likeNew)
            #expect(listing.status == .active)
            #expect(listing.isLiked)
            #expect(listing.isOwnedByCurrentUser)
            #expect(listing.galleryImages == [pixelPNG])
            #expect(listing.showsWardrobeVerification)

            try await SupabaseMarketInteractionRepository.shared.setFavorite(
                listingID: listingID,
                isFavorite: true
            )
            listing = try #require(
                try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
                    .first { $0.id == listingID }
            )
            #expect(listing.isLiked)
            try await SupabaseMarketInteractionRepository.shared.setFavorite(
                listingID: listingID,
                isFavorite: false
            )
            listing = try #require(
                try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
                    .first { $0.id == listingID }
            )
            #expect(!listing.isLiked)
            #expect(listing.sourceGarmentID == sourceGarmentID)
            #expect(listing.garmentCutoutImageDataSnapshot == pixelPNG)
            #expect(listing.verificationPurchasePrice == 120_000)
            #expect(listing.verificationWearCount == 3)
        } catch {
            capturedError = error
        }

        _ = try? await client.storage.from("market-media").remove(paths: [galleryPath, cutoutPath])
        _ = try? await client
            .from("market_listings")
            .delete()
            .eq("id", value: listingID.uuidString)
            .execute()

        if let capturedError { throw capturedError }
    }

    @Test("마켓 관심 변경은 Realtime 이벤트를 발생시킨다")
    func receivesRealtimeEventForMarketFavorite() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }
        let marker = "Market realtime integration \(UUID().uuidString)"
        let repository = SupabaseMarketListingMutationRepository.shared
        let listingID = try await repository.create(MarketListingMutationDraft(
            sourceGarmentID: nil, title: marker, detailText: "Realtime 검증", price: 10_000,
            brand: "WEARy", categoryRaw: GarmentCategory.top.rawValue, size: "M",
            colorHex: "778899", condition: .excellent, status: .active,
            meetingPlace: "", meetingAddress: "", meetingLatitude: nil, meetingLongitude: nil,
            galleryImages: [], showsWardrobeVerification: false, garmentName: nil,
            cutoutImageData: nil, purchasePrice: nil, lastWornAt: nil, wearCount: nil
        ))
        var capturedError: Error?

        do {
            let events = try await SupabaseMarketRealtimeRepository.shared.events()
            try await SupabaseMarketInteractionRepository.shared.setFavorite(
                listingID: listingID,
                isFavorite: true
            )
            #expect(await receivesFirstEvent(from: events, timeout: .seconds(5)))
        } catch {
            capturedError = error
        }

        await SupabaseMarketRealtimeRepository.shared.stop()
        _ = try? await SupabaseMarketInteractionRepository.shared.setFavorite(
            listingID: listingID,
            isFavorite: false
        )
        _ = try? await repository.delete(listingID: listingID)
        _ = try? await client.from("market_listings").delete()
            .eq("id", value: listingID.uuidString).execute()
        if let capturedError { throw capturedError }
    }

    @Test("마켓 매물을 생성하고 수정·판매완료·삭제한다")
    func mutatesMarketListingThroughRemoteRepository() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }
        let pixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        let sourceID = UUID()
        let marker = "Market mutation integration \(UUID().uuidString)"
        let repository = SupabaseMarketListingMutationRepository.shared
        let createDraft = MarketListingMutationDraft(
            sourceGarmentID: sourceID, title: marker, detailText: "생성 상세", price: 50_000,
            brand: "WEARy", categoryRaw: GarmentCategory.outer.rawValue, size: "M",
            colorHex: "334455", condition: .excellent, status: .active,
            meetingPlace: "성수역", meetingAddress: "서울 성동구",
            meetingLatitude: 37.5445, meetingLongitude: 127.0559,
            galleryImages: [pixelPNG], showsWardrobeVerification: true,
            garmentName: "통합 재킷", cutoutImageData: pixelPNG,
            purchasePrice: 120_000, lastWornAt: nil, wearCount: 2
        )
        let listingID = try await repository.create(createDraft)
        var capturedError: Error?

        do {
            var listing = try #require(
                try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
                    .first { $0.id == listingID }
            )
            #expect(listing.title == marker)
            #expect(listing.galleryImages == [pixelPNG])
            #expect(listing.showsWardrobeVerification)

            let updateDraft = MarketListingMutationDraft(
                sourceGarmentID: sourceID, title: marker + " 수정", detailText: "수정 상세",
                price: 42_000, brand: "WEARy", categoryRaw: GarmentCategory.outer.rawValue,
                size: "M", colorHex: "334455", condition: .likeNew, status: .reserved,
                meetingPlace: "서울숲", meetingAddress: "서울 성동구 서울숲",
                meetingLatitude: 37.5443, meetingLongitude: 127.0374,
                galleryImages: [pixelPNG, pixelPNG], showsWardrobeVerification: false,
                garmentName: "통합 재킷", cutoutImageData: pixelPNG,
                purchasePrice: 120_000, lastWornAt: nil, wearCount: 2
            )
            try await repository.update(listingID: listingID, draft: updateDraft)
            listing = try #require(
                try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
                    .first { $0.id == listingID }
            )
            #expect(listing.title == marker + " 수정")
            #expect(listing.price == 42_000)
            #expect(listing.previousPrice == 50_000)
            #expect(listing.status == .reserved)
            #expect(listing.galleryImages.count == 2)
            #expect(!listing.showsWardrobeVerification)

            try await repository.updateStatus(listingID: listingID, status: .sold)
            listing = try #require(
                try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
                    .first { $0.id == listingID }
            )
            #expect(listing.status == .sold)

            try await repository.delete(listingID: listingID)
            let remaining = try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
            #expect(!remaining.contains { $0.id == listingID })
        } catch {
            capturedError = error
        }

        _ = try? await repository.delete(listingID: listingID)
        _ = try? await client.from("market_listings").delete()
            .eq("id", value: listingID.uuidString).execute()
        if let capturedError { throw capturedError }
    }

    @Test("구매자와 판매자가 매물 채팅을 주고받는다")
    func exchangesMarketChatMessages() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        guard SupabaseService.client != nil else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }
        let configuration = try supabaseConfiguration()
        let seller = try await createAnonymousSession(configuration: configuration)
        let intruder = try await createAnonymousSession(configuration: configuration)
        let buyerID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let listingID = UUID()
        let marker = "Market chat integration \(UUID().uuidString)"

        try await restRequest(
            method: "POST",
            path: "/rest/v1/market_listings",
            configuration: configuration,
            token: seller.token,
            body: [
                "id": listingID.uuidString,
                "seller_id": seller.userID.uuidString,
                "title": marker,
                "description": "채팅 통합 검증",
                "price": 30_000,
                "brand_snapshot": "WEARy",
                "category_snapshot": GarmentCategory.top.rawValue,
                "size_snapshot": "M",
                "color_hex_snapshot": "8899AA",
                "condition": "excellent",
                "status": "active",
            ]
        )

        let chat = SupabaseMarketChatRepository.shared
        var capturedError: Error?
        do {
            #expect(try await chat.findBuyerConversation(listingID: listingID) == nil)
            let conversationID = try await chat.getOrCreateBuyerConversation(listingID: listingID)
            #expect(try await chat.getOrCreateBuyerConversation(listingID: listingID) == conversationID)

            let buyerMessage = "구매자 메시지 \(UUID().uuidString)"
            try await chat.sendMessage(conversationID: conversationID, body: buyerMessage)
            var messages = try await chat.fetchMessages(conversationID: conversationID)
            #expect(messages.count == 1)
            #expect(messages.first?.senderID == buyerID)
            #expect(messages.first?.body == buyerMessage)

            let sellerConversationData = try await restRequest(
                method: "GET",
                path: "/rest/v1/market_conversations?listing_id=eq.\(listingID.uuidString)&select=id",
                configuration: configuration,
                token: seller.token
            )
            let sellerConversations = try JSONSerialization.jsonObject(with: sellerConversationData) as? [[String: Any]]
            #expect(sellerConversations?.count == 1)

            let hiddenConversationData = try await restRequest(
                method: "GET",
                path: "/rest/v1/market_conversations?id=eq.\(conversationID.uuidString)&select=id",
                configuration: configuration,
                token: intruder.token
            )
            let hiddenConversations = try JSONSerialization.jsonObject(with: hiddenConversationData) as? [[String: Any]]
            #expect(hiddenConversations?.isEmpty == true)

            var intruderMessageWasRejected = false
            do {
                try await restRequest(
                    method: "POST",
                    path: "/rest/v1/market_messages",
                    configuration: configuration,
                    token: intruder.token,
                    body: [
                        "conversation_id": conversationID.uuidString,
                        "sender_id": intruder.userID.uuidString,
                        "body": "접근하면 안 되는 메시지",
                    ]
                )
            } catch {
                intruderMessageWasRejected = true
            }
            #expect(intruderMessageWasRejected)

            let events = try await SupabaseMarketMessageRealtimeRepository.shared.events()
            let sellerMessage = "판매자 답장 \(UUID().uuidString)"
            try await restRequest(
                method: "POST",
                path: "/rest/v1/market_messages",
                configuration: configuration,
                token: seller.token,
                body: [
                    "conversation_id": conversationID.uuidString,
                    "sender_id": seller.userID.uuidString,
                    "body": sellerMessage,
                ]
            )
            #expect(await receivesFirstEvent(from: events, timeout: .seconds(5)))

            messages = try await chat.fetchMessages(conversationID: conversationID)
            #expect(messages.count == 2)
            #expect(messages.last?.senderID == seller.userID)
            #expect(messages.last?.body == sellerMessage)

            try await SupabaseContentSafetyRepository.shared.setBlocked(
                userID: seller.userID,
                isBlocked: true
            )
            #expect(
                try await chat.fetchWriteStatus(
                    listingID: listingID,
                    conversationID: conversationID
                ) == .blockedBySelf
            )

            var buyerMessageAfterBlockWasRejected = false
            do {
                try await chat.sendMessage(
                    conversationID: conversationID,
                    body: "차단 후 전송되면 안 되는 구매자 메시지"
                )
            } catch {
                buyerMessageAfterBlockWasRejected = true
            }
            #expect(buyerMessageAfterBlockWasRejected)

            let sellerStatusData = try await restRequest(
                method: "POST",
                path: "/rest/v1/rpc/get_market_chat_write_status",
                configuration: configuration,
                token: seller.token,
                body: [
                    "p_listing_id": listingID.uuidString,
                    "p_conversation_id": conversationID.uuidString,
                ]
            )
            #expect(try JSONDecoder().decode(String.self, from: sellerStatusData) == "blocked_by_counterpart")

            var sellerMessageAfterBlockWasRejected = false
            do {
                try await restRequest(
                    method: "POST",
                    path: "/rest/v1/market_messages",
                    configuration: configuration,
                    token: seller.token,
                    body: [
                        "conversation_id": conversationID.uuidString,
                        "sender_id": seller.userID.uuidString,
                        "body": "차단 후 전송되면 안 되는 판매자 메시지",
                    ]
                )
            } catch {
                sellerMessageAfterBlockWasRejected = true
            }
            #expect(sellerMessageAfterBlockWasRejected)

            messages = try await chat.fetchMessages(conversationID: conversationID)
            #expect(messages.count == 2)

            try await SupabaseContentSafetyRepository.shared.setBlocked(
                userID: seller.userID,
                isBlocked: false
            )
            #expect(
                try await chat.fetchWriteStatus(
                    listingID: listingID,
                    conversationID: conversationID
                ) == .allowed
            )
        } catch {
            capturedError = error
        }

        await SupabaseMarketMessageRealtimeRepository.shared.stop()
        _ = try? await SupabaseContentSafetyRepository.shared.setBlocked(
            userID: seller.userID,
            isBlocked: false
        )
        _ = try? await restRequest(
            method: "DELETE",
            path: "/rest/v1/market_listings?id=eq.\(listingID.uuidString)",
            configuration: configuration,
            token: seller.token
        )
        if let capturedError { throw capturedError }
    }

    @Test("두 사용자가 피드부터 마켓 채팅까지 하나의 실제 흐름을 공유한다")
    func completesTwoUserCommunityAndMarketJourney() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }

        let configuration = try supabaseConfiguration()
        let seller = try await createAnonymousSession(configuration: configuration)
        let buyerID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let postID = UUID()
        let listingID = UUID()
        let marker = UUID().uuidString
        let commentBody = "친구 B 댓글 \(marker)"
        let buyerMessage = "친구 B 구매 문의 \(marker)"
        let sellerReply = "친구 A 답장 \(marker)"

        try await restRequest(
            method: "POST",
            path: "/rest/v1/posts",
            configuration: configuration,
            token: seller.token,
            body: [
                "id": postID.uuidString,
                "author_id": seller.userID.uuidString,
                "caption": "친구 A 스타일 \(marker)",
                "visibility": "public",
            ]
        )
        try await restRequest(
            method: "POST",
            path: "/rest/v1/market_listings",
            configuration: configuration,
            token: seller.token,
            body: [
                "id": listingID.uuidString,
                "seller_id": seller.userID.uuidString,
                "title": "친구 A 매물 \(marker)",
                "description": "2인 전체 흐름 검증",
                "price": 25_000,
                "brand_snapshot": "WEARy",
                "category_snapshot": GarmentCategory.outer.rawValue,
                "size_snapshot": "M",
                "color_hex_snapshot": "667788",
                "condition": "excellent",
                "status": "active",
            ]
        )

        let interactions = SupabaseCommunityInteractionRepository.shared
        let chat = SupabaseMarketChatRepository.shared
        var capturedError: Error?
        do {
            let buyerFeed = try await SupabaseCommunityFeedRepository.shared.fetchFeed(limit: 100)
            #expect(buyerFeed.contains { $0.id == postID && $0.authorID == seller.userID })
            let buyerMarket = try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
            #expect(buyerMarket.contains { $0.id == listingID && $0.sellerID == seller.userID })

            try await interactions.setLike(postID: postID, isLiked: true)
            try await interactions.addComment(postID: postID, body: commentBody)
            try await interactions.setFollowing(authorID: seller.userID, isFollowing: true)

            let sellerComments = try await restRequest(
                method: "GET",
                path: "/rest/v1/comments?post_id=eq.\(postID.uuidString)&author_id=eq.\(buyerID.uuidString)&select=body",
                configuration: configuration,
                token: seller.token
            )
            let commentRows = try JSONSerialization.jsonObject(with: sellerComments) as? [[String: Any]]
            #expect(commentRows?.contains { $0["body"] as? String == commentBody } == true)

            let sellerFollowers = try await restRequest(
                method: "GET",
                path: "/rest/v1/follows?following_id=eq.\(seller.userID.uuidString)&follower_id=eq.\(buyerID.uuidString)&select=follower_id",
                configuration: configuration,
                token: seller.token
            )
            let followerRows = try JSONSerialization.jsonObject(with: sellerFollowers) as? [[String: Any]]
            #expect(followerRows?.count == 1)

            let conversationID = try await chat.getOrCreateBuyerConversation(listingID: listingID)
            try await chat.sendMessage(conversationID: conversationID, body: buyerMessage)

            let sellerMessages = try await restRequest(
                method: "GET",
                path: "/rest/v1/market_messages?conversation_id=eq.\(conversationID.uuidString)&select=body,sender_id&order=created_at.asc",
                configuration: configuration,
                token: seller.token
            )
            let messageRows = try JSONSerialization.jsonObject(with: sellerMessages) as? [[String: Any]]
            #expect(messageRows?.contains { $0["body"] as? String == buyerMessage } == true)

            try await restRequest(
                method: "POST",
                path: "/rest/v1/market_messages",
                configuration: configuration,
                token: seller.token,
                body: [
                    "conversation_id": conversationID.uuidString,
                    "sender_id": seller.userID.uuidString,
                    "body": sellerReply,
                ]
            )
            let buyerMessages = try await chat.fetchMessages(conversationID: conversationID)
            #expect(buyerMessages.contains { $0.senderID == seller.userID && $0.body == sellerReply })
        } catch {
            capturedError = error
        }

        _ = try? await interactions.setLike(postID: postID, isLiked: false)
        _ = try? await interactions.setFollowing(authorID: seller.userID, isFollowing: false)
        _ = try? await client.from("comments").delete()
            .eq("post_id", value: postID.uuidString)
            .eq("author_id", value: buyerID.uuidString).execute()
        _ = try? await restRequest(
            method: "DELETE",
            path: "/rest/v1/posts?id=eq.\(postID.uuidString)",
            configuration: configuration,
            token: seller.token
        )
        _ = try? await restRequest(
            method: "DELETE",
            path: "/rest/v1/market_listings?id=eq.\(listingID.uuidString)",
            configuration: configuration,
            token: seller.token
        )

        if let capturedError { throw capturedError }
    }

    @Test("신고와 차단은 사용자별로 보호되고 콘텐츠를 숨긴다")
    func reportsAndBlocksRemoteContent() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        guard let client = SupabaseService.client else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }
        let configuration = try supabaseConfiguration()
        let targetUser = try await createAnonymousSession(configuration: configuration)
        let postID = UUID()
        let listingID = UUID()
        let marker = "Safety integration \(UUID().uuidString)"

        try await restRequest(
            method: "POST",
            path: "/rest/v1/posts",
            configuration: configuration,
            token: targetUser.token,
            body: [
                "id": postID.uuidString,
                "author_id": targetUser.userID.uuidString,
                "caption": marker,
                "visibility": "public",
            ]
        )
        try await restRequest(
            method: "POST",
            path: "/rest/v1/market_listings",
            configuration: configuration,
            token: targetUser.token,
            body: [
                "id": listingID.uuidString,
                "seller_id": targetUser.userID.uuidString,
                "title": marker,
                "description": "안전 기능 검증",
                "price": 20_000,
                "brand_snapshot": "WEARy",
                "category_snapshot": GarmentCategory.top.rawValue,
                "size_snapshot": "M",
                "color_hex_snapshot": "998877",
                "condition": "excellent",
                "status": "active",
            ]
        )

        let safety = SupabaseContentSafetyRepository.shared
        var capturedError: Error?
        do {
            try await safety.submitReport(
                target: .post,
                targetID: postID,
                reason: .inappropriate,
                details: "통합 테스트 신고"
            )
            try await safety.submitReport(
                target: .post,
                targetID: postID,
                reason: .inappropriate,
                details: "중복 신고"
            )
            let reports: [IntegrationReportReference] = try await client
                .from("content_reports")
                .select("id")
                .eq("target_type", value: "post")
                .eq("target_id", value: postID.uuidString)
                .execute()
                .value
            #expect(reports.count == 1)

            try await safety.setBlocked(userID: targetUser.userID, isBlocked: true)
            #expect(try await safety.fetchBlockedUserIDs().contains(targetUser.userID))
            #expect(try await safety.fetchBlockedUsers().contains { $0.id == targetUser.userID })

            let feed = try await SupabaseCommunityFeedRepository.shared.fetchFeed(limit: 100)
            #expect(!feed.contains { $0.id == postID })
            let market = try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
            #expect(!market.contains { $0.id == listingID })

            let hiddenReportsData = try await restRequest(
                method: "GET",
                path: "/rest/v1/content_reports?target_id=eq.\(postID.uuidString)&select=id",
                configuration: configuration,
                token: targetUser.token
            )
            let hiddenReports = try JSONSerialization.jsonObject(with: hiddenReportsData) as? [[String: Any]]
            #expect(hiddenReports?.isEmpty == true)

            try await safety.setBlocked(userID: targetUser.userID, isBlocked: false)
            #expect(!(try await safety.fetchBlockedUserIDs()).contains(targetUser.userID))
            let restoredFeed = try await SupabaseCommunityFeedRepository.shared.fetchFeed(limit: 100)
            #expect(restoredFeed.contains { $0.id == postID })
            let restoredMarket = try await SupabaseMarketListingRepository.shared.fetchListings(limit: 100)
            #expect(restoredMarket.contains { $0.id == listingID })
        } catch {
            capturedError = error
        }

        _ = try? await safety.setBlocked(userID: targetUser.userID, isBlocked: false)
        _ = try? await safety.removeReport(target: .post, targetID: postID)
        _ = try? await restRequest(
            method: "DELETE",
            path: "/rest/v1/posts?id=eq.\(postID.uuidString)",
            configuration: configuration,
            token: targetUser.token
        )
        _ = try? await restRequest(
            method: "DELETE",
            path: "/rest/v1/market_listings?id=eq.\(listingID.uuidString)",
            configuration: configuration,
            token: targetUser.token
        )
        if let capturedError { throw capturedError }
    }

    @Test("사용자는 자신의 계정과 연결 데이터를 삭제할 수 있다")
    func deletesOnlyCallingUserAccount() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        guard SupabaseService.client != nil else {
            Issue.record("Supabase 로컬 설정이 필요합니다")
            return
        }
        let configuration = try supabaseConfiguration()
        let disposableUser = try await createAnonymousSession(configuration: configuration)
        let currentUserID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let postID = UUID()

        try await restRequest(
            method: "POST",
            path: "/rest/v1/posts",
            configuration: configuration,
            token: disposableUser.token,
            body: [
                "id": postID.uuidString,
                "author_id": disposableUser.userID.uuidString,
                "caption": "Account deletion integration",
                "visibility": "public",
            ]
        )
        try await restRequest(
            method: "POST",
            path: "/rest/v1/rpc/delete_current_user",
            configuration: configuration,
            token: disposableUser.token,
            body: [:]
        )

        let deletedProfileData = try await restRequest(
            method: "GET",
            path: "/rest/v1/profiles?id=eq.\(disposableUser.userID.uuidString)&select=id",
            configuration: configuration,
            token: disposableUser.token
        )
        let deletedProfiles = try JSONSerialization.jsonObject(with: deletedProfileData) as? [[String: Any]]
        #expect(deletedProfiles?.isEmpty == true)

        let deletedPostData = try await restRequest(
            method: "GET",
            path: "/rest/v1/posts?id=eq.\(postID.uuidString)&select=id",
            configuration: configuration,
            token: disposableUser.token
        )
        let deletedPosts = try JSONSerialization.jsonObject(with: deletedPostData) as? [[String: Any]]
        #expect(deletedPosts?.isEmpty == true)
        #expect(try await SupabaseSessionManager.shared.authenticatedUserID() == currentUserID)
    }

    @Test("일반 사용자는 운영자 신고 도구에 접근할 수 없다")
    func rejectsModerationAccessForRegularUser() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        let configuration = try supabaseConfiguration()
        let regularUser = try await createAnonymousSession(configuration: configuration)

        let accessData = try await restRequest(
            method: "POST",
            path: "/rest/v1/rpc/is_content_moderator",
            configuration: configuration,
            token: regularUser.token,
            body: [:]
        )
        #expect(try JSONDecoder().decode(Bool.self, from: accessData) == false)

        var listWasDenied = false
        do {
            _ = try await restRequest(
                method: "POST",
                path: "/rest/v1/rpc/fetch_moderation_reports",
                configuration: configuration,
                token: regularUser.token,
                body: ["p_limit": 10]
            )
        } catch {
            listWasDenied = true
        }
        #expect(listWasDenied)

        var reviewWasDenied = false
        do {
            _ = try await restRequest(
                method: "POST",
                path: "/rest/v1/rpc/review_content_report",
                configuration: configuration,
                token: regularUser.token,
                body: [
                    "p_report_id": UUID().uuidString,
                    "p_status": "reviewing",
                    "p_note": "",
                ]
            )
        } catch {
            reviewWasDenied = true
        }
        #expect(reviewWasDenied)

        _ = try? await restRequest(
            method: "POST",
            path: "/rest/v1/rpc/delete_current_user",
            configuration: configuration,
            token: regularUser.token,
            body: [:]
        )
    }

    @Test("계정 제재와 이의 제기는 사용자 소유권과 운영자 권한을 보호한다")
    func protectsAccountSanctionsAndAppeals() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        let configuration = try supabaseConfiguration()
        let regularUser = try await createAnonymousSession(configuration: configuration)

        let visibleData = try await restRequest(
            method: "GET",
            path: "/rest/v1/account_sanctions?select=id,user_id",
            configuration: configuration,
            token: regularUser.token
        )
        let visibleRows = try JSONSerialization.jsonObject(with: visibleData) as? [[String: Any]]
        #expect(visibleRows?.isEmpty == true)

        let writeAccessData = try await restRequest(
            method: "POST",
            path: "/rest/v1/rpc/can_current_user_write_shared_content",
            configuration: configuration,
            token: regularUser.token,
            body: [:]
        )
        #expect(try JSONDecoder().decode(Bool.self, from: writeAccessData))

        var directInsertDenied = false
        do {
            _ = try await restRequest(
                method: "POST",
                path: "/rest/v1/account_sanctions",
                configuration: configuration,
                token: regularUser.token,
                body: [
                    "user_id": regularUser.userID.uuidString,
                    "kind": "warning",
                    "reason": "위조 제재",
                ]
            )
        } catch { directInsertDenied = true }
        #expect(directInsertDenied)

        var moderatorRPCDenied = false
        do {
            _ = try await restRequest(
                method: "POST",
                path: "/rest/v1/rpc/create_account_sanction",
                configuration: configuration,
                token: regularUser.token,
                body: [
                    "p_user_id": regularUser.userID.uuidString,
                    "p_kind": "warning",
                    "p_reason": "위조 제재",
                ]
            )
        } catch { moderatorRPCDenied = true }
        #expect(moderatorRPCDenied)

        var foreignAppealDenied = false
        do {
            _ = try await restRequest(
                method: "POST",
                path: "/rest/v1/rpc/submit_account_sanction_appeal",
                configuration: configuration,
                token: regularUser.token,
                body: [
                    "p_sanction_id": UUID().uuidString,
                    "p_body": "본인 소유가 아닌 제재에는 이의 제기할 수 없습니다.",
                ]
            )
        } catch { foreignAppealDenied = true }
        #expect(foreignAppealDenied)

        for request in [
            ("/rest/v1/rpc/fetch_moderation_appeals", ["p_limit": 10] as [String: Any]),
            ("/rest/v1/rpc/action_user_report", [
                "p_report_id": UUID().uuidString,
                "p_kind": "warning",
                "p_reason": "권한 없는 제재",
            ] as [String: Any]),
            ("/rest/v1/rpc/review_account_sanction_appeal", [
                "p_appeal_id": UUID().uuidString,
                "p_status": "accepted",
                "p_note": "권한 없는 심사",
            ] as [String: Any]),
        ] {
            var staffOperationDenied = false
            do {
                _ = try await restRequest(
                    method: "POST",
                    path: request.0,
                    configuration: configuration,
                    token: regularUser.token,
                    body: request.1
                )
            } catch { staffOperationDenied = true }
            #expect(staffOperationDenied)
        }

        _ = try? await restRequest(
            method: "POST",
            path: "/rest/v1/rpc/delete_current_user",
            configuration: configuration,
            token: regularUser.token,
            body: [:]
        )
    }

    @Test("사용자는 운영 알림을 위조할 수 없고 본인 알림만 읽는다")
    func protectsUserNotices() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" else { return }
        let configuration = try supabaseConfiguration()
        let regularUser = try await createAnonymousSession(configuration: configuration)

        let noticesData = try await restRequest(
            method: "GET",
            path: "/rest/v1/user_notices?select=id,recipient_id",
            configuration: configuration,
            token: regularUser.token
        )
        let notices = try JSONSerialization.jsonObject(with: noticesData) as? [[String: Any]]
        #expect(notices?.isEmpty == true)

        var insertWasDenied = false
        do {
            _ = try await restRequest(
                method: "POST",
                path: "/rest/v1/user_notices",
                configuration: configuration,
                token: regularUser.token,
                body: [
                    "recipient_id": regularUser.userID.uuidString,
                    "kind": "report_result",
                    "title": "위조 알림",
                    "body": "사용자가 직접 만들 수 없어야 합니다.",
                ]
            )
        } catch {
            insertWasDenied = true
        }
        #expect(insertWasDenied)

        _ = try await restRequest(
            method: "POST",
            path: "/rest/v1/rpc/mark_user_notice_read",
            configuration: configuration,
            token: regularUser.token,
            body: ["p_notice_id": UUID().uuidString]
        )

        _ = try? await restRequest(
            method: "POST",
            path: "/rest/v1/rpc/delete_current_user",
            configuration: configuration,
            token: regularUser.token,
            body: [:]
        )
    }

    private func receivesFirstEvent(
        from events: AsyncStream<Void>,
        timeout: Duration
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in events { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }
    }

    private func supabaseConfiguration() throws -> TestSupabaseConfiguration {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
            !key.isEmpty
        else {
            throw TestIntegrationError.missingConfiguration
        }
        return TestSupabaseConfiguration(url: url, publishableKey: key)
    }

    private func createAnonymousSession(
        configuration: TestSupabaseConfiguration
    ) async throws -> TestAnonymousSession {
        let data = try await restRequest(
            method: "POST",
            path: "/auth/v1/signup",
            configuration: configuration,
            token: configuration.publishableKey,
            body: [:]
        )
        return try JSONDecoder().decode(TestAnonymousSession.self, from: data)
    }

    @discardableResult
    private func restRequest(
        method: String,
        path: String,
        configuration: TestSupabaseConfiguration,
        token: String,
        body: [String: Any]? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: configuration.url) else {
            throw TestIntegrationError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TestIntegrationError.requestFailed
        }
        return data
    }
}

private struct IntegrationAccountAvailabilityRequest: Encodable, Sendable {
    let action: String
    let email: String
    let handle: String
    let nickname: String
}

private struct IntegrationAccountAvailability: Decodable, Sendable {
    let emailAvailable: Bool
    let handleAvailable: Bool
    let nicknameAvailable: Bool
}

private struct TestSupabaseConfiguration: Sendable {
    let url: URL
    let publishableKey: String
}

private struct TestAnonymousSession: Decodable, Sendable {
    let token: String
    let user: TestAnonymousUser

    var userID: UUID { user.id }

    enum CodingKeys: String, CodingKey {
        case token = "access_token"
        case user
    }
}

private struct TestAnonymousUser: Decodable, Sendable {
    let id: UUID
}

private struct IntegrationPostInsert: Encodable, Sendable {
    let id: UUID
    let authorID: UUID
    let caption: String
    let visibility: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, caption, visibility
        case authorID = "author_id"
        case createdAt = "created_at"
    }
}

private struct IntegrationMarketListingInsert: Encodable, Sendable {
    let id: UUID
    let sellerID: UUID
    let sourcePrivateID: UUID
    let title: String
    let description: String
    let price: Int
    let brandSnapshot: String
    let categorySnapshot: String
    let sizeSnapshot: String
    let colorHexSnapshot: String
    let condition: String
    let meetingName: String
    let meetingAddress: String
    let meetingLatitude: Double
    let meetingLongitude: Double

    enum CodingKeys: String, CodingKey {
        case id, title, description, price, condition
        case sellerID = "seller_id"
        case sourcePrivateID = "source_private_id"
        case brandSnapshot = "brand_snapshot"
        case categorySnapshot = "category_snapshot"
        case sizeSnapshot = "size_snapshot"
        case colorHexSnapshot = "color_hex_snapshot"
        case meetingName = "meeting_name"
        case meetingAddress = "meeting_address"
        case meetingLatitude = "meeting_latitude"
        case meetingLongitude = "meeting_longitude"
    }
}

private struct IntegrationMarketMediaInsert: Encodable, Sendable {
    let listingID: UUID
    let storagePath: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case listingID = "listing_id"
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
    }
}

private struct IntegrationMarketVerificationInsert: Encodable, Sendable {
    let listingID: UUID
    let sourcePrivateID: UUID
    let garmentNameSnapshot: String
    let purchasePrice: Int
    let wearCount: Int
    let cutoutStoragePath: String
    let isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case listingID = "listing_id"
        case sourcePrivateID = "source_private_id"
        case garmentNameSnapshot = "garment_name_snapshot"
        case purchasePrice = "purchase_price"
        case wearCount = "wear_count"
        case cutoutStoragePath = "cutout_storage_path"
        case isVisible = "is_visible"
    }
}

private struct IntegrationMarketFavoriteInsert: Encodable, Sendable {
    let listingID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case listingID = "listing_id"
        case userID = "user_id"
    }
}

private struct IntegrationMarketPriceUpdate: Encodable, Sendable {
    let price: Int
}

private struct IntegrationReportReference: Decodable, Sendable {
    let id: UUID
}

private enum TestIntegrationError: Error {
    case missingConfiguration
    case invalidURL
    case requestFailed
}
