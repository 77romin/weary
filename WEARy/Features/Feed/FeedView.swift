import SwiftData
import SwiftUI

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authentication: AuthenticationStore
    @Query(sort: \CommunityPost.createdAt, order: .reverse) private var posts: [CommunityPost]
    @AppStorage(SocialContentMode.storageKey) private var contentModeRaw = SocialContentMode.live.rawValue
    @State private var selectedTopic = "전체"
    @State private var showingComposer = false
    @State private var isRefreshing = false
    @State private var refreshCount = 0
    @State private var remoteSyncError: String?
    @State private var remoteCursor: CommunityFeedCursor?
    @State private var hasMoreRemotePosts = false
    @State private var isLoadingMore = false
    @State private var loadedRemoteLimit = 15

    private let topics = ["전체", "오늘의 룩", "미니멀", "빈티지", "출근 룩", "컬러 포인트"]
    private let feedTopAnchor = "feed.top"
    private let remotePageSize = 15

    private var contentMode: SocialContentMode {
        SocialContentMode(rawValue: contentModeRaw) ?? .live
    }

    private var visiblePosts: [CommunityPost] {
        switch contentMode {
        case .live: posts.filter { $0.isSyncedFromServer == true }
        case .demo: posts.filter { $0.isSyncedFromServer != true }
        }
    }

    private var filteredPosts: [CommunityPost] {
        guard selectedTopic != "전체" else { return visiblePosts }
        return visiblePosts.filter { postMatchesTopic($0, topic: selectedTopic) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    WEARyTheme.canvas.ignoresSafeArea()
                    if visiblePosts.isEmpty {
                        ContentUnavailableView(
                            contentMode == .live ? "아직 서버 게시물이 없어요" : "데모 게시물이 없어요",
                            systemImage: contentMode == .live ? "network" : "sparkles",
                            description: Text(contentMode == .live
                                ? "친구와 첫 실제 스타일을 공유해 보세요. 데모 데이터는 MY에서 따로 볼 수 있어요."
                                : "MY에서 데모 데이터를 초기화하면 발표용 샘플을 다시 만들 수 있어요.")
                        )
                    } else {
                        ScrollView {
                            Color.clear
                            .frame(height: 1)
                            .id(feedTopAnchor)

                            LazyVStack(spacing: 18) {
                                contentModeBadge
                                styleTopics
                                if filteredPosts.isEmpty {
                                    ContentUnavailableView(
                                        "아직 \(selectedTopic) 게시물이 없어요",
                                        systemImage: "sparkles",
                                        description: Text("내 착장으로 이 스타일의 첫 게시물을 작성해 보세요.")
                                    )
                                    .padding(.top, 50)
                                } else {
                                    ForEach(filteredPosts) { post in
                                        NavigationLink(value: post) {
                                            CommunityPostCard(post: post)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                if hasMoreRemotePosts {
                                    ProgressView("이전 스타일 불러오는 중…")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 18)
                                        .task { await loadMoreRemotePosts() }
                                        .accessibilityIdentifier("feed.loadMore")
                                }
                            }
                            .padding(18)
                        }
                        .refreshable {
                            await refreshFeed()
                        }
                        .accessibilityIdentifier("feed.scrollView")
                    }
                }
                .navigationTitle("!WEARy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Button {
                            handleLogoTap(using: proxy)
                        } label: {
                            Text("!WEARy")
                                .font(.system(size: 27, weight: .black, design: .rounded))
                                .tracking(-1)
                            .foregroundStyle(WEARyTheme.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("피드 최상단으로 이동")
                        .accessibilityValue("새로고침 \(refreshCount)회")
                        .accessibilityIdentifier("feed.logo")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showingComposer = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("피드 게시물 작성")
                        .disabled(authentication.isSocialWriteRestricted)
                        .accessibilityIdentifier("feed.compose")
                        Image(systemName: "bell")
                    }
                }
            }
            .navigationDestination(for: CommunityPost.self) { post in
                CommunityPostDetailView(post: post)
            }
            .sheet(isPresented: $showingComposer) {
                CreateCommunityPostView()
            }
            .task(id: contentModeRaw) {
                if contentMode == .live {
                    await runRemoteFeed()
                } else {
                    hasMoreRemotePosts = false
                    remoteCursor = nil
                    await SupabaseCommunityFeedRealtimeRepository.shared.stop()
                }
            }
        }
    }

    private func handleLogoTap(using proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.38)) {
            proxy.scrollTo(feedTopAnchor, anchor: .top)
        }
    }

    @MainActor
    private func refreshFeed() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshCount += 1
        if contentMode == .live {
            await refreshRemoteWindow()
        } else {
            SampleDataSeeder.seedIfNeeded(in: modelContext)
        }
        isRefreshing = false
    }

    private var contentModeBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: contentMode == .live ? "network" : "sparkles")
            Text(contentMode.title)
                .fontWeight(.bold)
            Text(contentMode.description)
                .foregroundStyle(WEARyTheme.secondaryInk)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .accessibilityIdentifier("feed.contentMode")
    }

    @MainActor
    private func refreshRemoteWindow() async {
        do {
            let page = try await SupabaseCommunityFeedRepository.shared.fetchPage(
                before: nil,
                limit: loadedRemoteLimit
            )
            try CommunityFeedCacheStore.replaceRemoteWindow(with: page.posts, in: modelContext)
            remoteCursor = page.nextCursor
            hasMoreRemotePosts = page.hasMore
            remoteSyncError = nil
#if DEBUG
            print("원격 피드 동기화 완료: \(page.posts.count)개")
#endif
        } catch {
            remoteSyncError = error.localizedDescription
#if DEBUG
            print("원격 피드 동기화 실패, 로컬 피드를 유지합니다: \(error.localizedDescription)")
#endif
        }
    }

    @MainActor
    private func loadMoreRemotePosts() async {
        guard hasMoreRemotePosts, !isLoadingMore, let remoteCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await SupabaseCommunityFeedRepository.shared.fetchPage(
                before: remoteCursor,
                limit: remotePageSize
            )
            try CommunityFeedCacheStore.mergeRemotePage(page.posts, in: modelContext)
            self.remoteCursor = page.nextCursor
            hasMoreRemotePosts = page.hasMore
            loadedRemoteLimit += page.posts.count
            remoteSyncError = nil
        } catch {
            remoteSyncError = error.localizedDescription
#if DEBUG
            print("원격 피드 다음 페이지 로드 실패: \(error.localizedDescription)")
#endif
        }
    }

    private func runRemoteFeed() async {
        await refreshRemoteWindow()
        guard !Task.isCancelled else { return }

        do {
            let events = try await SupabaseCommunityFeedRealtimeRepository.shared.events()
            for await _ in events {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { break }
                await refreshRemoteWindow()
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run { remoteSyncError = error.localizedDescription }
#if DEBUG
            print("피드 Realtime 구독 실패: \(error.localizedDescription)")
#endif
        }

        await SupabaseCommunityFeedRealtimeRepository.shared.stop()
    }

    private var styleTopics: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    Button {
                        withAnimation(.snappy) { selectedTopic = topic }
                    } label: {
                        Text(topic)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background(selectedTopic == topic ? WEARyTheme.ink : WEARyTheme.surface, in: Capsule())
                            .foregroundStyle(selectedTopic == topic ? WEARyTheme.surface : WEARyTheme.ink)
                            .lightTextOutline(isActive: selectedTopic == topic)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feed.topic.\(topic)")
                }
            }
        }
    }

    private func postMatchesTopic(_ post: CommunityPost, topic: String) -> Bool {
        let terms: [String]
        switch topic {
        case "오늘의 룩": terms = ["오늘의룩"]
        case "미니멀": terms = ["미니멀"]
        case "빈티지": terms = ["빈티지"]
        case "출근 룩": terms = ["출근룩", "출근"]
        case "컬러 포인트": terms = ["컬러포인트", "포인트", "색"]
        default: return true
        }
        let searchable = (post.tags.joined() + post.caption).replacingOccurrences(of: " ", with: "")
        return terms.contains { searchable.localizedCaseInsensitiveContains($0) }
    }
}

private struct CommunityPostCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allPosts: [CommunityPost]
    @Bindable var post: CommunityPost
    @State private var isUpdatingLike = false
    @State private var isUpdatingBookmark = false
    @State private var isUpdatingFollow = false
    @State private var interactionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            authorHeader
            CommunityLookArtwork(post: post)
                .frame(height: 390)
                .clipShape(RoundedRectangle(cornerRadius: WEARyTheme.cornerRadius))
            reactionBar
            Text(post.caption)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WEARyTheme.ink)
                .lineLimit(2)
            Text(post.tags.map { "#\($0)" }.joined(separator: "  "))
                .font(.caption)
                .foregroundStyle(WEARyTheme.coral)
        }
        .padding(16)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .alert("요청을 완료하지 못했어요", isPresented: Binding(
            get: { interactionError != nil },
            set: { if !$0 { interactionError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(interactionError ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private var authorHeader: some View {
        HStack {
            Text(post.authorInitials)
                .font(.caption.weight(.black))
                .frame(width: 40, height: 40)
                .background(Color(hex: post.accentHex), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(post.authorName).font(.subheadline.weight(.bold))
                Text("@\(post.authorHandle) · \(post.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(WEARyTheme.secondaryInk)
            }
            Spacer()
            if post.authorHandle != "my.weary" {
                Button(post.isFollowing ? "팔로잉" : "팔로우") {
                    toggleFollowing()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.bordered)
                .tint(WEARyTheme.ink)
                .disabled(isUpdatingFollow)
                .accessibilityIdentifier("follow.\(post.authorHandle)")
            }
        }
    }

    private var reactionBar: some View {
        HStack(spacing: 18) {
            Button {
                toggleLike()
            } label: {
                Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(post.isLiked ? WEARyTheme.coral : WEARyTheme.ink)
            }
            .disabled(isUpdatingLike)
            Label("\(post.comments.count)", systemImage: "bubble")
            Spacer()
            Button {
                toggleBookmark()
            } label: {
                Image(systemName: post.isSaved ? "bookmark.fill" : "bookmark")
            }
            .disabled(isUpdatingBookmark)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(WEARyTheme.ink)
        .buttonStyle(.plain)
    }

    private func toggleLike() {
        let previousValue = post.isLiked
        let desiredValue = !previousValue
        post.isLiked = desiredValue
        post.likeCount = max(0, post.likeCount + (desiredValue ? 1 : -1))
        try? modelContext.save()

        guard post.isSyncedFromServer == true else { return }
        isUpdatingLike = true
        Task { @MainActor in
            do {
                try await SupabaseCommunityInteractionRepository.shared.setLike(
                    postID: post.id,
                    isLiked: desiredValue
                )
            } catch {
                post.isLiked = previousValue
                post.likeCount = max(0, post.likeCount + (desiredValue ? -1 : 1))
                try? modelContext.save()
                interactionError = error.localizedDescription
            }
            isUpdatingLike = false
        }
    }

    private func toggleBookmark() {
        let previousValue = post.isSaved
        let desiredValue = !previousValue
        post.isSaved = desiredValue
        try? modelContext.save()

        guard post.isSyncedFromServer == true else { return }
        isUpdatingBookmark = true
        Task { @MainActor in
            do {
                try await SupabaseCommunityInteractionRepository.shared.setBookmark(
                    postID: post.id,
                    isSaved: desiredValue
                )
            } catch {
                post.isSaved = previousValue
                try? modelContext.save()
                interactionError = error.localizedDescription
            }
            isUpdatingBookmark = false
        }
    }

    private func toggleFollowing() {
        let previousValue = post.isFollowing
        let desiredValue = !previousValue
        applyFollowing(desiredValue)
        try? modelContext.save()

        guard post.isSyncedFromServer == true, let authorID = post.serverAuthorID else { return }
        isUpdatingFollow = true
        Task { @MainActor in
            do {
                try await SupabaseCommunityInteractionRepository.shared.setFollowing(
                    authorID: authorID,
                    isFollowing: desiredValue
                )
            } catch {
                applyFollowing(previousValue)
                try? modelContext.save()
                interactionError = error.localizedDescription
            }
            isUpdatingFollow = false
        }
    }

    private func applyFollowing(_ value: Bool) {
        for authorPost in allPosts {
            if let authorID = post.serverAuthorID {
                guard authorPost.serverAuthorID == authorID else { continue }
            } else {
                guard authorPost.authorHandle == post.authorHandle else { continue }
            }
            authorPost.isFollowing = value
        }
    }
}

private struct CreateCommunityPostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authentication: AuthenticationStore
    @Query(sort: \Outfit.wornAt, order: .reverse) private var outfits: [Outfit]
    @State private var selectedOutfitID: UUID?
    @State private var caption = ""
    @State private var tagsText = "오늘의룩"
    @State private var orderedItemIDs: [UUID] = []
    @State private var itemEditMode: EditMode = .active
    @State private var isPublishing = false
    @State private var publishError: String?

    private var availableOutfits: [Outfit] {
        outfits.filter { $0.isConfirmed && !$0.isPublished && $0.photoData != nil }
    }

    private var selectedOutfit: Outfit? {
        availableOutfits.first { $0.id == selectedOutfitID }
    }

    private var selectedOrderedItems: [OutfitItem] {
        guard let selectedOutfit else { return [] }
        let itemsByID = Dictionary(uniqueKeysWithValues: selectedOutfit.items.map { ($0.id, $0) })
        let explicitlyOrdered = orderedItemIDs.compactMap { itemsByID[$0] }
        let includedIDs = Set(explicitlyOrdered.map(\.id))
        return explicitlyOrdered + selectedOutfit.orderedItems.filter { !includedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("공개할 착장") {
                    if availableOutfits.isEmpty {
                        ContentUnavailableView(
                            "게시할 착장이 없어요",
                            systemImage: "camera",
                            description: Text("기록 탭에서 새 착장 사진을 남기거나 이미 게시한 착장을 확인해 주세요.")
                        )
                    } else {
                        Picker("착장 선택", selection: $selectedOutfitID) {
                            ForEach(availableOutfits) { outfit in
                                Text(outfit.wornAt.formatted(date: .abbreviated, time: .omitted))
                                    .tag(Optional(outfit.id))
                            }
                        }
                        if let selectedOutfit {
                            OutfitComposerPreview(outfit: selectedOutfit)
                        }
                    }
                }

                if selectedOutfit != nil {
                    Section {
                        ForEach(selectedOrderedItems) { item in
                            if let garment = item.garment {
                                HStack(spacing: 12) {
                                    GarmentCutoutThumbnail(garment: garment)
                                        .frame(width: 48, height: 48)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(garment.name).font(.subheadline.weight(.semibold))
                                        Text(garment.category.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(WEARyTheme.secondaryInk)
                                    }
                                }
                            }
                        }
                        .onMove(perform: moveItems)
                    } header: {
                        Text("이 룩의 아이템 순서")
                    } footer: {
                        Text("기본은 모자–아우터–상의–원피스–하의–신발–가방–액세서리 순서예요. 오른쪽 핸들을 드래그해 바꿀 수 있어요.")
                    }
                    .accessibilityIdentifier("feed.itemOrder")
                }

                Section("게시물") {
                    TextField("오늘의 룩을 소개해 주세요", text: $caption, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("태그를 쉼표로 구분해 주세요", text: $tagsText)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Text("선택한 착장 사진과 옷 정보만 커뮤니티 서버에 공개됩니다. 구매 가격과 비공개 옷장 정보는 업로드하지 않아요.")
                        .font(.caption)
                        .foregroundStyle(WEARyTheme.secondaryInk)
                }
            }
            .scrollContentBackground(.hidden)
            .background(WEARyTheme.canvas)
            .navigationTitle("피드 작성")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: publish) {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("게시")
                        }
                    }
                        .fontWeight(.bold)
                        .disabled(
                            isPublishing
                                || selectedOutfit == nil
                                || caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityIdentifier("feed.publish")
                }
            }
            .onAppear {
                if selectedOutfitID == nil { selectedOutfitID = availableOutfits.first?.id }
                resetItemOrder()
            }
            .onChange(of: selectedOutfitID) {
                resetItemOrder()
            }
            .environment(\.editMode, $itemEditMode)
            .interactiveDismissDisabled(isPublishing)
            .alert("게시하지 못했어요", isPresented: Binding(
                get: { publishError != nil },
                set: { if !$0 { publishError = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(publishError ?? "잠시 후 다시 시도해 주세요.")
            }
        }
    }

    private func publish() {
        guard let selectedOutfit, let photoData = selectedOutfit.photoData else { return }
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }
        let normalizedTags = tags.isEmpty ? ["오늘의룩"] : tags
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedOutfit.applyItemOrder(orderedItemIDs)
        try? modelContext.save()

        let draft = CommunityPostPublishDraft(
            sourceOutfitID: selectedOutfit.id,
            caption: trimmedCaption,
            tags: normalizedTags,
            photoData: photoData,
            items: selectedOrderedItems.compactMap { item in
                guard let garment = item.garment else { return nil }
                return CommunityPostPublishItem(
                    sourceGarmentID: garment.id,
                    name: garment.name,
                    brand: garment.brand,
                    categoryRaw: garment.categoryRaw,
                    size: garment.size,
                    colorHex: garment.colorHex,
                    imageData: garment.cutoutImageData
                )
            }
        )

        isPublishing = true
        publishError = nil

        Task { @MainActor in
            do {
                let postID = try await SupabaseCommunityPostPublisher.shared.publish(draft)
                selectedOutfit.isPublished = true
                let publishedID = postID
                var descriptor = FetchDescriptor<CommunityPost>(
                    predicate: #Predicate { $0.id == publishedID }
                )
                descriptor.fetchLimit = 1
                if let cachedPost = try? modelContext.fetch(descriptor).first {
                    cachedPost.authorName = authentication.displayName
                    cachedPost.authorHandle = "my.weary"
                    cachedPost.authorInitials = AuthenticationStore.initials(for: authentication.displayName)
                    cachedPost.caption = trimmedCaption
                    cachedPost.tags = normalizedTags
                    cachedPost.captureSnapshot(from: selectedOutfit)
                    cachedPost.isSyncedFromServer = true
                } else {
                    modelContext.insert(CommunityPost(
                        id: postID,
                        authorName: authentication.displayName,
                        authorHandle: "my.weary",
                        authorInitials: AuthenticationStore.initials(for: authentication.displayName),
                        caption: trimmedCaption,
                        tags: normalizedTags,
                        accentHex: "C7F25B",
                        outfit: selectedOutfit,
                        isSyncedFromServer: true
                    ))
                }
                do {
                    try modelContext.save()
                } catch {
#if DEBUG
                    print("게시 성공 후 로컬 피드 캐시 저장 실패: \(error.localizedDescription)")
#endif
                }
                isPublishing = false
                dismiss()
            } catch {
                isPublishing = false
                publishError = error.localizedDescription
            }
        }
    }

    private func resetItemOrder() {
        orderedItemIDs = selectedOutfit?.orderedItems.map(\.id) ?? []
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        orderedItemIDs.move(fromOffsets: source, toOffset: destination)
    }
}

private struct OutfitComposerPreview: View {
    let outfit: Outfit

    var body: some View {
        Group {
            if let data = outfit.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ContentUnavailableView("착장 사진 없음", systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .clipped()
    }
}

struct CommunityLookArtwork: View {
    let post: CommunityPost

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: post.accentHex), Color(hex: post.accentHex).opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let data = post.outfitPhotoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityIdentifier("feed.outfitPhoto")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 54, weight: .light))
                    Text("착장 사진이 없어요")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(WEARyTheme.ink.opacity(0.7))
            }
        }
        .clipped()
    }
}

private struct CommunityPostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var post: CommunityPost
    @State private var newComment = ""
    @State private var isSubmittingComment = false
    @State private var commentError: String?
    @State private var showingReport = false
    @State private var showingBlockConfirmation = false
    @State private var safetyMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CommunityLookArtwork(post: post).frame(height: 480).clipped()
                VStack(alignment: .leading, spacing: 16) {
                    Text(post.caption).font(.body.weight(.medium))
                    Text(post.tags.map { "#\($0)" }.joined(separator: "  "))
                        .font(.subheadline).foregroundStyle(WEARyTheme.coral)
                    Divider()
                    outfitItems
                    Divider()
                    commentsSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(WEARyTheme.canvas)
        .navigationTitle(post.authorName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if post.isSyncedFromServer == true,
               post.authorHandle != "my.weary",
               post.serverAuthorID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingReport = true
                        } label: {
                            Label("게시물 신고", systemImage: "exclamationmark.bubble")
                        }
                        Button(role: .destructive) {
                            showingBlockConfirmation = true
                        } label: {
                            Label("작성자 차단", systemImage: "person.crop.circle.badge.xmark")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("feed.safetyMenu")
                }
            }
        }
        .sheet(isPresented: $showingReport) {
            ContentReportSheet(target: .post, targetID: post.id) {
                safetyMessage = "신고가 접수되었습니다."
            }
        }
        .confirmationDialog("이 사용자를 차단할까요?", isPresented: $showingBlockConfirmation) {
            Button("차단", role: .destructive) {
                Task { await blockAuthor() }
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("차단하면 이 사용자의 피드와 매물이 더 이상 표시되지 않습니다.")
        }
        .alert("댓글을 등록하지 못했어요", isPresented: Binding(
            get: { commentError != nil },
            set: { if !$0 { commentError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(commentError ?? "잠시 후 다시 시도해 주세요.")
        }
        .alert("알림", isPresented: Binding(
            get: { safetyMessage != nil },
            set: { if !$0 { safetyMessage = nil } }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(safetyMessage ?? "")
        }
    }

    private var outfitItems: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이 룩의 아이템").font(.headline)
            ForEach(post.outfitItems) { garment in
                HStack(spacing: 12) {
                    CommunityGarmentSnapshotThumbnail(garment: garment).frame(width: 46, height: 46)
                    VStack(alignment: .leading) {
                        Text(garment.name).font(.subheadline.weight(.semibold))
                        Text("\(garment.brand) · \(garment.size)")
                            .font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
                    }
                }
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("댓글 \(post.comments.count)").font(.headline)
            ForEach(Array(post.comments.enumerated()), id: \.offset) { _, comment in
                Text(comment)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                TextField("댓글을 남겨보세요", text: $newComment)
                    .textFieldStyle(.roundedBorder)
                Button {
                    submitComment()
                } label: {
                    if isSubmittingComment {
                        ProgressView()
                    } else {
                        Text("등록")
                    }
                }
                .fontWeight(.bold)
                .disabled(
                    isSubmittingComment
                        || newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private func submitComment() {
        let body = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        guard post.isSyncedFromServer == true else {
            post.appendComment("나: \(body)")
            newComment = ""
            try? modelContext.save()
            return
        }

        isSubmittingComment = true
        commentError = nil
        Task { @MainActor in
            do {
                try await SupabaseCommunityInteractionRepository.shared.addComment(
                    postID: post.id,
                    body: body
                )
                post.appendComment("나: \(body)")
                newComment = ""
                try? modelContext.save()
            } catch {
                commentError = error.localizedDescription
            }
            isSubmittingComment = false
        }
    }

    @MainActor
    private func blockAuthor() async {
        guard let authorID = post.serverAuthorID else { return }
        do {
            try await SupabaseContentSafetyRepository.shared.setBlocked(
                userID: authorID,
                isBlocked: true
            )
            dismiss()
        } catch {
            safetyMessage = error.localizedDescription
        }
    }
}

private struct CommunityGarmentSnapshotThumbnail: View {
    let garment: CommunityGarmentSnapshot

    var body: some View {
        Group {
            if let data = garment.cutoutImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: garment.category.symbol)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(WEARyTheme.ink.opacity(0.82))
                    .padding(3)
                    .background(Color(hex: garment.colorHex).opacity(0.66), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .accessibilityLabel(garment.name)
    }
}
