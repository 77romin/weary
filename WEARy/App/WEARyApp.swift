import SwiftData
import SwiftUI

@main
struct WEARyApp: App {
    @StateObject private var authentication = AuthenticationStore()
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
                .environmentObject(authentication)
        }
        .modelContainer(modelContainer)
    }
}

private struct AppEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authentication: AuthenticationStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var didCompleteForcedOnboarding = false
    @State private var isPreparingApp = true

    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    private let forcesAuthentication = ProcessInfo.processInfo.arguments.contains("-ui-testing-authentication")
    private let forcesOnboarding = ProcessInfo.processInfo.arguments.contains("-ui-testing-onboarding")

    var body: some View {
        Group {
            if isPreparingApp {
                StartupLoadingView()
            } else if forcesAuthentication {
                AuthenticationView()
            } else if isUITesting {
                testedContent
            } else {
                switch authentication.phase {
                case .loading:
                    StartupLoadingView()
                case .signedOut:
                    AuthenticationView()
                case .signedIn:
                    authenticatedContent
                }
            }
        }
        .task {
            guard isPreparingApp else { return }
            if isUITesting {
                UserDefaults.standard.set(
                    SocialContentMode.demo.rawValue,
                    forKey: SocialContentMode.storageKey
                )
            }
            if !isUITesting { await authentication.bootstrap() }
            SampleDataSeeder.seedIfNeeded(in: modelContext)
            if !isUITesting {
                try? await Task.sleep(for: .milliseconds(900))
            }
            withAnimation(.easeOut(duration: 0.2)) {
                isPreparingApp = false
            }
        }
        .onOpenURL { url in
            Task { await authentication.handleIncomingURL(url) }
        }
        .sheet(isPresented: $authentication.requiresPasswordUpdate) {
            PasswordUpdateView()
        }
        .alert("계정 안내", isPresented: Binding(
            get: { authentication.accountNotice != nil },
            set: { if !$0 { authentication.accountNotice = nil } }
        )) {
            Button("확인", role: .cancel) { authentication.accountNotice = nil }
        } message: {
            Text(authentication.accountNotice ?? "")
        }
    }

    @ViewBuilder
    private var testedContent: some View {
        if shouldShowOnboarding {
            OnboardingView {
                hasCompletedOnboarding = true
                didCompleteForcedOnboarding = true
            }
        } else {
            RootTabView()
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if shouldShowOnboarding {
            OnboardingView {
                hasCompletedOnboarding = true
                didCompleteForcedOnboarding = true
            }
        } else {
            RootTabView()
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
