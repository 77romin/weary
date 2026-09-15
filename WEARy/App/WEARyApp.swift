import SwiftData
import SwiftUI

@main
struct WEARyApp: App {
    @StateObject private var authentication = AuthenticationStore()
    private let modelContainer: ModelContainer = {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")

        do {
            return try AppModelContainerFactory.make(isStoredInMemoryOnly: isUITesting)
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

enum AppModelContainerFactory {
    static let cloudKitContainerIdentifier = "iCloud.com.weary.prototype"

    static let personalSchema = Schema([
        Garment.self,
        Outfit.self,
        OutfitItem.self,
    ])

    static let serviceCacheSchema = Schema([
        CommunityPost.self,
        MarketListing.self,
    ])

    static let appSchema = Schema([
        Garment.self,
        Outfit.self,
        OutfitItem.self,
        CommunityPost.self,
        MarketListing.self,
    ])

    static func make(
        isStoredInMemoryOnly: Bool,
        baseDirectoryURL: URL? = nil,
        cloudKitEnabled: Bool = defaultCloudKitEnabled
    ) throws -> ModelContainer {
        let personalConfiguration: ModelConfiguration
        let serviceCacheConfiguration: ModelConfiguration

        if isStoredInMemoryOnly {
            personalConfiguration = ModelConfiguration(
                "Personal",
                schema: personalSchema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            serviceCacheConfiguration = ModelConfiguration(
                "ServiceCache",
                schema: serviceCacheSchema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            let legacyStoreURL = baseDirectoryURL?.appending(path: "default.store")
                ?? ModelConfiguration().url
            let cacheStoreURL = legacyStoreURL
                .deletingLastPathComponent()
                .appending(path: "service-cache.store")
            personalConfiguration = ModelConfiguration(
                "Personal",
                schema: personalSchema,
                url: legacyStoreURL,
                cloudKitDatabase: cloudKitEnabled
                    ? .private(cloudKitContainerIdentifier)
                    : .none
            )
            serviceCacheConfiguration = ModelConfiguration(
                "ServiceCache",
                schema: serviceCacheSchema,
                url: cacheStoreURL,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(
            for: appSchema,
            configurations: [personalConfiguration, serviceCacheConfiguration]
        )
    }

    static var defaultCloudKitEnabled: Bool {
#if CLOUDKIT_ENABLED
        true
#else
        false
#endif
    }
}

private struct AppEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authentication: AuthenticationStore
    @AppStorage("showsOnboardingReplay") private var showsOnboardingReplay = false
    @State private var didCompleteForcedOnboarding = false
    @State private var didCompleteSignedOutOnboarding = false
    @State private var isPreparingApp = true
    @AppStorage("serviceCacheOwnerID") private var serviceCacheOwnerID = ""
    @State private var readyCacheUserID: UUID?
    @State private var cachePreparationError: String?

    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    private let forcesAuthentication = ProcessInfo.processInfo.arguments.contains("-ui-testing-authentication")
    private let forcesOnboarding = ProcessInfo.processInfo.arguments.contains("-ui-testing-onboarding")
    private let simulatesSignedOut = ProcessInfo.processInfo.arguments.contains("-ui-testing-signed-out")

    var body: some View {
        Group {
            if isPreparingApp {
                StartupLoadingView()
            } else if shouldShowOnboarding {
                OnboardingView {
                    showsOnboardingReplay = false
                    didCompleteForcedOnboarding = true
                    didCompleteSignedOutOnboarding = true
                }
            } else if forcesAuthentication || simulatesSignedOut {
                AuthenticationView()
            } else if isUITesting {
                RootTabView()
            } else {
                switch authentication.phase {
                case .loading:
                    StartupLoadingView()
                case .signedOut:
                    AuthenticationView()
                case .signedIn:
                    if let userID = authentication.userID, readyCacheUserID == userID {
                        RootTabView().id(userID)
                    } else if let cachePreparationError {
                        ContentUnavailableView {
                            Label("계정 데이터를 준비하지 못했어요", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(cachePreparationError)
                        } actions: {
                            Button("다시 시도") { prepareServiceCache() }
                        }
                    } else {
                        StartupLoadingView()
                    }
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
        .task(id: authentication.userID) {
            prepareServiceCache()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await authentication.refreshAccountSanction() }
        }
        .onChange(of: isSignedIn) { wasSignedIn, signedIn in
            if wasSignedIn && !signedIn {
                didCompleteSignedOutOnboarding = false
            }
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

    private var shouldShowOnboarding: Bool {
        if forcesOnboarding { return !didCompleteForcedOnboarding }
        if simulatesSignedOut { return !didCompleteSignedOutOnboarding }
        if isUITesting || forcesAuthentication { return false }
        if case .signedOut = authentication.phase {
            return !didCompleteSignedOutOnboarding
        }
        guard isSignedIn else { return false }
        return showsOnboardingReplay
    }

    private func prepareServiceCache() {
        readyCacheUserID = nil
        cachePreparationError = nil
        guard let userID = authentication.userID else { return }
        do {
            if serviceCacheOwnerID != userID.uuidString {
                try ServiceCacheBoundary.clearRemoteCache(in: modelContext)
                serviceCacheOwnerID = userID.uuidString
            }
            readyCacheUserID = userID
        } catch {
            cachePreparationError = "이전 계정의 캐시를 정리하지 못했어요. 다시 시도해 주세요."
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = authentication.phase { return true }
        return false
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
