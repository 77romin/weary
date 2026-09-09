import SwiftUI

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
