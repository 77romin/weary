import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query private var garments: [Garment]
    @Query(filter: #Predicate<Outfit> { $0.isConfirmed }) private var outfits: [Outfit]

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
                            MetricPill(value: "2", label: "게시물")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("이번 달의 발견")
                                .font(.headline)
                            Text("가장 자주 입은 옷은 커브드 데님이에요. 옷장 속 모든 옷이 이야기가 되도록 계속 기록해 보세요.")
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
                    }
                    .padding(20)
                }
            }
            .navigationTitle("MY")
        }
    }
}
