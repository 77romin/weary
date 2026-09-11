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
            AppEntryView()
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}

private struct AppEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var didCompleteForcedOnboarding = false
    @State private var isPreparingApp = true

    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    private let forcesOnboarding = ProcessInfo.processInfo.arguments.contains("-ui-testing-onboarding")

    var body: some View {
        Group {
            if isPreparingApp {
                StartupLoadingView()
            } else if shouldShowOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                    didCompleteForcedOnboarding = true
                }
            } else {
                RootTabView()
            }
        }
        .task {
            guard isPreparingApp else { return }
            Task {
                await SupabaseSessionManager.shared.bootstrap()
            }
            SampleDataSeeder.seedIfNeeded(in: modelContext)
            if !isUITesting {
                try? await Task.sleep(for: .milliseconds(900))
            }
            withAnimation(.easeOut(duration: 0.2)) {
                isPreparingApp = false
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        if forcesOnboarding { return !didCompleteForcedOnboarding }
        return !isUITesting && !hasCompletedOnboarding
    }
}

private struct StartupLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("!WEARy")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .tracking(-2)
                .foregroundStyle(WEARyTheme.ink)

            Text("Don't WEARy, Be HAPPY")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WEARyTheme.snow.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("WEARy 로딩 중")
        .accessibilityIdentifier("app.loading")
    }
}
