import Supabase
import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
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
                AccountRecoveryView(initialEmail: email)
            }
            .alert("로그인하지 못했어요", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "입력 정보를 확인해 주세요.")
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
            TextField("이메일 (로그인 아이디)", text: $email)
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
            }
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
        email.contains("@") && !password.isEmpty && !isWorking
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
                try await authentication.signIn(email: email, password: password)
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("아이디", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("signup.handle")
                    TextField("닉네임", text: $nickname)
                        .textContentType(.nickname)
                    TextField("이메일", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("비밀번호 (8자 이상)", text: $password)
                        .textContentType(.newPassword)
                    SecureField("비밀번호 확인", text: $passwordConfirmation)
                        .textContentType(.newPassword)
                } header: {
                    Text("WEARy 계정")
                } footer: {
                    Text("아이디는 프로필 주소로 사용되며 가입 후 바꿀 수 없어요. 영문 소문자, 숫자, 마침표와 밑줄로 3–20자까지 입력해 주세요.")
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
        AccountInputValidator.signUpMessage(
            handle: handle,
            nickname: nickname,
            email: email,
            password: password,
            confirmation: passwordConfirmation
        )
    }

    private func submit() {
        guard validationMessage == nil else { return }
        isWorking = true
        Task { @MainActor in
            do {
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

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("아이디 찾기") {
                    Text("개인 이메일로 가입한 경우 이메일 주소가 로그인 아이디예요. 소셜 계정은 해당 Google·Kakao·Apple 버튼으로 로그인해 주세요.")
                        .foregroundStyle(WEARyTheme.secondaryInk)
                }
                Section("비밀번호 재설정") {
                    TextField("가입한 이메일", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("재설정 메일 보내기") { sendReset() }
                        .disabled(!email.contains("@") || isWorking)
                }
            }
            .scrollContentBackground(.hidden)
            .background(WEARyTheme.canvas)
            .navigationTitle("계정 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
            .alert("비밀번호 재설정", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("확인") {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func sendReset() {
        isWorking = true
        Task { @MainActor in
            do {
                try await authentication.sendPasswordReset(to: email)
                message = "가입 여부와 관계없이 요청을 접수했어요. 메일함을 확인해 주세요."
            } catch {
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
                    SecureField("새 비밀번호 (8자 이상)", text: $password)
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
                        .disabled(password.count < 8 || password != confirmation || isWorking)
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
        if password.count < 8 { return "비밀번호를 8자 이상 입력해 주세요." }
        if password != confirmation { return "비밀번호가 일치하지 않아요." }
        return nil
    }
}

private func friendlyMessage(for error: Error) -> String {
    let raw = error.localizedDescription
    let lowercased = raw.lowercased()
    if lowercased.contains("invalid login credentials") { return "이메일 또는 비밀번호가 맞지 않아요." }
    if lowercased.contains("already registered") || lowercased.contains("already been registered") {
        return "이미 가입된 이메일이에요. 로그인하거나 비밀번호를 재설정해 주세요."
    }
    if lowercased.contains("duplicate") || lowercased.contains("profiles_handle") {
        return "이미 사용 중인 아이디예요. 다른 아이디를 선택해 주세요."
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
