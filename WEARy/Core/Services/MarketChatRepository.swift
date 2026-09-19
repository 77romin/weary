import Foundation
import Supabase

struct MarketConversationSnapshot: Identifiable, Sendable {
    let id: UUID
    let listingID: UUID
    let buyerID: UUID
    let buyerName: String
    let buyerHandle: String
    let buyerInitials: String
    let buyerAccentHex: String
    let latestMessage: String?
    let lastMessageAt: Date?
}

struct MarketMessageSnapshot: Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date
}

enum MarketChatWriteStatus: String, Decodable, Sendable {
    case allowed
    case selfSanctioned = "self_sanctioned"
    case counterpartSanctioned = "counterpart_sanctioned"
    case blockedBySelf = "blocked_by_self"
    case blockedByCounterpart = "blocked_by_counterpart"
    case notParticipant = "not_participant"
    case notAuthenticated = "not_authenticated"

    var notice: String? {
        switch self {
        case .allowed:
            nil
        case .selfSanctioned:
            "정책 위반으로 채팅 이용이 제한되었습니다."
        case .counterpartSanctioned:
            "이 사용자는 정책위반으로 차단된 사용자입니다."
        case .blockedBySelf:
            "차단한 사용자와는 메시지를 주고받을 수 없습니다."
        case .blockedByCounterpart:
            "이 사용자와는 메시지를 주고받을 수 없습니다."
        case .notParticipant, .notAuthenticated:
            "현재 이 대화에서 메시지를 보낼 수 없습니다."
        }
    }
}

actor SupabaseMarketChatRepository {
    static let shared = SupabaseMarketChatRepository()

    func findBuyerConversation(listingID: UUID) async throws -> UUID? {
        let (client, userID) = try await authenticatedContext()
        let conversations: [RemoteMarketConversation] = try await client
            .from("market_conversations")
            .select("id,listing_id,buyer_id,created_at,last_message_at")
            .eq("listing_id", value: listingID.uuidString)
            .eq("buyer_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return conversations.first?.id
    }

    func getOrCreateBuyerConversation(listingID: UUID) async throws -> UUID {
        let (client, _) = try await authenticatedContext()
        let conversation: RemoteMarketConversation = try await client
            .rpc(
                "get_or_create_market_conversation",
                params: MarketConversationParameters(listingID: listingID)
            )
            .single()
            .execute()
            .value
        return conversation.id
    }

    func fetchSellerConversations(listingID: UUID) async throws -> [MarketConversationSnapshot] {
        let (client, _) = try await authenticatedContext()
        let conversations: [RemoteSellerMarketConversation] = try await client
            .from("market_conversations")
            .select(
                "id,listing_id,buyer_id,created_at,last_message_at,buyer:profiles!market_conversations_buyer_id_fkey(display_name,handle,avatar_initials,accent_hex)"
            )
            .eq("listing_id", value: listingID.uuidString)
            .order("last_message_at", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value

        let latestMessages = try await latestMessagesByConversation(
            conversations.map(\.id),
            client: client
        )
        return conversations.map { conversation in
            MarketConversationSnapshot(
                id: conversation.id,
                listingID: conversation.listingID,
                buyerID: conversation.buyerID,
                buyerName: conversation.buyer.displayName,
                buyerHandle: conversation.buyer.handle ?? "weary",
                buyerInitials: conversation.buyer.avatarInitials,
                buyerAccentHex: conversation.buyer.accentHex,
                latestMessage: latestMessages[conversation.id]?.body,
                lastMessageAt: conversation.lastMessageAt
            )
        }
    }

    func fetchMessages(conversationID: UUID) async throws -> [MarketMessageSnapshot] {
        let (client, _) = try await authenticatedContext()
        let messages: [RemoteMarketMessage] = try await client
            .from("market_messages")
            .select("id,conversation_id,sender_id,body,created_at")
            .eq("conversation_id", value: conversationID.uuidString)
            .order("created_at", ascending: true)
            .order("id", ascending: true)
            .limit(300)
            .execute()
            .value
        return messages.map(\.snapshot)
    }

    func sendMessage(conversationID: UUID, body: String) async throws {
        let (client, userID) = try await authenticatedContext()
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { throw MarketChatError.emptyMessage }
        guard trimmedBody.count <= 2_000 else { throw MarketChatError.messageTooLong }

        try await client
            .from("market_messages")
            .insert(MarketMessageInsert(
                id: UUID(),
                conversationID: conversationID,
                senderID: userID,
                body: trimmedBody
            ))
            .execute()
    }

    func fetchWriteStatus(
        listingID: UUID,
        conversationID: UUID?
    ) async throws -> MarketChatWriteStatus {
        let (client, _) = try await authenticatedContext()
        return try await client
            .rpc(
                "get_market_chat_write_status",
                params: MarketChatWriteStatusParameters(
                    listingID: listingID,
                    conversationID: conversationID
                )
            )
            .execute()
            .value
    }

    func currentUserID() async throws -> UUID {
        let (_, userID) = try await authenticatedContext()
        return userID
    }

    private func latestMessagesByConversation(
        _ conversationIDs: [UUID],
        client: SupabaseClient
    ) async throws -> [UUID: RemoteMarketMessage] {
        guard !conversationIDs.isEmpty else { return [:] }
        let messages: [RemoteMarketMessage] = try await client
            .from("market_messages")
            .select("id,conversation_id,sender_id,body,created_at")
            .in("conversation_id", values: conversationIDs.map(\.uuidString))
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .execute()
            .value

        var result: [UUID: RemoteMarketMessage] = [:]
        for message in messages where result[message.conversationID] == nil {
            result[message.conversationID] = message
        }
        return result
    }

    private func authenticatedContext() async throws -> (SupabaseClient, UUID) {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        return (client, try await SupabaseSessionManager.shared.authenticatedUserID())
    }
}

actor SupabaseMarketConversationRealtimeRepository {
    static let shared = SupabaseMarketConversationRealtimeRepository()

    private var channels: [RealtimeChannelV2] = []
    private var subscriptions: [RealtimeSubscription] = []
    private var continuation: AsyncStream<Void>.Continuation?

    func events() async throws -> AsyncStream<Void> {
        try await makeEvents(channelPrefix: "market-conversations", tables: [
            "market_conversations",
            "market_messages",
            "profiles",
        ])
    }

    private func makeEvents(
        channelPrefix: String,
        tables: [String]
    ) async throws -> AsyncStream<Void> {
        await stop()
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        _ = try await SupabaseSessionManager.shared.authenticatedUserID()
        try await SupabaseRealtimeSession.prepare(client)
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        channels = tables.map { table in
            client.channel("\(channelPrefix)-\(table)-\(UUID().uuidString)")
        }
        subscriptions = zip(channels, tables).map { channel, table in
            channel.onPostgresChange(AnyAction.self, schema: "public", table: table) { _ in
                continuation.yield()
            }
        }
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        do {
            for channel in channels {
                try await channel.subscribeWithError()
            }
            return stream
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        if let client = SupabaseService.client {
            for channel in channels {
                await client.removeChannel(channel)
            }
        }
        channels = []
    }
}

actor SupabaseMarketMessageRealtimeRepository {
    static let shared = SupabaseMarketMessageRealtimeRepository()

    private var channel: RealtimeChannelV2?
    private var subscription: RealtimeSubscription?
    private var continuation: AsyncStream<Void>.Continuation?

    func events() async throws -> AsyncStream<Void> {
        await stop()
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }
        _ = try await SupabaseSessionManager.shared.authenticatedUserID()
        try await SupabaseRealtimeSession.prepare(client)
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let channel = client.channel("market-messages-\(UUID().uuidString)")
        subscription = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "market_messages"
        ) { _ in
            continuation.yield()
        }
        self.channel = channel
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        do {
            try await channel.subscribeWithError()
            return stream
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
        subscription?.cancel()
        subscription = nil
        if let channel, let client = SupabaseService.client {
            await client.removeChannel(channel)
        }
        channel = nil
    }
}

private struct MarketConversationParameters: Encodable, Sendable {
    let listingID: UUID

    enum CodingKeys: String, CodingKey {
        case listingID = "p_listing_id"
    }
}

private struct MarketChatWriteStatusParameters: Encodable, Sendable {
    let listingID: UUID
    let conversationID: UUID?

    enum CodingKeys: String, CodingKey {
        case listingID = "p_listing_id"
        case conversationID = "p_conversation_id"
    }
}

private struct MarketMessageInsert: Encodable, Sendable {
    let id: UUID
    let conversationID: UUID
    let senderID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case conversationID = "conversation_id"
        case senderID = "sender_id"
    }
}

private struct RemoteMarketConversation: Decodable, Sendable {
    let id: UUID
    let listingID: UUID
    let buyerID: UUID
    let createdAt: Date
    let lastMessageAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case listingID = "listing_id"
        case buyerID = "buyer_id"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
    }
}

private struct RemoteSellerMarketConversation: Decodable, Sendable {
    let id: UUID
    let listingID: UUID
    let buyerID: UUID
    let createdAt: Date
    let lastMessageAt: Date?
    let buyer: RemoteMarketChatProfile

    enum CodingKeys: String, CodingKey {
        case id, buyer
        case listingID = "listing_id"
        case buyerID = "buyer_id"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
    }
}

private struct RemoteMarketChatProfile: Decodable, Sendable {
    let displayName: String
    let handle: String?
    let avatarInitials: String
    let accentHex: String

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case avatarInitials = "avatar_initials"
        case accentHex = "accent_hex"
    }
}

private struct RemoteMarketMessage: Decodable, Sendable {
    let id: UUID
    let conversationID: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date

    var snapshot: MarketMessageSnapshot {
        MarketMessageSnapshot(
            id: id,
            conversationID: conversationID,
            senderID: senderID,
            body: body,
            createdAt: createdAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, body
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case createdAt = "created_at"
    }
}

enum MarketChatError: LocalizedError {
    case emptyMessage
    case messageTooLong

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            "메시지를 입력해 주세요."
        case .messageTooLong:
            "메시지는 2,000자 이하로 입력해 주세요."
        }
    }
}
