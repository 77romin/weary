import Supabase
import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var identifier = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showingSignUp = false
    @State private var showingRecovery = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 28)
                    brand
                    credentials
                    recoveryButton
                    confirmationResendButton
                    socialLogins
                    signUpButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WEARyTheme.snow.ignoresSafeArea())
            .disabled(isWorking)
            .overlay {
                if isWorking {
                    ProgressView("연결 중…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .sheet(isPresented: $showingSignUp) {
                SignUpView()
            }
            .sheet(isPresented: $showingRecovery) {
                AccountRecoveryView(initialEmail: identifier.contains("@") ? identifier : "")
            }
            .alert("로그인하지 못했어요", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "입력 정보를 확인해 주세요.")
            }
            .alert("이메일 인증", isPresented: Binding(
                get: { confirmationMessage != nil },
                set: { if !$0 { confirmationMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(confirmationMessage ?? "")
            }
        }
        .accessibilityIdentifier("auth.login")
    }

    private var brand: some View {
        VStack(spacing: 8) {
            Text("!WEARy")
                .font(.system(size: 48, weight: .black, design: .rounded))
                .tracking(-2)
            Text("Don't WEARy, Be HAPPY")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .foregroundStyle(WEARyTheme.ink)
    }

    private var credentials: some View {
        VStack(spacing: 14) {
            TextField("이메일 또는 아이디", text: $identifier)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .wearyAuthField()
                .accessibilityIdentifier("auth.email")

            SecureField("비밀번호", text: $password)
                .textContentType(.password)
                .wearyAuthField()
                .accessibilityIdentifier("auth.password")

            Button(action: login) {
                Text("로그인")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .foregroundStyle(WEARyTheme.ink)
            .background(WEARyTheme.lime, in: RoundedRectangle(cornerRadius: 16))
            .disabled(!canLogin)
            .opacity(canLogin ? 1 : 0.45)
            .accessibilityIdentifier("auth.submit")
        }
    }

    private var recoveryButton: some View {
        Button("아이디 / 비밀번호 찾기") {
            showingRecovery = true
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(WEARyTheme.secondaryInk)
    }

    private var confirmationResendButton: some View {
        Button("가입 확인 메일 다시 보내기") {
            resendConfirmation()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(WEARyTheme.secondaryInk)
        .disabled(!identifier.contains("@") || isWorking)
        .opacity(identifier.contains("@") ? 1 : 0.45)
    }

    private var socialLogins: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Rectangle().fill(WEARyTheme.line).frame(height: 1)
                Text("또는").font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
                Rectangle().fill(WEARyTheme.line).frame(height: 1)
            }

            oauthButton(title: "Google로 계속하기", mark: "G", color: .white, identifier: "google", provider: .google)
            oauthButton(title: "카카오로 계속하기", mark: "K", color: Color(hex: "FEE500"), identifier: "kakao", provider: .kakao)
            oauthButton(title: "Apple로 계속하기", mark: "", color: .black, foreground: .white, identifier: "apple", provider: .apple)
        }
    }

    private var signUpButton: some View {
        Button {
            showingSignUp = true
        } label: {
            Text("처음이신가요? ") + Text("회원가입").bold()
        }
        .foregroundStyle(WEARyTheme.ink)
        .padding(.top, 2)
        .accessibilityIdentifier("auth.openSignUp")
    }

    private var canLogin: Bool {
        AccountInputValidator.isValidLoginIdentifier(identifier) && !password.isEmpty && !isWorking
    }

    private func oauthButton(
        title: String,
        mark: String,
        color: Color,
        foreground: Color = WEARyTheme.ink,
        identifier: String,
        provider: Provider
    ) -> some View {
        Button {
            oauth(provider)
        } label: {
            HStack {
                Text(mark).font(.title3.weight(.bold)).frame(width: 26)
                Text(title).font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(color, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WEARyTheme.line))
        .accessibilityIdentifier("auth.oauth.\(identifier)")
    }

    private func login() {
        guard canLogin else { return }
        isWorking = true
        Task { @MainActor in
            do {
                try await authentication.signIn(identifier: identifier, password: password)
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }

    private func oauth(_ provider: Provider) {
        isWorking = true
        Task { @MainActor in
            do {
                try await authentication.signInWithOAuth(provider)
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }

    private func resendConfirmation() {
        guard identifier.contains("@"), !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            do {
                try await authentication.resendSignUpConfirmation(to: identifier)
                confirmationMessage = "가입 확인 메일을 다시 보냈어요. 스팸 메일함도 확인해 주세요."
            } catch {
                confirmationMessage = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }
}

private struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var handle = ""
    @State private var nickname = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var shouldDismissAfterMessage = false
    @State private var availability: AccountAvailability?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이메일", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("signup.email")
                        .onChange(of: email) { _, _ in availability = nil }
                    TextField("아이디", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("signup.handle")
                        .onChange(of: handle) { _, _ in availability = nil }
                    TextField("닉네임", text: $nickname)
                        .textContentType(.nickname)
                        .accessibilityIdentifier("signup.nickname")
                        .onChange(of: nickname) { _, _ in availability = nil }
                    Button("이메일·아이디·닉네임 중복 확인") {
                        checkAvailability()
                    }
                    .disabled(!canCheckAvailability || isWorking)
                    .accessibilityIdentifier("signup.checkAvailability")
                    if let availability {
                        Label(
                            availabilityMessage(availability),
                            systemImage: availability.allAvailable
                                ? "checkmark.circle.fill"
                                : "exclamationmark.circle.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(availability.allAvailable ? .green : .red)
                    }
                    SecureField("비밀번호 (8자 이상 · 영문+숫자)", text: $password)
                        .textContentType(.newPassword)
                    SecureField("비밀번호 확인", text: $passwordConfirmation)
                        .textContentType(.newPassword)
                } header: {
                    Text("WEARy 계정")
                } footer: {
                    Text("이메일과 아이디는 가입 후 바꿀 수 없어요. 아이디는 영문 소문자, 숫자, 마침표와 밑줄로 3–20자까지 입력해 주세요. 가입 전에 세 항목의 중복 확인이 필요합니다.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(WEARyTheme.canvas)
            .navigationTitle("회원가입")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        isWorking ? AnyView(ProgressView()) : AnyView(Text("가입").fontWeight(.bold))
                    }
                    .disabled(validationMessage != nil || isWorking)
                    .accessibilityIdentifier("signup.submit")
                }
            }
            .alert("회원가입", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("확인") {
                    if shouldDismissAfterMessage { dismiss() }
                }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var validationMessage: String? {
        if let message = AccountInputValidator.signUpMessage(
            handle: handle,
            nickname: nickname,
            email: email,
            password: password,
            confirmation: passwordConfirmation
        ) { return message }
        guard availability?.allAvailable == true else {
            return "이메일·아이디·닉네임 중복 확인을 완료해 주세요."
        }
        return nil
    }

    private var canCheckAvailability: Bool {
        AccountInputValidator.isValidHandle(handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) &&
            nickname.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
            email.contains("@")
    }

    private func availabilityMessage(_ availability: AccountAvailability) -> String {
        var duplicates: [String] = []
        if !availability.emailAvailable { duplicates.append("이메일") }
        if !availability.handleAvailable { duplicates.append("아이디") }
        if !availability.nicknameAvailable { duplicates.append("닉네임") }
        return duplicates.isEmpty
            ? "모두 사용할 수 있어요."
            : "이미 사용 중: \(duplicates.joined(separator: ", "))"
    }

    private func checkAvailability() {
        guard canCheckAvailability, !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            do {
                availability = try await authentication.checkAvailability(
                    email: email,
                    handle: handle,
                    nickname: nickname
                )
            } catch {
                message = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }

    private func submit() {
        guard validationMessage == nil else { return }
        isWorking = true
        Task { @MainActor in
            do {
                let latestAvailability = try await authentication.checkAvailability(
                    email: email,
                    handle: handle,
                    nickname: nickname
                )
                availability = latestAvailability
                guard latestAvailability.allAvailable else {
                    throw AccountValidationError.unavailableAccountField
                }
                let result = try await authentication.signUp(
                    email: email,
                    password: password,
                    handle: handle,
                    nickname: nickname
                )
                switch result {
                case .signedIn:
                    dismiss()
                case .emailConfirmationRequired:
                    shouldDismissAfterMessage = true
                    message = "가입 확인 메일을 보냈어요. 메일에서 인증한 뒤 로그인해 주세요."
                }
            } catch {
                message = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }
}

private struct AccountRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var email: String
    @State private var isWorking = false
    @State private var message: String?
    @State private var messageTitle = "계정 찾기"

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("본인 확인") {
                    TextField("가입한 이메일", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("recovery.email")
                    Text("아이디 찾기는 가입 이메일로 본인 확인 링크를 보냅니다. 링크를 누르면 앱에서 아이디를 안전하게 확인할 수 있어요.")
                        .foregroundStyle(WEARyTheme.secondaryInk)
                    Button("아이디 확인 메일 보내기") { sendHandleRecovery() }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("recovery.handle")
                }
                Section("비밀번호 재설정") {
                    Button("재설정 메일 보내기") { sendReset() }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("recovery.password")
                    Text("가장 최근에 받은 링크만 사용할 수 있어요. 링크가 만료되면 이 화면에서 다시 요청해 주세요.")
                        .font(.footnote)
                        .foregroundStyle(WEARyTheme.secondaryInk)
                }
            }
            .scrollContentBackground(.hidden)
            .background(WEARyTheme.canvas)
            .navigationTitle("계정 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
            .alert(messageTitle, isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("확인") {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && !isWorking
    }

    private func sendHandleRecovery() {
        guard canSubmit else { return }
        isWorking = true
        Task { @MainActor in
            do {
                try await authentication.sendHandleRecovery(to: email)
                messageTitle = "아이디 찾기"
                message = "가입 여부와 관계없이 요청을 접수했어요. 받은 링크를 이 아이폰에서 열어 주세요."
            } catch {
                messageTitle = "메일을 보내지 못했어요"
                message = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }

    private func sendReset() {
        guard canSubmit else { return }
        isWorking = true
        Task { @MainActor in
            do {
                try await authentication.sendPasswordReset(to: email)
                messageTitle = "비밀번호 재설정"
                message = "가입 여부와 관계없이 요청을 접수했어요. 메일함을 확인해 주세요."
            } catch {
                messageTitle = "메일을 보내지 못했어요"
                message = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }
}

struct PasswordUpdateView: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("새 비밀번호 (8자 이상 · 영문+숫자)", text: $password)
                    SecureField("새 비밀번호 확인", text: $confirmation)
                } footer: {
                    Text("다른 서비스에서 사용하지 않는 비밀번호를 권장해요.")
                }
            }
            .navigationTitle("새 비밀번호")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("변경") { update() }
                        .fontWeight(.bold)
                        .disabled(!AccountInputValidator.isValidPassword(password) || password != confirmation || isWorking)
                }
            }
            .alert("변경하지 못했어요", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled()
    }

    private func update() {
        isWorking = true
        Task { @MainActor in
            do {
                try await authentication.updatePassword(password)
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }
}

enum AccountInputValidator {
    static func isValidHandle(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9._]{3,20}$", options: .regularExpression) != nil
    }

    static func isValidLoginIdentifier(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("@") || isValidHandle(normalized)
    }

    static func isValidPassword(_ value: String) -> Bool {
        value.count >= 8
            && value.rangeOfCharacter(from: .letters) != nil
            && value.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static func signUpMessage(
        handle: String,
        nickname: String,
        email: String,
        password: String,
        confirmation: String
    ) -> String? {
        let normalizedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !isValidHandle(normalizedHandle) { return "아이디 형식을 확인해 주세요." }
        if nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { return "닉네임을 2자 이상 입력해 주세요." }
        if !email.contains("@") { return "이메일을 확인해 주세요." }
        if !isValidPassword(password) { return "비밀번호는 8자 이상이며 영문과 숫자를 포함해야 해요." }
        if password != confirmation { return "비밀번호가 일치하지 않아요." }
        return nil
    }
}

private func friendlyMessage(for error: Error) -> String {
    let raw = error.localizedDescription
    let lowercased = raw.lowercased()
    if lowercased.contains("email not confirmed") {
        return "이메일 인증이 아직 완료되지 않았어요. 가입 확인 메일의 링크를 누른 뒤 다시 로그인해 주세요."
    }
    if lowercased.contains("otp_expired") || lowercased.contains("expired") {
        return "인증 링크가 만료됐어요. 가장 최근 메일을 사용하거나 새 메일을 요청해 주세요."
    }
    if lowercased.contains("network") || lowercased.contains("offline") || lowercased.contains("internet") {
        return "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
    }
    if lowercased.contains("invalid email") {
        return "이메일 형식을 확인해 주세요."
    }
    if lowercased.contains("email address not authorized") ||
        lowercased.contains("email rate limit exceeded") {
        return "현재 개발용 메일 발송이 제한되어 있어요. 잠시 후 다시 시도하거나 관리자에게 이메일 인증 설정을 확인해 달라고 요청해 주세요."
    }
    if lowercased.contains("invalid login credentials") { return "이메일 또는 아이디와 비밀번호가 맞지 않아요." }
    if lowercased.contains("already registered") || lowercased.contains("already been registered") {
        return "이미 가입된 이메일이에요. 로그인하거나 비밀번호를 재설정해 주세요."
    }
    if lowercased.contains("profiles_nickname_key_unique") {
        return "이미 사용 중인 닉네임이에요. 다른 닉네임을 선택해 주세요."
    }
    if lowercased.contains("edge function") || lowercased.contains("relay error") {
        return "계정 서버에 연결하지 못했어요. 네트워크를 확인한 뒤 다시 시도해 주세요."
    }
    if lowercased.contains("duplicate") || lowercased.contains("profiles_handle") {
        return "이미 사용 중인 이메일 또는 아이디예요. 중복 확인 후 다시 시도해 주세요."
    }
    if lowercased.contains("provider is not enabled") || lowercased.contains("unsupported provider") {
        return "아직 Supabase에서 이 소셜 로그인이 설정되지 않았어요."
    }
    return raw
}

private extension View {
    func wearyAuthField() -> some View {
        padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WEARyTheme.line))
    }
}
