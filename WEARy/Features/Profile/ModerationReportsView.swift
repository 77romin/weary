import SwiftUI

struct ModerationReportsView: View {
    @State private var selectedFilter: ModerationReportFilter = .pending
    @State private var reports: [ModerationReportSnapshot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("처리 상태", selection: $selectedFilter) {
                    ForEach(ModerationReportFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            if reports.isEmpty, !isLoading {
                ContentUnavailableView(
                    "신고가 없습니다",
                    systemImage: "checkmark.shield",
                    description: Text("선택한 상태에 해당하는 신고가 없어요.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(reports) { report in
                    NavigationLink {
                        ModerationReportDetailView(report: report) {
                            await loadReports()
                        }
                    } label: {
                        ModerationReportRow(report: report)
                    }
                }
            }
        }
        .overlay {
            if isLoading, reports.isEmpty {
                ProgressView("신고 불러오는 중…")
            }
        }
        .scrollContentBackground(.hidden)
        .background(WEARyTheme.canvas)
        .navigationTitle("신고 검토")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedFilter) {
            await loadReports()
        }
        .refreshable {
            await loadReports()
        }
        .alert("신고를 불러오지 못했어요", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func loadReports() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            reports = try await SupabaseModerationRepository.shared.fetchReports(
                status: selectedFilter.status
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ModerationReportFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case reviewing
    case dismissed
    case actioned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .pending: "검토 대기"
        case .reviewing: "검토 중"
        case .dismissed: "위반 없음"
        case .actioned: "조치 완료"
        }
    }

    var status: ModerationReportStatus? {
        self == .all ? nil : ModerationReportStatus(rawValue: rawValue)
    }
}

private struct ModerationReportRow: View {
    let report: ModerationReportSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(targetTitle, systemImage: targetIcon)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(report.status.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
            }
            Text(report.targetSummary)
                .font(.body)
                .lineLimit(2)
            HStack {
                Text(reasonTitle)
                Spacer()
                Text(report.createdAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .padding(.vertical, 4)
    }

    private var targetTitle: String {
        switch report.targetType {
        case "post": "게시물 신고"
        case "listing": "매물 신고"
        case "message": "메시지 신고"
        case "user": "사용자 신고"
        default: "콘텐츠 신고"
        }
    }

    private var targetIcon: String {
        switch report.targetType {
        case "post": "photo"
        case "listing": "bag"
        case "message": "message"
        case "user": "person"
        default: "exclamationmark.bubble"
        }
    }

    private var reasonTitle: String {
        ContentReportReason(rawValue: report.reason)?.title ?? report.reason
    }

    private var statusColor: Color {
        switch report.status {
        case .pending: WEARyTheme.coral
        case .reviewing: .orange
        case .dismissed: WEARyTheme.secondaryInk
        case .actioned: .green
        }
    }
}

private struct ModerationReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let report: ModerationReportSnapshot
    let onUpdated: () async -> Void
    @State private var note: String
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(
        report: ModerationReportSnapshot,
        onUpdated: @escaping () async -> Void
    ) {
        self.report = report
        self.onUpdated = onUpdated
        _note = State(initialValue: report.moderatorNote)
    }

    var body: some View {
        Form {
            Section("신고 대상") {
                LabeledContent("종류", value: targetTitle)
                Text(report.targetSummary)
                    .textSelection(.enabled)
                LabeledContent("대상 ID", value: report.targetID.uuidString)
                    .font(.caption)
            }

            Section("신고 내용") {
                LabeledContent(
                    "사유",
                    value: ContentReportReason(rawValue: report.reason)?.title ?? report.reason
                )
                if report.details.isEmpty {
                    Text("추가 설명 없음")
                        .foregroundStyle(WEARyTheme.secondaryInk)
                } else {
                    Text(report.details)
                }
            }

            Section("신고자") {
                LabeledContent("닉네임", value: report.reporterName)
                LabeledContent("아이디", value: "@\(report.reporterHandle)")
                LabeledContent("접수", value: report.createdAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section {
                TextEditor(text: $note)
                    .frame(minHeight: 100)
                    .disabled(isWorking)
            } header: {
                Text("운영 메모")
            } footer: {
                Text("\(note.count)/1,000 · 처리 근거를 개인정보 없이 간단히 기록해 주세요.")
            }

            Section("처리") {
                if report.status != .reviewing {
                    actionButton("검토 시작", status: .reviewing)
                }
                if report.status != .dismissed {
                    actionButton("위반 없음으로 종료", status: .dismissed)
                }
                if report.status != .actioned {
                    actionButton("조치 완료", status: .actioned)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(WEARyTheme.canvas)
        .navigationTitle(report.status.title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isWorking)
        .overlay {
            if isWorking {
                ProgressView("처리 중…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .alert("신고를 처리하지 못했어요", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var targetTitle: String {
        switch report.targetType {
        case "post": "게시물"
        case "listing": "매물"
        case "message": "메시지"
        case "user": "사용자"
        default: report.targetType
        }
    }

    private func actionButton(
        _ title: String,
        status: ModerationReportStatus
    ) -> some View {
        Button(title) {
            Task { await update(status: status) }
        }
        .disabled(isWorking || note.count > 1_000)
    }

    @MainActor
    private func update(status: ModerationReportStatus) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseModerationRepository.shared.review(
                reportID: report.id,
                status: status,
                note: note
            )
            await onUpdated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
