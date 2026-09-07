import SwiftData
import SwiftUI

@main
struct WEARyApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Garment.self,
            Outfit.self,
            OutfitItem.self,
            CommunityPost.self,
            MarketListing.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}
