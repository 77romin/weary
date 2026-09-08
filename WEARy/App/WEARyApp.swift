import SwiftData
import SwiftUI

@main
struct WEARyApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var didCompleteForcedOnboarding = false

    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    private let forcesOnboarding = ProcessInfo.processInfo.arguments.contains("-ui-testing-onboarding")

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Garment.self,
            Outfit.self,
            OutfitItem.self,
            CommunityPost.self,
            MarketListing.self,
        ])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if shouldShowOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                    didCompleteForcedOnboarding = true
                }
            } else {
                RootTabView()
            }
        }
        .modelContainer(modelContainer)
    }

    private var shouldShowOnboarding: Bool {
        if forcesOnboarding { return !didCompleteForcedOnboarding }
        return !isUITesting && !hasCompletedOnboarding
    }
}
