import SwiftData
import SwiftUI

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CommunityPost.createdAt, order: .reverse) private var posts: [CommunityPost]
    @State private var selectedTopic = "전체"
    @State private var showingComposer = false
    @State private var isAtFeedTop = true
    @State private var isRefreshing = false
    @State private var refreshCount = 0

    private let topics = ["전체", "오늘의 룩", "미니멀", "빈티지", "출근 룩", "컬러 포인트"]
    private let feedTopAnchor = "feed.top"

    private var filteredPosts: [CommunityPost] {
        guard selectedTopic != "전체" else { return posts }
        return posts.filter { postMatchesTopic($0, topic: selectedTopic) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    WEARyTheme.canvas.ignoresSafeArea()
                    if posts.isEmpty {
                        ContentUnavailableView(
                            "첫 스타일을 기다리고 있어요",
                            systemImage: "rectangle.stack.badge.plus",
                            description: Text("착장을 기록하거나 + 버튼에서 첫 게시물을 작성해 보세요.")
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 18) {
                                Color.clear
                                    .frame(height: 0)
                                    .id(feedTopAnchor)
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
                            }
                            .padding(18)
                        }
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.y + geometry.contentInsets.top <= 12
                        } action: { _, isAtTop in
                            isAtFeedTop = isAtTop
                        }
                    }
                }
                .navigationTitle("!WEARy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Button {
                            handleLogoTap(using: proxy)
                        } label: {
                            HStack(spacing: 8) {
                                Text("!WEARy")
                                    .font(.system(size: 27, weight: .black, design: .rounded))
                                    .tracking(-1)
                                if isRefreshing {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .foregroundStyle(WEARyTheme.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isRefreshing ? "피드 최신화 중" : "피드 처음으로")
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
        }
    }

    private func handleLogoTap(using proxy: ScrollViewProxy) {
        if isAtFeedTop {
            refreshFeed()
        } else {
            isAtFeedTop = true
            withAnimation(.snappy) {
                proxy.scrollTo(feedTopAnchor, anchor: .top)
            }
        }
    }

    private func refreshFeed() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshCount += 1
        Task { @MainActor in
            SampleDataSeeder.seedIfNeeded(in: modelContext)
            try? await Task.sleep(for: .milliseconds(650))
            isRefreshing = false
        }
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
            Button(post.isFollowing ? "팔로잉" : "팔로우") {
                let newValue = !post.isFollowing
                for authorPost in allPosts where authorPost.authorHandle == post.authorHandle {
                    authorPost.isFollowing = newValue
                }
                try? modelContext.save()
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.bordered)
            .tint(WEARyTheme.ink)
            .accessibilityIdentifier("follow.\(post.authorHandle)")
        }
    }

    private var reactionBar: some View {
        HStack(spacing: 18) {
            Button {
                post.isLiked.toggle()
                post.likeCount += post.isLiked ? 1 : -1
                try? modelContext.save()
            } label: {
                Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(post.isLiked ? WEARyTheme.coral : WEARyTheme.ink)
            }
            Label("\(post.comments.count)", systemImage: "bubble")
            Spacer()
            Button {
                post.isSaved.toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: post.isSaved ? "bookmark.fill" : "bookmark")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(WEARyTheme.ink)
        .buttonStyle(.plain)
    }
}

private struct CreateCommunityPostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Outfit.wornAt, order: .reverse) private var outfits: [Outfit]
    @State private var selectedOutfitID: UUID?
    @State private var caption = ""
    @State private var tagsText = "오늘의룩"
    @State private var orderedItemIDs: [UUID] = []
    @State private var itemEditMode: EditMode = .active

    private var availableOutfits: [Outfit] {
        outfits.filter { $0.isConfirmed && $0.photoData != nil }
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
                            "사진이 있는 착장이 없어요",
                            systemImage: "camera",
                            description: Text("기록 탭에서 실제 착장 사진을 먼저 남겨주세요.")
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
                    Text("공개한 착장과 옷 정보는 로컬 Mock 피드에만 표시됩니다.")
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("게시", action: publish)
                        .fontWeight(.bold)
                        .disabled(selectedOutfit == nil || caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        }
    }

    private func publish() {
        guard let selectedOutfit else { return }
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }
        selectedOutfit.applyItemOrder(orderedItemIDs)
        selectedOutfit.isPublished = true
        modelContext.insert(CommunityPost(
            authorName: "나",
            authorHandle: "my.weary",
            authorInitials: "ME",
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags.isEmpty ? ["오늘의룩"] : tags,
            accentHex: "C7F25B",
            outfit: selectedOutfit
        ))
        try? modelContext.save()
        dismiss()
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
            if let data = post.outfit?.photoData, let image = UIImage(data: data) {
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
    @Environment(\.modelContext) private var modelContext
    @Bindable var post: CommunityPost
    @State private var newComment = ""

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
    }

    private var outfitItems: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이 룩의 아이템").font(.headline)
            ForEach(post.outfit?.orderedItems ?? []) { item in
                if let garment = item.garment {
                    HStack(spacing: 12) {
                        GarmentCutoutThumbnail(garment: garment).frame(width: 46, height: 46)
                        VStack(alignment: .leading) {
                            Text(garment.name).font(.subheadline.weight(.semibold))
                            Text("\(garment.brand) · \(garment.size)")
                                .font(.caption).foregroundStyle(WEARyTheme.secondaryInk)
                        }
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
                Button("등록") {
                    post.appendComment("나: \(newComment)")
                    newComment = ""
                    try? modelContext.save()
                }
                .fontWeight(.bold)
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
