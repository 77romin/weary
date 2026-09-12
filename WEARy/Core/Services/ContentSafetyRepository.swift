import Foundation
import Supabase

enum ContentReportTarget: String, Sendable {
    case post
    case listing
    case message
    case user
}

enum ContentReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam
    case fraud
    case harassment
    case inappropriate
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: "스팸 또는 홍보"
        case .fraud: "사기 또는 허위 정보"
        case .harassment: "괴롭힘 또는 혐오 표현"
        case .inappropriate: "부적절한 콘텐츠"
        case .other: "기타"
        }
    }
}

struct BlockedUserSnapshot: Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let handle: String
    let initials: String
    let accentHex: String
}

actor SupabaseContentSafetyRepository {
    static let shared = SupabaseContentSafetyRepository()

    func submitReport(
        target: ContentReportTarget,
        targetID: UUID,
        reason: ContentReportReason,
        details: String = ""
    ) async throws {
        let (client, userID) = try await authenticatedContext()
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDetails.count <= 1_000 else { throw ContentSafetyError.detailsTooLong }

        try await client
            .from("content_reports")
            .upsert(
                ContentReportInsert(
                    reporterID: userID,
                    targetType: target.rawValue,
                    targetID: targetID,
                    reason: reason.rawValue,
                    details: trimmedDetails
                ),
                onConflict: "reporter_id,target_type,target_id",
                returning: .minimal,
                ignoreDuplicates: true
            )
            .execute()
    }

    func removeReport(target: ContentReportTarget, targetID: UUID) async throws {
        let (client, userID) = try await authenticatedContext()
        try await client
            .from("content_reports")
            .delete()
            .eq("reporter_id", value: userID.uuidString)
            .eq("target_type", value: target.rawValue)
            .eq("target_id", value: targetID.uuidString)
            .execute()
    }

    func setBlocked(userID blockedID: UUID, isBlocked: Bool) async throws {
        let (client, userID) = try await authenticatedContext()
        guard blockedID != userID else { throw ContentSafetyError.cannotBlockSelf }

        if isBlocked {
            try await client
                .from("user_blocks")
                .upsert(
                    UserBlockInsert(blockerID: userID, blockedID: blockedID),
                    onConflict: "blocker_id,blocked_id",
                    returning: .minimal,
                    ignoreDuplicates: true
                )
                .execute()
            _ = try? await client
                .from("follows")
                .delete()
                .eq("follower_id", value: userID.uuidString)
                .eq("following_id", value: blockedID.uuidString)
                .execute()
        } else {
            try await client
                .from("user_blocks")
                .delete()
                .eq("blocker_id", value: userID.uuidString)
                .eq("blocked_id", value: blockedID.uuidString)
                .execute()
        }
    }

    func fetchBlockedUserIDs() async throws -> Set<UUID> {
        let (client, userID) = try await authenticatedContext()
        let records: [RemoteUserBlock] = try await client
            .from("user_blocks")
            .select("blocked_id")
            .eq("blocker_id", value: userID.uuidString)
            .execute()
            .value
        return Set(records.map(\.blockedID))
    }

    func fetchBlockedUsers() async throws -> [BlockedUserSnapshot] {
        let (client, userID) = try await authenticatedContext()
        let records: [RemoteBlockedUser] = try await client
            .from("user_blocks")
            .select(
                "blocked:profiles!user_blocks_blocked_id_fkey(id,display_name,handle,avatar_initials,accent_hex)"
            )
            .eq("blocker_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return records.map(\.blocked.snapshot)
    }

    private func authenticatedContext() async throws -> (SupabaseClient, UUID) {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        return (client, try await SupabaseSessionManager.shared.authenticatedUserID())
    }
}

private struct ContentReportInsert: Encodable, Sendable {
    let reporterID: UUID
    let targetType: String
    let targetID: UUID
    let reason: String
    let details: String

    enum CodingKeys: String, CodingKey {
        case reason, details
        case reporterID = "reporter_id"
        case targetType = "target_type"
        case targetID = "target_id"
    }
}

private struct UserBlockInsert: Encodable, Sendable {
    let blockerID: UUID
    let blockedID: UUID

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
    }
}

private struct RemoteUserBlock: Decodable, Sendable {
    let blockedID: UUID

    enum CodingKeys: String, CodingKey {
        case blockedID = "blocked_id"
    }
}

private struct RemoteBlockedUser: Decodable, Sendable {
    let blocked: RemoteBlockedProfile
}

private struct RemoteBlockedProfile: Decodable, Sendable {
    let id: UUID
    let displayName: String
    let handle: String?
    let avatarInitials: String
    let accentHex: String

    var snapshot: BlockedUserSnapshot {
        BlockedUserSnapshot(
            id: id,
            displayName: displayName,
            handle: handle ?? "weary",
            initials: avatarInitials,
            accentHex: accentHex
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, handle
        case displayName = "display_name"
        case avatarInitials = "avatar_initials"
        case accentHex = "accent_hex"
    }
}

enum ContentSafetyError: LocalizedError {
    case cannotBlockSelf
    case detailsTooLong

    var errorDescription: String? {
        switch self {
        case .cannotBlockSelf: "본인을 차단할 수 없습니다."
        case .detailsTooLong: "신고 상세 내용은 1,000자 이하로 입력해 주세요."
        }
    }
}
