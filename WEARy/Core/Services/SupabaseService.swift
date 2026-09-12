import Foundation
import Supabase

enum SupabaseService {
    static let client: SupabaseClient? = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
            let url = URL(string: urlString),
            !key.isEmpty,
            key.hasPrefix("sb_publishable_")
        else {
            return nil
        }

        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}

actor SupabaseSessionManager {
    static let shared = SupabaseSessionManager()

    private(set) var userID: UUID?
    private(set) var lastErrorDescription: String?
    private var authenticationTask: Task<UUID, Error>?

    func bootstrap() async {
        do {
            _ = try await authenticatedUserID()
        } catch {
            lastErrorDescription = error.localizedDescription
#if DEBUG
            print("Supabase 익명 로그인 실패: \(error.localizedDescription)")
#endif
        }
    }

    func authenticatedUserID() async throws -> UUID {
        if let userID { return userID }
        if let authenticationTask { return try await authenticationTask.value }

        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }

        let task = Task<UUID, Error> {
            if let currentSession = try? await client.auth.session {
                return currentSession.user.id
            }

            return try await client.auth.signInAnonymously().user.id
        }
        authenticationTask = task

        do {
            let authenticatedID = try await task.value
            userID = authenticatedID
            lastErrorDescription = nil
            authenticationTask = nil
            return authenticatedID
        } catch {
            lastErrorDescription = error.localizedDescription
            authenticationTask = nil
            throw error
        }
    }
}

enum SupabaseServiceError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Supabase 설정을 찾을 수 없습니다."
        }
    }
}
