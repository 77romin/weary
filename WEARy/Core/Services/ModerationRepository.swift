import Foundation
import Supabase

enum ModerationReportStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case pending
    case reviewing
    case dismissed
    case actioned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: "검토 대기"
        case .reviewing: "검토 중"
        case .dismissed: "위반 없음"
        case .actioned: "조치 완료"
        }
    }
}

struct ModerationReportSnapshot: Identifiable, Decodable, Sendable {
    let id: UUID
    let reporterID: UUID
    let reporterName: String
    let reporterHandle: String
    let targetType: String
    let targetID: UUID
    let targetSummary: String
    let reason: String
    let details: String
    let status: ModerationReportStatus
    let moderatorNote: String
    let createdAt: Date
    let updatedAt: Date
    let reviewedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, reason, details
        case reporterID = "reporter_id"
        case reporterName = "reporter_name"
        case reporterHandle = "reporter_handle"
        case targetType = "target_type"
        case targetID = "target_id"
        case targetSummary = "target_summary"
        case status = "report_status"
        case moderatorNote = "moderator_note"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case reviewedAt = "reviewed_at"
    }
}

actor SupabaseModerationRepository {
    static let shared = SupabaseModerationRepository()

    func isCurrentUserModerator() async throws -> Bool {
        let client = try await authenticatedClient()
        let response: Bool = try await client
            .rpc("is_content_moderator")
            .execute()
            .value
        return response
    }

    func fetchReports(
        status: ModerationReportStatus?,
        limit: Int = 100
    ) async throws -> [ModerationReportSnapshot] {
        let client = try await authenticatedClient()
        return try await client
            .rpc(
                "fetch_moderation_reports",
                params: ModerationReportFetchParameters(
                    status: status?.rawValue,
                    limit: min(max(limit, 1), 200)
                )
            )
            .execute()
            .value
    }

    func review(
        reportID: UUID,
        status: ModerationReportStatus,
        note: String
    ) async throws {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedNote.count <= 1_000 else {
            throw ModerationError.noteTooLong
        }
        let client = try await authenticatedClient()
        try await client
            .rpc(
                "review_content_report",
                params: ModerationReportReviewParameters(
                    reportID: reportID,
                    status: status.rawValue,
                    note: normalizedNote
                )
            )
            .execute()
    }

    private func authenticatedClient() async throws -> SupabaseClient {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        _ = try await SupabaseSessionManager.shared.authenticatedUserID()
        return client
    }
}

private struct ModerationReportFetchParameters: Encodable, Sendable {
    let status: String?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case status = "p_status"
        case limit = "p_limit"
    }
}

private struct ModerationReportReviewParameters: Encodable, Sendable {
    let reportID: UUID
    let status: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case reportID = "p_report_id"
        case status = "p_status"
        case note = "p_note"
    }
}

enum ModerationError: LocalizedError {
    case noteTooLong

    var errorDescription: String? {
        switch self {
        case .noteTooLong:
            "운영 메모는 1,000자 이하로 입력해 주세요."
        }
    }
}

enum AccountSanctionKind: String, Decodable, Sendable {
    case warning
    case restriction
    case suspension

    var title: String {
        switch self {
        case .warning: "경고"
        case .restriction: "이용 제한"
        case .suspension: "계정 정지"
        }
    }
}

struct AccountSanctionSnapshot: Identifiable, Decodable, Sendable {
    let id: UUID
    let kind: AccountSanctionKind
    let reason: String
    let startsAt: Date
    let endsAt: Date?
    let liftedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, reason
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case liftedAt = "lifted_at"
        case createdAt = "created_at"
    }

    var isActive: Bool {
        liftedAt == nil && (endsAt == nil || endsAt! > .now)
    }
}

struct AccountSanctionAppealSnapshot: Identifiable, Decodable, Sendable {
    let id: UUID
    let sanctionID: UUID
    let body: String
    let status: String
    let moderatorNote: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body, status
        case sanctionID = "sanction_id"
        case moderatorNote = "moderator_note"
        case createdAt = "created_at"
    }
}

actor SupabaseAccountSanctionRepository {
    static let shared = SupabaseAccountSanctionRepository()

    func fetchMine() async throws -> ([AccountSanctionSnapshot], [AccountSanctionAppealSnapshot]) {
        guard let client = SupabaseService.client else { throw SupabaseServiceError.missingConfiguration }
        let userID = try await SupabaseSessionManager.shared.authenticatedUserID()
        async let sanctions: [AccountSanctionSnapshot] = client.from("account_sanctions")
            .select("id,kind,reason,starts_at,ends_at,lifted_at,created_at")
            .eq("user_id", value: userID.uuidString).order("created_at", ascending: false).execute().value
        async let appeals: [AccountSanctionAppealSnapshot] = client.from("account_sanction_appeals")
            .select("id,sanction_id,body,status,moderator_note,created_at")
            .eq("user_id", value: userID.uuidString).order("created_at", ascending: false).execute().value
        return try await (sanctions, appeals)
    }

    func submitAppeal(sanctionID: UUID, body: String) async throws {
        guard body.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 else {
            throw AccountSanctionError.appealTooShort
        }
        guard let client = SupabaseService.client else { throw SupabaseServiceError.missingConfiguration }
        try await client.rpc("submit_account_sanction_appeal", params: [
            "p_sanction_id": sanctionID.uuidString,
            "p_body": body.trimmingCharacters(in: .whitespacesAndNewlines),
        ]).execute()
    }
}

enum AccountSanctionError: LocalizedError {
    case appealTooShort
    var errorDescription: String? { "이의 제기 사유를 10자 이상 입력해 주세요." }
}
