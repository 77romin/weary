import SwiftUI

struct RemoteSellerChatListView: View {
    @Environment(\.dismiss) private var dismiss
    let listing: MarketListing
    @State private var conversations: [MarketConversationSnapshot] = []
    @State private var selectedConversation: MarketConversationSnapshot?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, conversations.isEmpty {
                    ProgressView("채팅 불러오는 중…")
                } else if conversations.isEmpty {
                    ContentUnavailableView(
                        "아직 채팅이 없어요",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("구매 희망자가 메시지를 보내면 이곳에 표시됩니다.")
                    )
                } else {
                    List(conversations) { conversation in
                        Button {
                            selectedConversation = conversation
                        } label: {
                            HStack(spacing: 12) {
                                Text(conversation.buyerInitials)
                                    .font(.caption.weight(.black))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Color(hex: conversation.buyerAccentHex),
                                        in: Circle()
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(conversation.buyerName).fontWeight(.semibold)
                                        Spacer()
                                        if let date = conversation.lastMessageAt {
                                            Text(date, style: .relative)
                                                .font(.caption2)
                                                .foregroundStyle(WEARyTheme.secondaryInk)
                                        }
                                    }
                                    Text(conversation.latestMessage ?? "새 대화가 시작됐어요.")
                                        .font(.caption)
                                        .foregroundStyle(WEARyTheme.secondaryInk)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                    .background(WEARyTheme.canvas)
                }
            }
            .background(WEARyTheme.canvas)
            .navigationTitle("채팅 \(conversations.count)명")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .sheet(item: $selectedConversation) { conversation in
                RemoteMarketChatView(
                    listing: listing,
                    conversation: conversation,
                    counterpartName: conversation.buyerName
                )
            }
            .task { await runConversationList() }
            .refreshable { await refreshConversations() }
            .alert("채팅을 불러오지 못했어요", isPresented: marketChatErrorPresentation($loadError)) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(loadError ?? "다시 시도해 주세요.")
            }
        }
    }

    @MainActor
    private func refreshConversations() async {
        do {
            conversations = try await SupabaseMarketChatRepository.shared
                .fetchSellerConversations(listingID: listing.id)
            listing.chatCount = conversations.count
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func runConversationList() async {
        await refreshConversations()
        guard !Task.isCancelled else { return }
        do {
            let events = try await SupabaseMarketConversationRealtimeRepository.shared.events()
            for await _ in events {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }
                await refreshConversations()
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run { loadError = error.localizedDescription }
            }
        }
        await SupabaseMarketConversationRealtimeRepository.shared.stop()
    }
}

struct RemoteMarketChatView: View {
    @Environment(\.dismiss) private var dismiss
    let listing: MarketListing
    let counterpartName: String
    @State private var conversationID: UUID?
    @State private var messages: [MarketMessageSnapshot] = []
    @State private var currentUserID: UUID?
    @State private var input = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var chatError: String?

    init(
        listing: MarketListing,
        conversation: MarketConversationSnapshot? = nil,
        counterpartName: String
    ) {
        self.listing = listing
        self.counterpartName = counterpartName
        _conversationID = State(initialValue: conversation?.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                listingHeader
                Divider()
                messageArea
                composer
            }
            .background(WEARyTheme.canvas)
            .navigationTitle(counterpartName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .task { await prepareConversation() }
            .task(id: conversationID) { await runMessages() }
            .alert("채팅 요청 실패", isPresented: marketChatErrorPresentation($chatError)) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(chatError ?? "다시 시도해 주세요.")
            }
        }
    }

    private var listingHeader: some View {
        HStack(spacing: 12) {
            MarketChatThumbnail(listing: listing)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(listing.price.formatted(.currency(code: "KRW").precision(.fractionLength(0))))
                    .font(.caption.weight(.bold))
            }
            Spacer()
            Text(listing.status.rawValue)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(WEARyTheme.lime, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(WEARyTheme.surface)
    }

    @ViewBuilder
    private var messageArea: some View {
        if isLoading, messages.isEmpty {
            Spacer()
            ProgressView("대화 불러오는 중…")
            Spacer()
        } else if messages.isEmpty {
            ContentUnavailableView(
                "대화를 시작해 보세요",
                systemImage: "bubble.left",
                description: Text("거래 가능 여부와 만날 장소를 채팅으로 합의할 수 있어요.")
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    guard let lastID = messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("메시지", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button("전송") { Task { await sendMessage() } }
                .fontWeight(.bold)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding()
        .background(WEARyTheme.surface)
    }

    private func messageBubble(_ message: MarketMessageSnapshot) -> some View {
        let isMine = message.senderID == currentUserID
        return VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            Text(message.body)
                .font(.subheadline)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    isMine ? WEARyTheme.lime : WEARyTheme.surface,
                    in: RoundedRectangle(cornerRadius: 16)
                )
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    @MainActor
    private func prepareConversation() async {
        do {
            currentUserID = try await SupabaseMarketChatRepository.shared.currentUserID()
            if conversationID == nil {
                conversationID = try await SupabaseMarketChatRepository.shared
                    .findBuyerConversation(listingID: listing.id)
            }
            chatError = nil
        } catch {
            chatError = error.localizedDescription
        }
        if conversationID == nil { isLoading = false }
    }

    private func runMessages() async {
        guard let conversationID else { return }
        await refreshMessages(conversationID: conversationID)
        guard !Task.isCancelled else { return }
        do {
            let events = try await SupabaseMarketMessageRealtimeRepository.shared.events()
            for await _ in events {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { break }
                await refreshMessages(conversationID: conversationID)
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run { chatError = error.localizedDescription }
            }
        }
        await SupabaseMarketMessageRealtimeRepository.shared.stop()
    }

    @MainActor
    private func refreshMessages(conversationID: UUID) async {
        do {
            messages = try await SupabaseMarketChatRepository.shared
                .fetchMessages(conversationID: conversationID)
            chatError = nil
        } catch {
            chatError = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func sendMessage() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let activeConversationID: UUID
            if let conversationID {
                activeConversationID = conversationID
            } else {
                activeConversationID = try await SupabaseMarketChatRepository.shared
                    .getOrCreateBuyerConversation(listingID: listing.id)
                self.conversationID = activeConversationID
            }
            try await SupabaseMarketChatRepository.shared.sendMessage(
                conversationID: activeConversationID,
                body: input
            )
            input = ""
            await refreshMessages(conversationID: activeConversationID)
        } catch {
            chatError = error.localizedDescription
        }
    }
}

private struct MarketChatThumbnail: View {
    let listing: MarketListing

    var body: some View {
        ZStack {
            Color(hex: listing.accentHex).opacity(0.78)
            if let data = listing.galleryImages.first, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let data = listing.garmentCutoutImageDataSnapshot,
                      let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().padding(5)
            } else {
                Image(systemName: "hanger")
            }
        }
        .clipped()
    }
}

private func marketChatErrorPresentation(_ message: Binding<String?>) -> Binding<Bool> {
    Binding(
        get: { message.wrappedValue != nil },
        set: { if !$0 { message.wrappedValue = nil } }
    )
}
