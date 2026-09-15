import Charts
import PhotosUI
import SwiftData
import SwiftUI

struct WardrobeInsightsView: View {
    let garments: [Garment]
    @State private var period: InsightPeriod = .thirtyDays

    private var usage: [GarmentUsage] {
        WardrobeInsights.usage(garments: garments, period: period)
    }

    private var activeUsage: [GarmentUsage] { usage.filter { $0.count > 0 } }
    private var totalWears: Int { usage.reduce(0) { $0 + $1.count } }
    private var utilization: Int {
        guard !garments.isEmpty else { return 0 }
        return Int((Double(activeUsage.count) / Double(garments.count) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("옷장 활용 리포트").font(.headline)
                Spacer()
                Picker("기간", selection: $period) {
                    ForEach(InsightPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                MetricPill(value: "\(totalWears)회", label: "기간 내 착용")
                MetricPill(value: "\(utilization)%", label: "옷장 활용률")
                MetricPill(value: "\(max(0, garments.count - activeUsage.count))", label: "안 입은 옷")
            }

            if activeUsage.isEmpty {
                ContentUnavailableView(
                    "아직 기간 내 기록이 없어요",
                    systemImage: "chart.bar",
                    description: Text("착장을 기록하면 자주 입은 옷을 보여드려요.")
                )
                .frame(maxWidth: .infinity).frame(height: 220)
            } else {
                Chart(Array(activeUsage.prefix(5))) { item in
                    BarMark(
                        x: .value("착용 횟수", item.count),
                        y: .value("옷", item.garment.name)
                    )
                    .foregroundStyle(WEARyTheme.coral.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(item.count)").font(.caption2.bold())
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name).lineLimit(1).font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(170, activeUsage.prefix(5).count * 42)))
                .padding(14)
                .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("\(period.title) 동안 자주 입은 옷 차트")
            }

            if let bestValue = garments
                .compactMap({ garment in garment.costPerWear.map { (garment, $0) } })
                .min(by: { $0.1 < $1.1 }) {
                HStack(spacing: 12) {
                    GarmentCutoutThumbnail(garment: bestValue.0).frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("가장 알뜰하게 입은 옷").font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
                        Text("\(bestValue.0.name) · 1회 \(bestValue.1.formatted())원")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WEARyTheme.lime.opacity(0.48), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

struct AIRecommendationInsightsView: View {
    let summary: AIRecommendationSummary
    @ObservedObject private var diagnostics = OutfitAnalysisDiagnostics.shared
    @State private var showingBenchmark = false
    @State private var showingEvaluation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 추천 실험실", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Label("기기에만 저장", systemImage: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WEARyTheme.secondaryInk)
            }

            Button("반복 분석 성능 비교") { showingBenchmark = true }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("profile.visionBenchmark")
            Button("정답 옷으로 추천 평가") { showingEvaluation = true }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("profile.visionEvaluation")
            if let elapsed = diagnostics.elapsedMilliseconds {
                Text("최근 분석 \(elapsed.formatted(.number.precision(.fractionLength(0))))ms · \(diagnostics.performance == nil ? "기본 후보 전환" : "Vision 비교")")
                    .font(.caption)
                if let performance = diagnostics.performance {
                    Text("마지막 Vision 시도: 재사용 \(performance.cacheHits)회 · 새 특징값 \(performance.generatedPrints)개 · 캐시 \(performance.cachedPrints)/128개")
                        .font(.caption2)
                    Text("특징값 데이터 \(performance.cachedPayloadBytes.formatted())바이트 / 4MB 한도 · 앱 실행 중에만 유지")
                        .font(.caption2)
                        .foregroundStyle(WEARyTheme.secondaryInk)
                }
            }
            if summary.analyzedOutfitCount == 0 {
                Text("새 착장을 기록하면 Vision 후보를 얼마나 유지하고 수정했는지 보여드려요.")
                    .font(.subheadline)
                    .foregroundStyle(WEARyTheme.secondaryInk)
            } else {
                HStack(spacing: 10) {
                    MetricPill(value: "\(summary.acceptanceRate)%", label: "후보 채택")
                    MetricPill(value: "\(summary.topOneRate)%", label: "첫 후보")
                    MetricPill(value: "\(summary.adjustmentRate)%", label: "수정 필요")
                }

                Text("착장 \(summary.analyzedOutfitCount)회 · Vision 후보 \(summary.visionCandidateCount)개 · 기본 후보 전환 \(summary.fallbackOutfitCount)회")
                    .font(.caption)
                    .foregroundStyle(WEARyTheme.secondaryInk)
                Text("정답 정확도가 아니라, 사용자가 최종 확정한 선택을 기준으로 한 PoC 지표예요.")
                    .font(.caption2)
                    .foregroundStyle(WEARyTheme.secondaryInk)
            }
        }
        .padding(16)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.aiRecommendationInsights")
        .sheet(isPresented: $showingBenchmark) { VisionBenchmarkView() }
        .sheet(isPresented: $showingEvaluation) { VisionEvaluationView() }
    }
}

private struct VisionEvaluationView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var garments: [Garment]
    @ObservedObject private var session = OutfitEvaluationSession.shared
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var truthIDs = Set<UUID>()
    @State private var result: OutfitEvaluationResult?
    @State private var message: String?
    @State private var isWorking = false
    @State private var evaluationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section("1. 사진과 정답 지정") {
                    Text("본인 또는 동의받은 착장 사진을 선택하고, 추천을 보기 전에 실제로 입은 옷을 모두 지정해 주세요. 사진·결과는 자동 저장하거나 서버로 보내지 않습니다.")
                        .font(.caption)
                    PhotosPicker(photoData == nil ? "평가할 착장 사진 선택" : "사진 선택됨 · 변경", selection: $photo, matching: .images)
                    ForEach(garments.sorted { $0.name < $1.name }) { garment in
                        Button {
                            if truthIDs.contains(garment.id) { truthIDs.remove(garment.id) }
                            else { truthIDs.insert(garment.id) }
                            result = nil
                        } label: {
                            HStack {
                                Image(systemName: truthIDs.contains(garment.id) ? "checkmark.circle.fill" : "circle")
                                Text("\(garment.category.rawValue) · \(garment.name)")
                            }
                        }
                    }
                }
                .disabled(isWorking)
                Section("2. 추천 평가") {
                    Button("지정한 정답으로 평가") { evaluate() }
                        .disabled(isWorking || photoData == nil || truthIDs.isEmpty || result != nil)
                    if isWorking { ProgressView("기기 안에서 추천 비교 중…") }
                    if let message { Text(message).font(.caption) }
                    if let result {
                        LabeledContent("정답 옷별 Top-1", value: "\(result.topOneHits)/\(result.scores.count)")
                        LabeledContent("정답 옷별 Top-3", value: "\(result.topThreeHits)/\(result.scores.count)")
                        LabeledContent("Vision 비교 범위", value: "\(result.visionCoveredCount)/\(result.scores.count)")
                        LabeledContent("거리 수집 범위", value: "\(result.distanceCoveredCount)/\(result.scores.count)")
                        LabeledContent("자동 선택 정확", value: "\(result.autoSelectionCorrectCount)/\(result.autoSelectedCount)")
                        Text("정답 옷이 해당 카테고리의 첫 후보·상위 3개 후보에 포함되는지 계산합니다. 비교할 Vision 후보가 없는 정답은 미적중입니다. 같은 카테고리의 여러 옷도 각각 집계합니다.")
                            .font(.caption)
                        ForEach(result.scores, id: \.garmentID) { score in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(score.category) · \(garmentName(score.garmentID))")
                                    .font(.subheadline.weight(.semibold))
                                Text(scoreStatus(score))
                                    .font(.caption)
                                if !score.candidateIDs.isEmpty {
                                    Text(candidateSummary(score))
                                        .font(.caption2)
                                        .foregroundStyle(WEARyTheme.secondaryInk)
                                }
                            }
                        }
                    }
                }
                Section("실행 중 평가 모음 · 최근 50회") {
                    Text("\(session.results.count)회 · 정답 \(session.truthCount)개 · Top-1 \(session.topOneHits)개 · Top-3 \(session.topThreeHits)개 적중")
                    Text("거리값 \(session.distanceCoveredCount)개 · 자동 선택 정확 \(session.autoSelectionCorrectCount)/\(session.autoSelectedCount)")
                        .font(.caption)
                    let calibration = session.calibration
                    if calibration.isReadyForExploration {
                        Text("보정 탐색 준비됨 · Top-1 적중 거리 중앙값 \(distance(calibration.medianHitDistance)) · 미적중 \(distance(calibration.medianMissDistance))")
                            .font(.caption)
                    } else {
                        Text("신뢰도 보정 탐색까지 거리 표본 \(calibration.sampleCount)/20개 · 적중 \(calibration.hitCount)/5개 · 미적중 \(calibration.missCount)/5개")
                            .font(.caption)
                    }
                    Text("앱 종료 시 사라집니다. 같은 사진의 재평가는 최근 결과로 교체합니다. 채택률과 별도이며 정답 카테고리의 Vision 비교가 전혀 없으면 제외합니다. 얼굴 사진·옷 이름 없이 UUID·카테고리·후보·거리·신뢰도·버전만 공유합니다.")
                        .font(.caption)
                    ShareLink("평가 JSON 공유", item: session.exportJSON)
                        .disabled(session.results.isEmpty)
                        .accessibilityIdentifier("evaluation.share")
                    Button("평가 모음 비우기", role: .destructive) { session.clear() }
                        .disabled(isWorking || session.results.isEmpty)
                }
            }
            .navigationTitle("정답 기반 추천 평가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("완료") { dismiss() } }
            .task(id: photo) {
                photoData = nil
                result = nil
                truthIDs.removeAll()
                message = nil
                guard let photo else { return }
                do {
                    let data = try await photo.loadTransferable(type: Data.self)
                    try Task.checkCancellation()
                    photoData = data
                    if data == nil { message = "사진을 읽지 못했어요." }
                } catch is CancellationError {
                } catch { message = "사진을 읽지 못했어요. 다시 선택해 주세요." }
            }
            .onDisappear { evaluationTask?.cancel() }
        }
    }

    private func evaluate() {
        guard !isWorking, let photoData, !truthIDs.isEmpty else { return }
        let truth = truthIDs
        let snapshots = garments.map { GarmentSnapshot(id: $0.id, category: $0.category, name: $0.name,
                                                       imageData: $0.imageData, cutoutImageData: $0.cutoutImageData) }
        isWorking = true
        message = nil
        evaluationTask = Task { @MainActor in
            defer { isWorking = false }
            do {
                let groups = try await DeviceOutfitAnalyzer().analyze(photoData: photoData, wardrobe: snapshots)
                try Task.checkCancellation()
                let measured = try OutfitEvaluation.evaluate(groundTruthIDs: truth, wardrobe: snapshots, groups: groups)
                guard measured.isValidVisionRun else {
                    message = "정답 옷에 대한 Vision 비교가 없어 평가 모음에서 제외했어요. 실제 아이폰과 옷 사진을 확인해 주세요."
                    return
                }
                result = measured
                session.append(measured, photoKey: FeaturePrintCache<Int>.imageKey(photoData))
            } catch is CancellationError {
            } catch { message = error.localizedDescription }
        }
    }

    private func distance(_ value: Float?) -> String {
        guard let value else { return "없음" }
        return value.formatted(.number.precision(.fractionLength(2)))
    }

    private func garmentName(_ id: UUID) -> String {
        garments.first { $0.id == id }?.name ?? "삭제된 옷"
    }

    private func scoreStatus(_ score: OutfitEvaluationScore) -> String {
        guard score.usedVision, !score.candidateIDs.isEmpty else { return "Vision 비교 후보 없음 · 미적중" }
        let rank = score.candidateIDs.firstIndex(of: score.garmentID).map { $0 + 1 }
        let result = rank.map { "Top-\($0) 적중" } ?? "Top-3 미적중"
        return "\(result) · 신뢰도 \(score.reportedConfidence ?? "없음") · 최단 거리 \(distance(score.bestDistance))"
    }

    private func candidateSummary(_ score: OutfitEvaluationScore) -> String {
        zip(score.candidateIDs, score.candidateDistances).enumerated().map { index, pair in
            "\(index + 1). \(garmentName(pair.0)) (\(distance(pair.1)))"
        }.joined(separator: " · ")
    }
}

private struct VisionBenchmarkView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var garments: [Garment]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var result: VisionBenchmarkResult?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("착장 사진 하나로 빈 특징값 캐시 1회와 재사용 3회를 비교합니다. 사진·결과는 서버에 보내거나 저장하지 않습니다.")
                    Text("사진이 있는 옷 중 이름·ID 순으로 최대 128개를 비교합니다. 실제 추천 정확도를 평가하는 기능은 아닙니다.")
                        .font(.caption)
                    PhotosPicker("착장 사진 선택하고 비교", selection: $selectedPhoto, matching: .images)
                        .disabled(isWorking)
                    if isWorking { ProgressView("Vision 비교 중…") }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
                if let result {
                    Section("분석 시간") {
                        LabeledContent("빈 캐시", value: milliseconds(result.cold.milliseconds))
                        LabeledContent("재사용 3회 중앙값", value: milliseconds(result.warmMedianMilliseconds))
                        LabeledContent("빈 캐시 새 계산", value: "\(result.cold.performance.generatedPrints)개")
                        ForEach(Array(result.warm.enumerated()), id: \.offset) { index, sample in
                            LabeledContent("재사용 \(index + 1)회", value: "\(milliseconds(sample.milliseconds)) · 캐시 \(sample.performance.cacheHits)회")
                        }
                    }
                    Section("프로세스 메모리 관측") {
                        if let bytes = result.maximumObservedFootprintBytes {
                            LabeledContent("분석 중 최대 footprint", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))
                        } else { Text("이 환경에서 메모리 정보를 읽지 못했어요.") }
                        LabeledContent("메모리 표본", value: "총 \(result.totalMemorySampleCount)회")
                        Text("각 분석의 시작·종료와 실행 중 약 10ms 간격으로 읽은 앱 전체 footprint의 관측 최대값입니다. 순간적인 실제 최고점을 놓칠 수 있고 다른 화면·OS 상태의 영향을 받습니다. 빈 캐시는 OS·Vision 자체의 최초 실행을 의미하지 않습니다.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Vision 성능 비교")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("완료") { dismiss() } }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                isWorking = true
                result = nil
                errorMessage = nil
                defer { isWorking = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                        throw OutfitAnalysisError.invalidOutfitPhoto
                    }
                    let snapshots = garments
                        .filter { $0.cutoutImageData != nil || $0.imageData != nil }
                        .sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name }
                        .prefix(128)
                        .map { GarmentSnapshot(id: $0.id, category: $0.category, name: $0.name,
                                               imageData: $0.imageData, cutoutImageData: $0.cutoutImageData) }
                    let measured = try await VisionCacheBenchmark.run(photoData: data, wardrobe: snapshots)
                    try Task.checkCancellation()
                    result = measured
                } catch is CancellationError {
                    // Dismissing the sheet cancels the remaining comparisons.
                } catch {
                    errorMessage = "Vision 성능 비교를 완료하지 못했어요. 옷장 사진을 확인하고 실제 아이폰에서 다시 시도해 주세요."
                }
            }
        }
    }

    private func milliseconds(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0))))ms"
    }
}

struct WardrobeReviewView: View {
    @Environment(\.modelContext) private var modelContext
    let garments: [Garment]
    @State private var thresholdDays = 180
    @State private var listingGarment: Garment?

    private var candidates: [Garment] {
        WardrobeInsights.reviewCandidates(garments: garments, thresholdDays: thresholdDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("다시 볼 옷").font(.headline)
                    Text("결정은 언제나 내가 해요").font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
                }
                Spacer()
                Picker("미착용 기준", selection: $thresholdDays) {
                    Text("90일").tag(90)
                    Text("180일").tag(180)
                    Text("1년").tag(365)
                }
                .pickerStyle(.menu)
            }

            if candidates.isEmpty {
                Label("지금 검토할 옷이 없어요", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WEARyTheme.secondaryInk)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ForEach(candidates) { garment in
                    reviewCard(garment)
                }
            }
        }
        .sheet(item: $listingGarment) { garment in
            NavigationStack { CreateListingView(garment: garment) }
        }
    }

    private func reviewCard(_ garment: Garment) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                GarmentCutoutThumbnail(garment: garment).frame(width: 66, height: 66)
                VStack(alignment: .leading, spacing: 4) {
                    Text(garment.name).font(.subheadline.weight(.bold))
                    Text(reviewReason(for: garment))
                        .font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                actionButton("유지", status: .keep, garment: garment)
                actionButton("보관", status: .stored, garment: garment)
                Button("판매하기") { listingGarment = garment }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent).tint(WEARyTheme.ink)
            }
        }
        .padding(16)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func actionButton(_ title: String, status: GarmentStatus, garment: Garment) -> some View {
        Button(title) {
            withAnimation(.snappy) { garment.status = status }
            try? modelContext.save()
        }
        .font(.caption.weight(.bold)).buttonStyle(.bordered).tint(WEARyTheme.ink)
    }

    private func reviewReason(for garment: Garment) -> String {
        let days = WardrobeInsights.daysSinceLastUse(for: garment)
        if garment.wearCount == 0 { return "등록 이후 착용 기록이 없어요 · \(days)일" }
        return "마지막으로 입은 지 \(days)일 됐어요 · 총 \(garment.wearCount)회"
    }
}
