import Foundation
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

private enum TestIntegrationError: Error {
    case missingConfiguration
    case invalidURL
    case requestFailed
}
