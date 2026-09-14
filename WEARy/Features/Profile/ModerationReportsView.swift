import SwiftUI

struct AccountSanctionsView: View {
    @State private var sanctions: [AccountSanctionSnapshot] = []
    @State private var appeals: [AccountSanctionAppealSnapshot] = []
    @State private var selectedSanction: AccountSanctionSnapshot?
    @State private var appealBody = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            if sanctions.isEmpty {
                ContentUnavailableView("계정 제재 내역이 없어요", systemImage: "checkmark.shield", description: Text("운영 정책 관련 안내와 이의 제기 상태를 여기서 확인할 수 있어요."))
                    .listRowBackground(Color.clear)
            }
            ForEach(sanctions) { sanction in
                Section {
                    Text(sanction.reason)
                    if let end = sanction.endsAt { LabeledContent("종료 예정", value: end.formatted(date: .abbreviated, time: .shortened)) }
                    if let appeal = appeals.first(where: { $0.sanctionID == sanction.id }) {
                        LabeledContent("이의 제기", value: appealStatus(appeal.status))
                        if !appeal.moderatorNote.isEmpty { Text(appeal.moderatorNote).foregroundStyle(WEARyTheme.secondaryInk) }
                    } else if sanction.isActive {
                        Button("이의 제기") { selectedSanction = sanction }
                    }
                } header: {
                    Label(sanction.kind.title, systemImage: sanction.isActive ? "exclamationmark.shield.fill" : "checkmark.shield")
                }
            }
        }
        .navigationTitle("계정 제재·이의 제기")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedSanction) { sanction in
            NavigationStack {
                Form {
                    Section("제재 사유") { Text(sanction.reason) }
                    Section("이의 제기 내용") {
                        TextEditor(text: $appealBody).frame(minHeight: 150)
                        Text("\(appealBody.count)/2,000").font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
                    }
                }
                .navigationTitle("이의 제기")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { selectedSanction = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("제출") { Task { await submit(for: sanction) } }
                            .disabled(appealBody.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || appealBody.count > 2_000)
                    }
                }
            }
        }
        .alert("처리하지 못했어요", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor private func load() async {
        do { (sanctions, appeals) = try await SupabaseAccountSanctionRepository.shared.fetchMine() }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func submit(for sanction: AccountSanctionSnapshot) async {
        do {
            try await SupabaseAccountSanctionRepository.shared.submitAppeal(sanctionID: sanction.id, body: appealBody)
            appealBody = ""
            selectedSanction = nil
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    private func appealStatus(_ value: String) -> String {
        ["pending": "검토 대기", "reviewing": "검토 중", "accepted": "인용", "rejected": "기각"][value] ?? value
    }
}

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

struct ModerationAppealsView: View {
    @State private var appeals: [ModerationAppealSnapshot] = []
    @State private var selectedStatus: String? = "pending"
    @State private var errorMessage: String?

    var body: some View {
        List {
            Picker("상태", selection: $selectedStatus) {
                Text("전체").tag(String?.none)
                Text("검토 대기").tag(String?.some("pending"))
                Text("검토 중").tag(String?.some("reviewing"))
                Text("처리 완료").tag(String?.some("completed"))
            }
            if appeals.isEmpty {
                ContentUnavailableView("이의 제기가 없습니다", systemImage: "checkmark.bubble", description: Text("선택한 상태에 해당하는 요청이 없어요."))
                    .listRowBackground(Color.clear)
            }
            ForEach(appeals) { appeal in
                NavigationLink {
                    ModerationAppealDetailView(appeal: appeal) { await load() }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(appeal.userName) · @\(appeal.userHandle)").fontWeight(.semibold)
                        Text(appeal.appealBody).lineLimit(2)
                        Text(appeal.sanctionKind.title).font(.caption).foregroundStyle(WEARyTheme.coral)
                    }
                }
            }
        }
        .navigationTitle("이의 제기 심사")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedStatus) { await load() }
        .refreshable { await load() }
        .alert("불러오지 못했어요", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor private func load() async {
        do {
            let requestedStatus = selectedStatus == "completed" ? nil : selectedStatus
            let result = try await SupabaseAccountSanctionRepository.shared.fetchModerationAppeals(status: requestedStatus)
            appeals = selectedStatus == "completed" ? result.filter { ["accepted", "rejected"].contains($0.status) } : result
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ModerationAppealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let appeal: ModerationAppealSnapshot
    let onUpdated: () async -> Void
    @State private var note: String
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(appeal: ModerationAppealSnapshot, onUpdated: @escaping () async -> Void) {
        self.appeal = appeal
        self.onUpdated = onUpdated
        _note = State(initialValue: appeal.moderatorNote)
    }

    var body: some View {
        Form {
            Section("사용자") {
                LabeledContent("닉네임", value: appeal.userName)
                LabeledContent("아이디", value: "@\(appeal.userHandle)")
            }
            Section("기존 제재") {
                LabeledContent("종류", value: appeal.sanctionKind.title)
                Text(appeal.sanctionReason)
            }
            Section("이의 제기") { Text(appeal.appealBody) }
            Section("운영 메모") {
                TextEditor(text: $note).frame(minHeight: 100)
                Text("\(note.count)/1,000").font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
            }
            if ["pending", "reviewing"].contains(appeal.status) {
                Section("처리") {
                    if appeal.status == "pending" { action("검토 시작", status: "reviewing") }
                    action("인용하고 제재 해제", status: "accepted")
                    action("기각하고 제재 유지", status: "rejected")
                }
            }
        }
        .navigationTitle("이의 제기")
        .navigationBarTitleDisplayMode(.inline)
        .alert("처리하지 못했어요", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func action(_ title: String, status: String) -> some View {
        Button(title) { Task { await review(status) } }.disabled(isWorking || note.count > 1_000)
    }

    @MainActor private func review(_ status: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseAccountSanctionRepository.shared.reviewAppeal(id: appeal.id, status: status, note: note)
            await onUpdated()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
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
    @State private var sanctionKind: AccountSanctionKind = .warning
    @State private var restrictionDays = 7

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
                if report.status == .actioned {
                    Text("조치 완료 후 상태 변경은 이의 제기 절차에서만 할 수 있어요.")
                        .foregroundStyle(WEARyTheme.secondaryInk)
                } else if report.status != .reviewing {
                    actionButton("검토 시작", status: .reviewing)
                }
                if report.status != .actioned, report.status != .dismissed {
                    actionButton("위반 없음으로 종료", status: .dismissed)
                }
                if report.status != .actioned, report.targetType != "user" {
                    actionButton("조치 완료", status: .actioned)
                }
            }

            if report.targetType == "user", report.status != .actioned {
                Section {
                    Picker("제재 종류", selection: $sanctionKind) {
                        ForEach(AccountSanctionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    if sanctionKind == .restriction {
                        Stepper("제한 기간 \(restrictionDays)일", value: $restrictionDays, in: 1...365)
                    }
                    Button("계정 제재 및 조치 완료", role: .destructive) {
                        Task { await actionUserReport() }
                    }
                    .disabled(isWorking || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("moderation.actionUser")
                } header: {
                    Text("계정 제재")
                } footer: {
                    Text("운영 메모가 사용자에게 제재 사유로 안내됩니다. 경고와 정지는 종료일이 없고, 이용 제한은 설정한 기간 후 자동 만료됩니다.")
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
    private func actionUserReport() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let endsAt = sanctionKind == .restriction
            ? Calendar.current.date(byAdding: .day, value: restrictionDays, to: .now)
            : nil
        do {
            try await SupabaseAccountSanctionRepository.shared.actionUserReport(
                reportID: report.id,
                kind: sanctionKind,
                reason: note,
                endsAt: endsAt,
                note: note
            )
            await onUpdated()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
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
