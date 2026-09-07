import SwiftUI

struct FeedView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("오늘, 이렇게 입었어요")
                            .font(.system(.title2, design: .rounded, weight: .bold))

                        FeedPreviewCard(
                            initials: "SY",
                            name: "서연",
                            caption: "빈티지 레더와 데님의 월요일 조합",
                            tags: "#시티보이  #가을코디",
                            color: Color(hex: "A7B9CE")
                        )
                        FeedPreviewCard(
                            initials: "JM",
                            name: "지민",
                            caption: "색 하나만 강하게 넣어보기",
                            tags: "#미니멀  #레드포인트",
                            color: Color(hex: "E99C8D")
                        )
                    }
                    .padding(18)
                }
            }
            .navigationTitle("!WEARy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "bell")
                }
            }
        }
    }
}

private struct FeedPreviewCard: View {
    let initials: String
    let name: String
    let caption: String
    let tags: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(initials)
                    .font(.caption.weight(.bold))
                    .frame(width: 38, height: 38)
                    .background(WEARyTheme.lime, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.subheadline.weight(.bold))
                    Text("서울 · 오늘").font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "ellipsis")
            }

            ZStack {
                color
                Image(systemName: "figure.stand.dress")
                    .font(.system(size: 100, weight: .thin))
                    .foregroundStyle(WEARyTheme.ink.opacity(0.75))
            }
            .frame(height: 370)
            .clipShape(RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius))

            HStack(spacing: 18) {
                Label("128", systemImage: "heart")
                Label("14", systemImage: "bubble")
                Spacer()
                Image(systemName: "bookmark")
            }
            .font(.subheadline.weight(.semibold))

            Text(caption).font(.subheadline.weight(.medium))
            Text(tags).font(.caption).foregroundStyle(WEARyTheme.coral)
        }
        .padding(16)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 28))
    }
}
