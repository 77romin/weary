import SwiftData
import SwiftUI

struct AccountProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authentication: AuthenticationStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @Query private var communityPosts: [CommunityPost]
    @Query private var marketListings: [MarketListing]
    @State private var handle = ""
    @State private var nickname = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var gender: AccountGender = .undisclosed
    @State private var chest = ""
    @State private var waist = ""
    @State private var hip = ""
    @State private var inseam = ""
    @State private var newPassword = ""
    @State private var passwordConfirmation = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var loadedProfileID: UUID?
    @State private var showingAccountDeletion = false
    @State private var isModerator = false

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                bodySection
                optionalMeasurementsSection
                passwordSection
                if isModerator {
                    Section("운영") {
                        NavigationLink {
                            ModerationReportsView()
                        } label: {
                            Label("신고 검토", systemImage: "checkmark.shield")
                        }
                        .accessibilityIdentifier("profile.moderationReports")
                    }
                }
                Section {
                    Button("로그아웃", role: .destructive) { logout() }
                        .frame(maxWidth: .infinity)
                    Button("계정 탈퇴", role: .destructive) {
                        showingAccountDeletion = true
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("profile.deleteAccount")
                }
            }
            .scrollContentBackground(.hidden)
            .background(WEARyTheme.canvas)
            .navigationTitle("내 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .fontWeight(.bold)
                        .disabled(saveValidationMessage != nil || isWorking)
                        .accessibilityIdentifier("profile.accountSave")
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingAccountDeletion) {
                AccountDeletionConfirmationView {
                    try clearLocalData()
                    hasCompletedOnboarding = false
                }
                .environmentObject(authentication)
            }
            .alert("내 정보", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("확인") {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func clearLocalData() throws {
        try modelContext.delete(model: CommunityPost.self)
        try modelContext.delete(model: MarketListing.self)
        try modelContext.delete(model: OutfitItem.self)
        try modelContext.delete(model: Outfit.self)
        try modelContext.delete(model: Garment.self)
        try modelContext.save()
    }

    private var identitySection: some View {
        Section {
            TextField("아이디", text: $handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(authentication.profile?.handleLocked == true)
            LabeledContent("로그인 이메일", value: authentication.email ?? "-")
            TextField("닉네임", text: $nickname)
                .textContentType(.nickname)
        } header: {
            Text("계정")
        } footer: {
            Text(authentication.profile?.handleLocked == true
                 ? "이메일과 아이디는 가입 후 변경할 수 없어요. 닉네임은 수정할 수 있으며 피드와 판매 글에 표시됩니다."
                 : "아이디를 이번에 저장하면 이후에는 변경할 수 없어요. 닉네임은 수정할 수 있습니다.")
        }
    }

    private var bodySection: some View {
        Section("기본 신체 정보") {
            measurementField("키", value: $height)
            measurementField("몸무게", value: $weight, unit: "kg")
            Picker("성별", selection: $gender) {
                ForEach(AccountGender.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        }
    }

    private var optionalMeasurementsSection: some View {
        Section {
            measurementField("가슴둘레", value: $chest)
            measurementField("허리둘레", value: $waist)
            measurementField("엉덩이둘레", value: $hip)
            measurementField("인심 기장", value: $inseam)
        } header: {
            Text("추가 치수 · 선택")
        } footer: {
            Text("현재는 저장만 하며, 추후 상품 치수 비교와 맞춤 추천에 사용하기 전 별도 동의를 받을 예정이에요.")
        }
    }

    @ViewBuilder
    private var passwordSection: some View {
        if authentication.isPasswordAccount {
            Section {
                SecureField("새 비밀번호 (변경할 때만 입력)", text: $newPassword)
                SecureField("새 비밀번호 확인", text: $passwordConfirmation)
            } header: {
                Text("비밀번호")
            }
        } else {
            Section("비밀번호") {
                Text("소셜 로그인 계정의 비밀번호는 Google·Kakao·Apple에서 관리해 주세요.")
                    .foregroundStyle(WEARyTheme.secondaryInk)
            }
        }
    }

    private var saveValidationMessage: String? {
        let normalizedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !AccountInputValidator.isValidHandle(normalizedHandle) { return "아이디를 확인해 주세요." }
        if nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { return "닉네임을 확인해 주세요." }
        if !newPassword.isEmpty && newPassword.count < 8 { return "새 비밀번호는 8자 이상이어야 해요." }
        if newPassword != passwordConfirmation { return "새 비밀번호가 일치하지 않아요." }
        return nil
    }

    private func measurementField(_ title: String, value: Binding<String>, unit: String = "cm") -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("선택", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(WEARyTheme.secondaryInk)
        }
    }

    @MainActor
    private func load() async {
        do {
            isModerator = (try? await SupabaseModerationRepository.shared.isCurrentUserModerator()) ?? false
            if authentication.profile == nil { try await authentication.refreshProfile() }
            guard let profile = authentication.profile, loadedProfileID != profile.id else { return }
            loadedProfileID = profile.id
            handle = profile.handle ?? ""
            nickname = profile.displayName
            height = text(profile.heightCM)
            weight = text(profile.weightKG)
            gender = profile.gender ?? .undisclosed
            chest = text(profile.chestCM)
            waist = text(profile.waistCM)
            hip = text(profile.hipCM)
            inseam = text(profile.inseamCM)
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() {
        guard saveValidationMessage == nil,
              let userID = SupabaseService.client?.auth.currentUser?.id else { return }
        isWorking = true
        Task { @MainActor in
            do {
                let normalizedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await AccountProfileRepository.shared.update(
                    userID: userID,
                    profile: AccountProfileUpdate(
                        displayName: normalizedNickname,
                        handle: handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        avatarInitials: AuthenticationStore.initials(for: normalizedNickname)
                    ),
                    measurements: PrivateProfileMeasurements(
                        id: userID,
                        heightCM: number(height),
                        weightKG: number(weight),
                        gender: gender == .undisclosed ? nil : gender,
                        chestCM: number(chest),
                        waistCM: number(waist),
                        hipCM: number(hip),
                        inseamCM: number(inseam)
                    )
                )
                if !newPassword.isEmpty {
                    try await authentication.updatePassword(newPassword)
                }
                updateLocalDisplayName(to: normalizedNickname)
                try await authentication.refreshProfile()
                message = "내 정보를 저장했어요."
                newPassword = ""
                passwordConfirmation = ""
            } catch {
                let raw = error.localizedDescription
                message = raw.lowercased().contains("profiles_nickname_key_unique")
                    ? "이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해 주세요."
                    : raw
            }
            isWorking = false
        }
    }

    private func logout() {
        isWorking = true
        Task { @MainActor in
            do {
                try await authentication.signOut()
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func updateLocalDisplayName(to nickname: String) {
        for post in communityPosts where post.authorHandle == "my.weary" {
            post.authorName = nickname
            post.authorInitials = AuthenticationStore.initials(for: nickname)
        }
        for listing in marketListings where listing.isOwnedByCurrentUser {
            listing.sellerName = nickname
        }
        try? modelContext.save()
    }

    private func number(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct AccountDeletionConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationStore
    let clearLocalData: () throws -> Void
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("이 작업은 되돌릴 수 없습니다.", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("공개 게시물, 매물, 채팅, 프로필과 서버 사진을 삭제하고 이 기기의 옷장·착장 기록도 비웁니다.")
                    Text("탈퇴를 계속하려면 아래에 ‘탈퇴’를 입력해 주세요.")
                        .font(.subheadline.weight(.semibold))
                }
                Section("확인 문구") {
                    TextField("탈퇴", text: $confirmation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isDeleting)
                }
                Section {
                    Button("계정과 데이터 영구 삭제", role: .destructive) {
                        Task { await deleteAccount() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(confirmation != "탈퇴" || isDeleting)
                    .accessibilityIdentifier("profile.confirmAccountDeletion")
                    if isDeleting {
                        HStack {
                            Spacer()
                            ProgressView("데이터 삭제 중…")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("계정 탈퇴")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isDeleting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.disabled(isDeleting)
                }
            }
            .alert("계정을 삭제하지 못했어요", isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(deletionError ?? "네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
            }
        }
    }

    @MainActor
    private func deleteAccount() async {
        guard confirmation == "탈퇴", !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await SupabaseAccountDeletionRepository.shared.deleteCurrentAccount()
            try clearLocalData()
            await authentication.finishAccountDeletion()
            dismiss()
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
