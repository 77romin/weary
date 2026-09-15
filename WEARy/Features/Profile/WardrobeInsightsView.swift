import Charts
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
