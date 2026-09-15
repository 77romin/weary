import Foundation
import Supabase

enum SignUpResult {
    case signedIn
    case emailConfirmationRequired
}

struct AccountAvailability: Decodable, Sendable {
    let emailAvailable: Bool
    let handleAvailable: Bool
    let nicknameAvailable: Bool

    var allAvailable: Bool {
        emailAvailable && handleAvailable && nicknameAvailable
    }
}

private struct AccountAuthRequest: Encodable, Sendable {
    let action: String
    let identifier: String?
    let password: String?
    let email: String?
    let handle: String?
    let nickname: String?
}

private struct AccountAuthSession: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
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
    @Published private(set) var userID: UUID?
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var email: String?
    @Published private(set) var isPasswordAccount = false
    @Published var requiresPasswordUpdate = false
    @Published var accountNotice: String?
    @Published private(set) var activeAccountSanction: AccountSanctionSnapshot?

    private var observerTask: Task<Void, Never>?
    private let pendingConfirmationKey = "auth.pendingEmailConfirmation"
    private let pendingHandleRecoveryKey = "auth.pendingHandleRecovery"
    private let pendingPasswordRecoveryKey = "auth.pendingPasswordRecovery"

    var displayName: String { profile?.displayName ?? "나의 WEARy" }
    var handle: String? { profile?.handle }
    var isSocialWriteRestricted: Bool { activeAccountSanction != nil }

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

    func signIn(identifier: String, password: String) async throws {
        let client = try configuredClient()
        try await discardAnonymousSession(using: client)
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let session: Session
            if normalizedIdentifier.contains("@") {
                session = try await client.auth.signIn(
                    email: normalizedIdentifier,
                    password: password
                )
            } else {
                let response: AccountAuthSession = try await client.functions.invoke(
                    "account-auth",
                    options: FunctionInvokeOptions(body: AccountAuthRequest(
                        action: "sign_in",
                        identifier: normalizedIdentifier,
                        password: password,
                        email: nil,
                        handle: nil,
                        nickname: nil
                    ))
                )
                session = try await client.auth.setSession(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken
                )
            }
            await activate(session)
            clearPendingLinkPurpose()
        } catch FunctionsError.httpError(let code, _) where code == 400 {
            phase = .signedOut
            throw AccountValidationError.invalidCredentials
        } catch {
            phase = .signedOut
            throw error
        }
    }

    func checkAvailability(email: String, handle: String, nickname: String) async throws -> AccountAvailability {
        let client = try configuredClient()
        return try await client.functions.invoke(
            "account-auth",
            options: FunctionInvokeOptions(body: AccountAuthRequest(
                action: "availability",
                identifier: nil,
                password: nil,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                handle: handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        )
    }

    func signUp(email: String, password: String, handle: String, nickname: String) async throws -> SignUpResult {
        let client = try configuredClient()
        try await discardAnonymousSession(using: client)

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
                ],
                redirectTo: SupabaseService.authRedirectURL
            )
            if let session = response.session {
                await activate(session)
                clearPendingLinkPurpose()
                return .signedIn
            }
            setPendingLinkPurpose(pendingConfirmationKey)
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
        do {
            let session = try await client.auth.signInWithOAuth(
                provider: provider,
                redirectTo: SupabaseService.authRedirectURL
            )
            await activate(session)
            clearPendingLinkPurpose()
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
        setPendingLinkPurpose(pendingPasswordRecoveryKey)
    }

    func sendHandleRecovery(to email: String) async throws {
        let client = try configuredClient()
        try await client.auth.signInWithOTP(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            redirectTo: SupabaseService.authRedirectURL,
            shouldCreateUser: false
        )
        setPendingLinkPurpose(pendingHandleRecoveryKey)
    }

    func resendSignUpConfirmation(to email: String) async throws {
        let client = try configuredClient()
        try await client.auth.resend(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            type: .signup,
            emailRedirectTo: SupabaseService.authRedirectURL
        )
        setPendingLinkPurpose(pendingConfirmationKey)
    }

    func updatePassword(_ password: String) async throws {
        let client = try configuredClient()
        guard isPasswordAccount else { throw AccountValidationError.oauthPassword }
        _ = try await client.auth.update(user: UserAttributes(password: password))
        requiresPasswordUpdate = false
        UserDefaults.standard.removeObject(forKey: pendingPasswordRecoveryKey)
        accountNotice = "새 비밀번호로 변경했어요. 다음 로그인부터 새 비밀번호를 사용해 주세요."
    }

    func handleIncomingURL(_ url: URL) async {
        guard url.scheme?.lowercased() == SupabaseService.authRedirectURL.scheme,
              let client = SupabaseService.client else { return }
        phase = .loading
        do {
            let session = try await client.auth.session(from: url)
            await activate(session)

            let isRecoveryURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains(where: { $0.name == "type" && $0.value == "recovery" }) == true
            if isRecoveryURL || UserDefaults.standard.bool(forKey: pendingPasswordRecoveryKey) {
                clearPendingLinkPurpose()
                requiresPasswordUpdate = true
            } else if UserDefaults.standard.bool(forKey: pendingHandleRecoveryKey) {
                clearPendingLinkPurpose()
                let recoveredHandle = profile?.handle.map { "@\($0)" } ?? "MY의 내 정보"
                accountNotice = "본인 확인이 완료됐어요. 아이디는 \(recoveredHandle)에서 확인할 수 있어요."
            } else if UserDefaults.standard.bool(forKey: pendingConfirmationKey) {
                clearPendingLinkPurpose()
                accountNotice = "이메일 인증이 완료됐어요. WEARy에 로그인했습니다."
            }
        } catch {
            clearPendingLinkPurpose()
            if (try? await client.auth.session) == nil {
                phase = .signedOut
            }
            accountNotice = Self.deepLinkFailureMessage(for: error)
        }
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

    func refreshAccountSanction() async {
        guard let user = SupabaseService.client?.auth.currentUser,
              !user.isAnonymous else {
            activeAccountSanction = nil
            return
        }

        do {
            let (sanctions, _) = try await SupabaseAccountSanctionRepository.shared.fetchMine()
            activeAccountSanction = sanctions.first {
                $0.isActive && $0.kind != .warning
            }
        } catch {
            // Keep the last known state when a transient network failure occurs.
        }
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
        let fetchedProfile = try? await AccountProfileRepository.shared.fetch(userID: session.user.id)
        guard SupabaseService.client?.auth.currentUser?.id == session.user.id else { return }
        email = session.user.email
        isPasswordAccount = session.user.identities?.contains { $0.provider == "email" } == true
        await SupabaseSessionManager.shared.update(userID: session.user.id)
        profile = fetchedProfile
        activeAccountSanction = nil
        await refreshAccountSanction()
        guard SupabaseService.client?.auth.currentUser?.id == session.user.id else { return }
        userID = session.user.id
        phase = .signedIn
    }

    private func clearSession() async {
        userID = nil
        email = nil
        profile = nil
        isPasswordAccount = false
        requiresPasswordUpdate = false
        activeAccountSanction = nil
        await SupabaseSessionManager.shared.update(userID: nil)
        phase = .signedOut
    }

    private static func deepLinkFailureMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("expired") || message.contains("otp_expired") {
            return "인증 링크가 만료됐어요. 로그인 화면에서 메일을 다시 요청해 주세요."
        }
        if message.contains("access_denied") || message.contains("invalid") {
            return "인증 링크가 유효하지 않아요. 가장 최근에 받은 메일의 링크를 사용해 주세요."
        }
        return "인증 링크를 처리하지 못했어요. 네트워크를 확인한 뒤 메일을 다시 요청해 주세요."
    }

    private func setPendingLinkPurpose(_ key: String) {
        clearPendingLinkPurpose()
        UserDefaults.standard.set(true, forKey: key)
    }

    private func clearPendingLinkPurpose() {
        UserDefaults.standard.removeObject(forKey: pendingConfirmationKey)
        UserDefaults.standard.removeObject(forKey: pendingHandleRecoveryKey)
        UserDefaults.standard.removeObject(forKey: pendingPasswordRecoveryKey)
    }

    static func initials(for name: String) -> String {
        let compact = name.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return "WY" }
        return String(compact.prefix(2)).uppercased()
    }
}

enum AccountValidationError: LocalizedError {
    case oauthPassword
    case invalidCredentials
    case unavailableAccountField

    var errorDescription: String? {
        switch self {
        case .oauthPassword:
            "소셜 로그인 계정의 비밀번호는 해당 서비스에서 관리해 주세요."
        case .invalidCredentials:
            "이메일 또는 아이디와 비밀번호가 맞지 않아요."
        case .unavailableAccountField:
            "중복 확인 결과를 다시 확인해 주세요."
        }
    }
}
