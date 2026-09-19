import Foundation
import Supabase

enum SupabaseService {
    static let authRedirectURL = URL(string: "weary://auth-callback")!

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

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(redirectToURL: authRedirectURL)
            )
        )
    }()
}

enum SupabaseStoragePath {
    static func resourceRoot(ownerID: UUID, resourceID: UUID) -> String {
        "\(component(ownerID))/\(component(resourceID))"
    }

    static func component(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}

enum SupabaseRealtimeSession {
    /// Auth state propagation inside supabase-swift is asynchronous. Resolve the
    /// current session and push its JWT before joining a channel so Realtime RLS
    /// never evaluates a newly signed-in user with the publishable key instead.
    static func prepare(_ client: SupabaseClient) async throws {
        let session = try await client.auth.session
        await client.realtimeV2.setAuth(session.accessToken)
    }
}

actor SupabaseSessionManager {
    static let shared = SupabaseSessionManager()

    private(set) var userID: UUID?
    func update(userID: UUID?) {
        self.userID = userID
    }

    func authenticatedUserID() async throws -> UUID {
        if let userID { return userID }

        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }

        if let session = try? await client.auth.session, !session.user.isAnonymous {
            userID = session.user.id
            return session.user.id
        }

#if DEBUG
        if ProcessInfo.processInfo.environment["RUN_SUPABASE_INTEGRATION"] == "1" {
            let testUser = try await client.auth.signInAnonymously().user.id
            userID = testUser
            return testUser
        }
#endif

        throw SupabaseServiceError.authenticationRequired
    }
}

enum SupabaseServiceError: LocalizedError {
    case missingConfiguration
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Supabase 설정을 찾을 수 없습니다."
        case .authenticationRequired:
            "로그인이 필요합니다."
        }
    }
}
