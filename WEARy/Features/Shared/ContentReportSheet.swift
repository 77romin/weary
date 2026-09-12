import SwiftUI

struct ContentReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: ContentReportTarget
    let targetID: UUID
    let onSubmitted: () -> Void
    @State private var reason: ContentReportReason = .spam
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var submissionError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("신고 이유") {
                    Picker("이유", selection: $reason) {
                        ForEach(ContentReportReason.allCases) { reason in
                            Text(reason.title).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("추가 설명 · 선택") {
                    TextEditor(text: $details)
                        .frame(minHeight: 110)
                    Text("\(details.count)/1,000")
                        .font(.caption)
                        .foregroundStyle(details.count > 1_000 ? Color.red : WEARyTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Section {
                    Text("신고 내용은 운영 검토에 사용되며 신고만으로 콘텐츠가 자동 삭제되지는 않습니다.")
                        .font(.caption)
                        .foregroundStyle(WEARyTheme.secondaryInk)
                }
            }
            .navigationTitle("신고하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting { ProgressView() } else { Text("제출") }
                    }
                    .disabled(isSubmitting || details.count > 1_000)
                }
            }
            .alert("신고를 접수하지 못했어요", isPresented: Binding(
                get: { submissionError != nil },
                set: { if !$0 { submissionError = nil } }
            )) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(submissionError ?? "다시 시도해 주세요.")
            }
        }
    }

    @MainActor
    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await SupabaseContentSafetyRepository.shared.submitReport(
                target: target,
                targetID: targetID,
                reason: reason,
                details: details
            )
            onSubmitted()
            dismiss()
        } catch {
            submissionError = error.localizedDescription
        }
    }
}

struct BlockedUserListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var users: [BlockedUserSnapshot] = []
    @State private var isLoading = true
    @State private var workingUserID: UUID?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, users.isEmpty {
                    ProgressView("차단 목록 불러오는 중…")
                } else if users.isEmpty {
                    ContentUnavailableView(
                        "차단한 사용자가 없어요",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                } else {
                    List(users) { user in
                        HStack(spacing: 12) {
                            Text(user.initials)
                                .font(.caption.weight(.black))
                                .frame(width: 42, height: 42)
                                .background(Color(hex: user.accentHex), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName).fontWeight(.semibold)
                                Text("@\(user.handle)")
                                    .font(.caption)
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                            Spacer()
                            Button("차단 해제") {
                                Task { await unblock(user) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(workingUserID != nil)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(WEARyTheme.canvas)
            .navigationTitle("차단한 사용자")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .task { await loadUsers() }
            .alert("차단 목록 요청 실패", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(loadError ?? "다시 시도해 주세요.")
            }
        }
    }

    @MainActor
    private func loadUsers() async {
        do {
            users = try await SupabaseContentSafetyRepository.shared.fetchBlockedUsers()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func unblock(_ user: BlockedUserSnapshot) async {
        guard workingUserID == nil else { return }
        workingUserID = user.id
        defer { workingUserID = nil }
        do {
            try await SupabaseContentSafetyRepository.shared.setBlocked(
                userID: user.id,
                isBlocked: false
            )
            users.removeAll { $0.id == user.id }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
