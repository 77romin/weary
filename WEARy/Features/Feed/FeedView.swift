import SwiftData
import SwiftUI

struct FeedView: View {
    @Query(sort: \CommunityPost.createdAt, order: .reverse) private var posts: [CommunityPost]

    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.canvas.ignoresSafeArea()
                if posts.isEmpty {
                    ContentUnavailableView(
                        "첫 스타일을 기다리고 있어요",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("착장을 기록하고 커뮤니티에 공유해 보세요.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            styleTopics
                            ForEach(posts) { post in
                                NavigationLink(value: post) {
                                    CommunityPostCard(post: post)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("!WEARy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "bell")
                }
            }
            .navigationDestination(for: CommunityPost.self) { post in
                CommunityPostDetailView(post: post)
            }
        }
    }

    private var styleTopics: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["오늘의 룩", "미니멀", "빈티지", "출근 룩", "컬러 포인트"], id: \.self) { topic in
                    Text(topic)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(topic == "오늘의 룩" ? WEARyTheme.ink : WEARyTheme.surface, in: Capsule())
                        .foregroundStyle(topic == "오늘의 룩" ? WEARyTheme.surface : WEARyTheme.ink)
                        .lightTextOutline(isActive: topic == "오늘의 룩")
                }
            }
        }
    }
}

private struct CommunityPostCard: View {
    @Environment(\.modelContext) private var modelContext
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
                post.isFollowing.toggle()
                try? modelContext.save()
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.bordered)
            .tint(WEARyTheme.ink)
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

struct CommunityLookArtwork: View {
    let post: CommunityPost

    private var garments: [Garment] {
        post.outfit?.items.compactMap(\.garment) ?? []
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: post.accentHex), Color(hex: post.accentHex).opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let data = post.outfit?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                VStack(spacing: -8) {
                    ForEach(garments.prefix(5)) { garment in
                        GarmentCutoutThumbnail(garment: garment)
                            .frame(width: 145, height: 85)
                    }
                }
                .padding(.vertical, 18)
            }
            VStack {
                Spacer()
                HStack {
                    Text("\(garments.count) ITEMS")
                        .font(.caption2.weight(.black)).tracking(1.2)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(14)
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
            ForEach(post.outfit?.items.compactMap(\.garment) ?? []) { garment in
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
