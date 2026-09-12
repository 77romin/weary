import Foundation
import Supabase
import Testing
@testable import WEARy

@Suite("Supabase 수동 통합 검증", .serialized)
struct SupabaseIntegrationTests {
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
            let listing = try #require(listings.first { $0.id == listingID })
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

private enum TestIntegrationError: Error {
    case missingConfiguration
    case invalidURL
    case requestFailed
}
