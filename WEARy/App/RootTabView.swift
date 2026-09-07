import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = .wardrobe
    @State private var didSeed = false

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
        .task {
            guard !didSeed else { return }
            didSeed = true
            SampleDataSeeder.seedIfNeeded(in: modelContext)
        }
    }
}

private enum AppTab: Hashable {
    case feed
    case wardrobe
    case capture
    case market
    case profile
}
