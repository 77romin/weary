import SwiftUI

struct MarketView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("옷장에서 다음 옷장으로")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        HStack(spacing: 12) {
                            MarketPreviewCard(name: "울 크롭 코트", price: "89,000원", color: Color(hex: "B7A08B"))
                            MarketPreviewCard(name: "블랙 니트 드레스", price: "72,000원", color: Color(hex: "464646"))
                        }
                        HStack(spacing: 12) {
                            MarketPreviewCard(name: "레드 미니 백", price: "48,000원", color: Color(hex: "D94B43"))
                            MarketPreviewCard(name: "실버 러너", price: "95,000원", color: Color(hex: "B9BEC2"))
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("마켓")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("판매") { }
                        .fontWeight(.bold)
                }
            }
        }
    }
}

private struct MarketPreviewCard: View {
    let name: String
    let price: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                color
                Image(systemName: "hanger")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(WEARyTheme.ink.opacity(0.75))
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(price).font(.headline)
            Text("착용 정보 인증")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WEARyTheme.coral)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
