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

    func bootstrap() async {
        guard let client = SupabaseService.client else {
            lastErrorDescription = "Supabase 설정을 찾을 수 없습니다."
            return
        }

        do {
            if let currentSession = try? await client.auth.session {
                userID = currentSession.user.id
                lastErrorDescription = nil
                return
            }

            let newSession = try await client.auth.signInAnonymously()
            userID = newSession.user.id
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
#if DEBUG
            print("Supabase 익명 로그인 실패: \(error.localizedDescription)")
#endif
        }
    }
}
