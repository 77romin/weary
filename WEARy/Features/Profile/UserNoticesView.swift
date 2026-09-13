import SwiftUI

struct UserNoticesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notices: [UserNoticeSnapshot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if notices.isEmpty, !isLoading {
                    ContentUnavailableView(
                        "새 알림이 없습니다",
                        systemImage: "bell",
                        description: Text("신고 처리 결과와 운영 안내가 여기에 표시돼요.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(notices) { notice in
                        Button {
                            Task { await markRead(notice) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(notice.readAt == nil ? WEARyTheme.coral : .clear)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 7)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(notice.title)
                                        .font(.headline)
                                        .foregroundStyle(WEARyTheme.ink)
                                    Text(notice.body)
                                        .font(.subheadline)
                                        .foregroundStyle(WEARyTheme.secondaryInk)
                                    Text(notice.createdAt, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(WEARyTheme.secondaryInk)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if isLoading, notices.isEmpty {
                    ProgressView("알림 불러오는 중…")
                }
            }
            .scrollContentBackground(.hidden)
            .background(WEARyTheme.canvas)
            .navigationTitle("알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .refreshable {
                await load()
            }
            .task {
                await load()
            }
            .alert("알림을 불러오지 못했어요", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            notices = try await SupabaseUserNoticeRepository.shared.fetchNotices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func markRead(_ notice: UserNoticeSnapshot) async {
        guard notice.readAt == nil else { return }
        do {
            try await SupabaseUserNoticeRepository.shared.markRead(noticeID: notice.id)
            guard let index = notices.firstIndex(where: { $0.id == notice.id }) else { return }
            notices[index].readAt = .now
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
