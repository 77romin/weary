import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authentication: AuthenticationStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @Query private var garments: [Garment]
    @Query(filter: #Predicate<Outfit> { $0.isConfirmed }) private var outfits: [Outfit]
    @Query private var communityPosts: [CommunityPost]
    @State private var showsDemoResetConfirmation = false
    @State private var demoResetMessage: String?
    @State private var selectedSocialList: SocialListKind?
    @State private var remoteSocialGraph: CommunitySocialGraphSnapshot?
    @State private var showingAccountProfile = false
    @State private var showingBlockedUsers = false

    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Button {
                            showingAccountProfile = true
                        } label: {
                            HStack(spacing: 14) {
                                Text(authentication.profile?.avatarInitials ?? "ME")
                                    .font(.title3.weight(.black))
                                    .frame(width: 62, height: 62)
                                    .background(WEARyTheme.lime, in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(authentication.displayName)
                                        .font(.title3.weight(.bold))
                                    Text(authentication.handle.map { "@\($0)" } ?? "아이디를 설정해 주세요")
                                        .font(.subheadline)
                                        .foregroundStyle(WEARyTheme.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("내 정보 수정")
                        .accessibilityIdentifier("profile.account")

                        HStack(spacing: 0) {
                            socialCountButton(
                                value: followerUsers.count,
                                label: "팔로워",
                                kind: .followers
                            )
                            Divider().frame(height: 34)
                            socialCountButton(
                                value: followingUsers.count,
                                label: "팔로잉",
                                kind: .following
                            )
                        }
                        .padding(.vertical, 12)
                        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 18))

                        HStack(spacing: 10) {
                            MetricPill(value: "\(garments.count)", label: "옷")
                            MetricPill(value: "\(outfits.count)", label: "착장")
                            MetricPill(value: "\(myPosts.count)", label: "게시물")
                        }

                        Button {
                            showingBlockedUsers = true
                        } label: {
                            HStack {
                                Label("차단한 사용자 관리", systemImage: "person.crop.circle.badge.xmark")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                            .padding(16)
                            .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.blockedUsers")

                        VStack(alignment: .leading, spacing: 12) {
                            Text("이번 달의 발견")
                                .font(.headline)
                            Text(monthlyDiscoveryText)
                                .font(.body)
                                .foregroundStyle(WEARyTheme.secondaryInk)
                                .padding(18)
                                .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("나의 착장 캘린더")
                                    .font(.headline)
                                Spacer()
                                Text("날짜를 눌러 자세히 보기")
                                    .font(.caption)
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                            MonthOutfitCalendarView(outfits: outfits)
                        }

                        WardrobeInsightsView(garments: garments)

                        WardrobeReviewView(garments: garments)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("프로토타입 도구")
                                .font(.headline)
                            Text("리허설 중 바뀐 착장, 좋아요와 판매 상태를 처음 상태로 되돌려요.")
                                .font(.caption)
                                .foregroundStyle(WEARyTheme.secondaryInk)
                            Button("데모 데이터 초기화", role: .destructive) {
                                showsDemoResetConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("profile.resetDemo")

                            Button {
                                hasCompletedOnboarding = false
                            } label: {
                                Label("앱 안내 다시 보기", systemImage: "questionmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(WEARyTheme.ink)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .padding(20)
                }
                .refreshable {
                    await loadRemoteSocialGraph()
                }
            }
            .navigationTitle("MY")
            .sheet(item: $selectedSocialList) { kind in
                SocialUserListView(
                    title: kind == .followers ? "팔로워" : "팔로잉",
                    users: kind == .followers ? followerUsers : followingUsers
                )
            }
            .sheet(isPresented: $showingAccountProfile) {
                AccountProfileView()
            }
            .sheet(isPresented: $showingBlockedUsers) {
                BlockedUserListView()
            }
            .alert("데모 데이터를 초기화할까요?", isPresented: $showsDemoResetConfirmation) {
                Button("취소", role: .cancel) {}
                Button("초기화", role: .destructive) { resetDemoData() }
            } message: {
                Text("직접 등록한 옷과 착장도 삭제되고 발표용 샘플 데이터가 다시 생성됩니다.")
            }
            .alert("데모 데이터", isPresented: Binding(
                get: { demoResetMessage != nil },
                set: { if !$0 { demoResetMessage = nil } }
            )) {
                Button("확인") { demoResetMessage = nil }
            } message: {
                Text(demoResetMessage ?? "")
            }
            .task {
                await loadRemoteSocialGraph()
            }
        }
    }

    private var myPosts: [CommunityPost] {
        communityPosts.filter { $0.authorHandle == "my.weary" }
    }

    private func resetDemoData() {
        do {
            try SampleDataSeeder.resetDemoData(in: modelContext)
            demoResetMessage = "발표용 샘플 데이터로 돌아왔어요."
        } catch {
            demoResetMessage = "초기화하지 못했어요. 앱을 다시 실행한 뒤 시도해 주세요."
        }
    }

    private func socialCountButton(value: Int, label: String, kind: SocialListKind) -> some View {
        Button {
            selectedSocialList = kind
        } label: {
            VStack(spacing: 3) {
                Text("\(value)")
                    .font(.headline)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(WEARyTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.\(kind.rawValue)")
    }

    private var followingUsers: [SocialUser] {
        var seen = Set<String>()
        var users = (remoteSocialGraph?.following ?? []).compactMap { user -> SocialUser? in
            guard seen.insert(user.handle).inserted else { return nil }
            return SocialUser(snapshot: user)
        }
        users += communityPosts.compactMap { post in
            guard post.isFollowing,
                  post.authorHandle != "my.weary",
                  seen.insert(post.authorHandle).inserted else { return nil }
            return SocialUser(
                name: post.authorName,
                handle: post.authorHandle,
                initials: post.authorInitials,
                accentHex: post.accentHex
            )
        }
        return users.sorted { $0.name < $1.name }
    }

    private var followerUsers: [SocialUser] {
        guard let remoteSocialGraph else {
            return [
            SocialUser(name: "서연", handle: "seoyeon.daily", initials: "SY", accentHex: "A7B9CE"),
            SocialUser(name: "민서", handle: "color.minseo", initials: "MS", accentHex: "FF765F"),
            SocialUser(name: "도윤", handle: "doyoon.fit", initials: "DY", accentHex: "C7F25B"),
            ]
        }
        return remoteSocialGraph.followers.map(SocialUser.init(snapshot:)).sorted { $0.name < $1.name }
    }

    @MainActor
    private func loadRemoteSocialGraph() async {
        do {
            remoteSocialGraph = try await SupabaseCommunityInteractionRepository.shared.fetchSocialGraph()
        } catch {
#if DEBUG
            print("원격 팔로우 목록 동기화 실패, 로컬 목록을 유지합니다: \(error.localizedDescription)")
#endif
        }
    }

    private var monthlyDiscoveryText: String {
        guard let interval = Calendar.current.dateInterval(of: .month, for: .now) else {
            return "착장을 기록하면 이번 달의 스타일을 발견할 수 있어요."
        }
        let ranked = garments
            .map { garment in
                (garment, garment.confirmedOutfitItems.filter {
                    guard let date = $0.outfit?.wornAt else { return false }
                    return interval.contains(date)
                }.count)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }

        guard let top = ranked.first else {
            return "아직 이번 달 착장이 없어요. 오늘의 룩부터 가볍게 남겨보세요."
        }
        return "이번 달에는 ‘\(top.0.name)’을 \(top.1)번 입었어요. 나의 취향이 데이터로 쌓이고 있어요."
    }
}

private enum SocialListKind: String, Identifiable {
    case followers
    case following

    var id: String { rawValue }
}

private struct SocialUser: Identifiable {
    let name: String
    let handle: String
    let initials: String
    let accentHex: String

    var id: String { handle }

    init(name: String, handle: String, initials: String, accentHex: String) {
        self.name = name
        self.handle = handle
        self.initials = initials
        self.accentHex = accentHex
    }

    init(snapshot: CommunitySocialUserSnapshot) {
        name = snapshot.name
        handle = snapshot.handle
        initials = snapshot.initials
        accentHex = snapshot.accentHex
    }
}

private struct SocialUserListView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let users: [SocialUser]

    var body: some View {
        NavigationStack {
            Group {
                if users.isEmpty {
                    ContentUnavailableView(
                        title == "팔로잉" ? "아직 팔로우한 사람이 없어요" : "아직 팔로워가 없어요",
                        systemImage: "person.2",
                        description: Text(title == "팔로잉" ? "피드에서 마음에 드는 스타일의 사용자를 팔로우해 보세요." : "착장을 공유하면 새로운 연결이 시작돼요.")
                    )
                } else {
                    List(users) { user in
                        HStack(spacing: 12) {
                            Text(user.initials)
                                .font(.caption.weight(.black))
                                .frame(width: 46, height: 46)
                                .background(Color(hex: user.accentHex), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name).fontWeight(.semibold)
                                Text("@\(user.handle)")
                                    .font(.caption)
                                    .foregroundStyle(WEARyTheme.secondaryInk)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("social.user.\(user.handle)")
                    }
                    .scrollContentBackground(.hidden)
                    .background(WEARyTheme.canvas)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}
