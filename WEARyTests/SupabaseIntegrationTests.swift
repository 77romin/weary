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
}
