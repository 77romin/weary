import Foundation
import Supabase

struct UserNoticeSnapshot: Identifiable, Decodable, Sendable {
    let id: UUID
    let kind: String
    let title: String
    let body: String
    var readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

actor SupabaseUserNoticeRepository {
    static let shared = SupabaseUserNoticeRepository()

    func fetchNotices(limit: Int = 50) async throws -> [UserNoticeSnapshot] {
        let (client, userID) = try await authenticatedContext()
        return try await client
            .from("user_notices")
            .select("id,kind,title,body,read_at,created_at")
            .eq("recipient_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(min(max(limit, 1), 100))
            .execute()
            .value
    }

    func markRead(noticeID: UUID) async throws {
        let (client, _) = try await authenticatedContext()
        try await client
            .rpc(
                "mark_user_notice_read",
                params: UserNoticeReadParameters(noticeID: noticeID)
            )
            .execute()
    }

    private func authenticatedContext() async throws -> (SupabaseClient, UUID) {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        return (client, try await SupabaseSessionManager.shared.authenticatedUserID())
    }
}

private struct UserNoticeReadParameters: Encodable, Sendable {
    let noticeID: UUID

    enum CodingKeys: String, CodingKey {
        case noticeID = "p_notice_id"
    }
}
