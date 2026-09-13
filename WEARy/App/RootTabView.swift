import SwiftUI

enum SocialContentMode: String, CaseIterable, Identifiable {
    case live
    case demo

    static let storageKey = "socialContentMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "실서버"
        case .demo: "데모"
        }
    }

    var description: String {
        switch self {
        case .live: "친구들과 실제로 공유되는 데이터"
        case .demo: "기기에만 저장된 발표용 샘플"
        }
    }
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .feed

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem { Label("피드", systemImage: "rectangle.stack") }
                .tag(AppTab.feed)

            WardrobeView()
                .tabItem { Label("옷장", systemImage: "hanger") }
                .tag(AppTab.wardrobe)

            CaptureView()
                .tabItem { Label("기록", systemImage: "camera.fill") }
                .tag(AppTab.capture)

            MarketView()
                .tabItem { Label("마켓", systemImage: "bag") }
                .tag(AppTab.market)

            ProfileView()
                .tabItem { Label("MY", systemImage: "person") }
                .tag(AppTab.profile)
        }
        .tint(WEARyTheme.ink)
    }
}

private enum AppTab: Hashable {
    case feed
    case wardrobe
    case capture
    case market
    case profile
}
