import Foundation
import Supabase

enum SignUpResult {
    case signedIn
    case emailConfirmationRequired
}

enum AccountGender: String, CaseIterable, Identifiable, Codable, Sendable {
    case female
    case male
    case nonbinary
    case undisclosed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: "여성"
        case .male: "남성"
        case .nonbinary: "논바이너리"
        case .undisclosed: "선택 안 함"
        }
    }
}

struct AccountProfile: Decodable, Sendable {
    let id: UUID
    let displayName: String
    let handle: String?
    let handleLocked: Bool
    let avatarInitials: String
    let accentHex: String
    let heightCM: Double?
    let weightKG: Double?
    let gender: AccountGender?
    let chestCM: Double?
    let waistCM: Double?
    let hipCM: Double?
    let inseamCM: Double?

    enum CodingKeys: String, CodingKey {
        case id, handle, gender
        case displayName = "display_name"
        case handleLocked = "handle_locked"
        case avatarInitials = "avatar_initials"
        case accentHex = "accent_hex"
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case chestCM = "chest_cm"
        case waistCM = "waist_cm"
        case hipCM = "hip_cm"
        case inseamCM = "inseam_cm"
    }

    init(publicProfile: PublicAccountProfile, measurements: PrivateProfileMeasurements?) {
        id = publicProfile.id
        displayName = publicProfile.displayName
        handle = publicProfile.handle
        handleLocked = publicProfile.handleLocked
        avatarInitials = publicProfile.avatarInitials
        accentHex = publicProfile.accentHex
        heightCM = measurements?.heightCM
        weightKG = measurements?.weightKG
        gender = measurements?.gender
        chestCM = measurements?.chestCM
        waistCM = measurements?.waistCM
        hipCM = measurements?.hipCM
        inseamCM = measurements?.inseamCM
    }
}

struct AccountProfileUpdate: Encodable, Sendable {
    let displayName: String
    let handle: String?
    let avatarInitials: String

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case avatarInitials = "avatar_initials"
    }
}

struct PublicAccountProfile: Decodable, Sendable {
    let id: UUID
    let displayName: String
    let handle: String?
    let handleLocked: Bool
    let avatarInitials: String
    let accentHex: String

    enum CodingKeys: String, CodingKey {
        case id, handle
        case displayName = "display_name"
        case handleLocked = "handle_locked"
        case avatarInitials = "avatar_initials"
        case accentHex = "accent_hex"
    }
}

struct PrivateProfileMeasurements: Codable, Sendable {
    let id: UUID
    let heightCM: Double?
    let weightKG: Double?
    let gender: AccountGender?
    let chestCM: Double?
    let waistCM: Double?
    let hipCM: Double?
    let inseamCM: Double?

    enum CodingKeys: String, CodingKey {
        case id, gender
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case chestCM = "chest_cm"
        case waistCM = "waist_cm"
        case hipCM = "hip_cm"
        case inseamCM = "inseam_cm"
    }
}

actor AccountProfileRepository {
    static let shared = AccountProfileRepository()

    func fetch(userID: UUID) async throws -> AccountProfile {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        async let publicProfile: PublicAccountProfile = client
            .from("profiles")
            .select("id,display_name,handle,handle_locked,avatar_initials,accent_hex")
            .eq("id", value: userID.uuidString)
            .single()
            .execute()
            .value
        async let measurements: [PrivateProfileMeasurements] = client
            .from("profile_measurements")
            .select()
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return try await AccountProfile(publicProfile: publicProfile, measurements: measurements.first)
    }

    func update(
        userID: UUID,
        profile: AccountProfileUpdate,
        measurements: PrivateProfileMeasurements
    ) async throws -> AccountProfile {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        try await client
            .from("profiles")
            .update(profile)
            .eq("id", value: userID.uuidString)
            .execute()
        try await client
            .from("profile_measurements")
            .upsert(measurements, onConflict: "id")
            .execute()
        return try await fetch(userID: userID)
    }
}

@MainActor
final class AuthenticationStore: ObservableObject {
    enum Phase {
        case loading
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var email: String?
    @Published private(set) var isPasswordAccount = false
    @Published var requiresPasswordUpdate = false

    private var observerTask: Task<Void, Never>?

    var displayName: String { profile?.displayName ?? "나의 WEARy" }
    var handle: String? { profile?.handle }

    deinit {
        observerTask?.cancel()
    }

    func bootstrap() async {
        guard let client = SupabaseService.client else {
            phase = .signedOut
            return
        }

        startObserving(client)
        if let session = try? await client.auth.session, !session.user.isAnonymous {
            await activate(session)
        } else {
            if client.auth.currentUser?.isAnonymous == true {
                try? await client.auth.signOut(scope: .local)
            }
            await SupabaseSessionManager.shared.update(userID: nil)
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async throws {
        let client = try configuredClient()
        try await discardAnonymousSession(using: client)
        phase = .loading
        do {
            let session = try await client.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password
            )
            await activate(session)
        } catch {
            phase = .signedOut
            throw error
        }
    }

    func signUp(email: String, password: String, handle: String, nickname: String) async throws -> SignUpResult {
        let client = try configuredClient()
        try await discardAnonymousSession(using: client)
        phase = .loading

        let normalizedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password,
                data: [
                    "handle": .string(normalizedHandle),
                    "display_name": .string(normalizedNickname),
                    "avatar_initials": .string(Self.initials(for: normalizedNickname)),
                ]
            )
            if let session = response.session {
                await activate(session)
                return .signedIn
            }
            phase = .signedOut
            return .emailConfirmationRequired
        } catch {
            phase = .signedOut
            throw error
        }
    }

    func signInWithOAuth(_ provider: Provider) async throws {
        let client = try configuredClient()
        try await discardAnonymousSession(using: client)
        phase = .loading
        do {
            let session = try await client.auth.signInWithOAuth(
                provider: provider,
                redirectTo: SupabaseService.authRedirectURL
            )
            await activate(session)
        } catch {
            phase = .signedOut
            throw error
        }
    }

    func sendPasswordReset(to email: String) async throws {
        let client = try configuredClient()
        try await client.auth.resetPasswordForEmail(
            email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            redirectTo: SupabaseService.authRedirectURL
        )
    }

    func updatePassword(_ password: String) async throws {
        let client = try configuredClient()
        guard isPasswordAccount else { throw AccountValidationError.oauthPassword }
        _ = try await client.auth.update(user: UserAttributes(password: password))
        requiresPasswordUpdate = false
    }

    func refreshProfile() async throws {
        guard let userID = SupabaseService.client?.auth.currentUser?.id else {
            throw SupabaseServiceError.authenticationRequired
        }
        profile = try await AccountProfileRepository.shared.fetch(userID: userID)
    }

    func signOut() async throws {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        try await client.auth.signOut()
        await clearSession()
    }

    func finishAccountDeletion() async {
        if let client = SupabaseService.client {
            try? await client.auth.signOut(scope: .local)
        }
        await clearSession()
    }

    private func configuredClient() throws -> SupabaseClient {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        return client
    }

    private func discardAnonymousSession(using client: SupabaseClient) async throws {
        if client.auth.currentUser?.isAnonymous == true {
            try await client.auth.signOut(scope: .local)
            await SupabaseSessionManager.shared.update(userID: nil)
        }
    }

    private func startObserving(_ client: SupabaseClient) {
        guard observerTask == nil else { return }
        observerTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                if event == .passwordRecovery {
                    self.requiresPasswordUpdate = true
                }
                if let session, !session.user.isAnonymous {
                    await self.activate(session)
                } else if event == .signedOut {
                    await self.clearSession()
                }
            }
        }
    }

    private func activate(_ session: Session) async {
        email = session.user.email
        isPasswordAccount = session.user.identities?.contains { $0.provider == "email" } == true
        await SupabaseSessionManager.shared.update(userID: session.user.id)
        profile = try? await AccountProfileRepository.shared.fetch(userID: session.user.id)
        phase = .signedIn
    }

    private func clearSession() async {
        email = nil
        profile = nil
        isPasswordAccount = false
        requiresPasswordUpdate = false
        await SupabaseSessionManager.shared.update(userID: nil)
        phase = .signedOut
    }

    static func initials(for name: String) -> String {
        let compact = name.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return "WY" }
        return String(compact.prefix(2)).uppercased()
    }
}

enum AccountValidationError: LocalizedError {
    case oauthPassword

    var errorDescription: String? {
        switch self {
        case .oauthPassword:
            "소셜 로그인 계정의 비밀번호는 해당 서비스에서 관리해 주세요."
        }
    }
}
