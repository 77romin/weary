import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var garments: [Garment]
    @Query(filter: #Predicate<Outfit> { $0.isConfirmed }) private var outfits: [Outfit]
    @Query(filter: #Predicate<CommunityPost> { $0.authorHandle == "my.weary" })
    private var myPosts: [CommunityPost]
    @State private var showsDemoResetConfirmation = false
    @State private var demoResetMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 14) {
                            Text("ME")
                                .font(.title3.weight(.black))
                                .frame(width: 62, height: 62)
                                .background(WEARyTheme.lime, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("나의 WEARy")
                                    .font(.title3.weight(.bold))
                                Text("내 스타일이 쌓이는 중")
                                    .font(.subheadline)
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                        }

                        HStack(spacing: 10) {
                            MetricPill(value: "\(garments.count)", label: "옷")
                            MetricPill(value: "\(outfits.count)", label: "착장")
                            MetricPill(value: "\(myPosts.count)", label: "게시물")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("이번 달의 발견")
                                .font(.headline)
                            Text(monthlyDiscoveryText)
                                .font(.body)
                                .foregroundStyle(WEARyTheme.secondaryInk)
                                .padding(18)
                                .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("나의 착장 캘린더")
                                    .font(.headline)
                                Spacer()
                                Text("날짜를 눌러 자세히 보기")
                                    .font(.caption)
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                            MonthOutfitCalendarView(outfits: outfits)
                        }

                        WardrobeInsightsView(garments: garments)

                        WardrobeReviewView(garments: garments)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("프로토타입 도구")
                                .font(.headline)
                            Text("리허설 중 바뀐 착장, 좋아요와 판매 상태를 처음 상태로 되돌려요.")
                                .font(.caption)
                                .foregroundStyle(WEARyTheme.secondaryInk)
                            Button("데모 데이터 초기화", role: .destructive) {
                                showsDemoResetConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("profile.resetDemo")
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("MY")
            .alert("데모 데이터를 초기화할까요?", isPresented: $showsDemoResetConfirmation) {
                Button("취소", role: .cancel) {}
                Button("초기화", role: .destructive) { resetDemoData() }
            } message: {
                Text("직접 등록한 옷과 착장도 삭제되고 발표용 샘플 데이터가 다시 생성됩니다.")
            }
            .alert("데모 데이터", isPresented: Binding(
                get: { demoResetMessage != nil },
                set: { if !$0 { demoResetMessage = nil } }
            )) {
                Button("확인") { demoResetMessage = nil }
            } message: {
                Text(demoResetMessage ?? "")
            }
        }
    }

    private func resetDemoData() {
        do {
            try SampleDataSeeder.resetDemoData(in: modelContext)
            demoResetMessage = "발표용 샘플 데이터로 돌아왔어요."
        } catch {
            demoResetMessage = "초기화하지 못했어요. 앱을 다시 실행한 뒤 시도해 주세요."
        }
    }

    private var monthlyDiscoveryText: String {
        guard let interval = Calendar.current.dateInterval(of: .month, for: .now) else {
            return "착장을 기록하면 이번 달의 스타일을 발견할 수 있어요."
        }
        let ranked = garments
            .map { garment in
                (garment, garment.confirmedOutfitItems.filter {
                    guard let date = $0.outfit?.wornAt else { return false }
                    return interval.contains(date)
                }.count)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }

        guard let top = ranked.first else {
            return "아직 이번 달 착장이 없어요. 오늘의 룩부터 가볍게 남겨보세요."
        }
        return "이번 달에는 ‘\(top.0.name)’을 \(top.1)번 입었어요. 나의 취향이 데이터로 쌓이고 있어요."
    }
}
