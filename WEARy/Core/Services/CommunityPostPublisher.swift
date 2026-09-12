import Foundation
import Supabase

protocol CommunityPostPublishing: Sendable {
    func publish(_ draft: CommunityPostPublishDraft) async throws -> UUID
}

struct CommunityPostPublishDraft: Sendable {
    let sourceOutfitID: UUID
    let caption: String
    let tags: [String]
    let photoData: Data
    let items: [CommunityPostPublishItem]
}

struct CommunityPostPublishItem: Sendable {
    let sourceGarmentID: UUID
    let name: String
    let brand: String
    let categoryRaw: String
    let size: String
    let colorHex: String
    let imageData: Data?
}

actor SupabaseCommunityPostPublisher: CommunityPostPublishing {
    static let shared = SupabaseCommunityPostPublisher()

    private let bucket = "community-media"
    private let maximumFileSize = 10 * 1_024 * 1_024

    func publish(_ draft: CommunityPostPublishDraft) async throws -> UUID {
        guard let client = SupabaseService.client else {
            throw SupabaseServiceError.missingConfiguration
        }

        let userID = try await SupabaseSessionManager.shared.authenticatedUserID()
        let postID = UUID()
        var uploadedPaths: [String] = []
        var didCreatePost = false

        do {
            try await client
                .from("posts")
                .insert(PostInsert(
                    id: postID,
                    authorID: userID,
                    sourcePrivateID: draft.sourceOutfitID,
                    caption: draft.caption,
                    tags: draft.tags,
                    visibility: "private"
                ))
                .execute()
            didCreatePost = true

            let photo = try mediaFile(from: draft.photoData)
            let photoPath = "\(userID.uuidString)/\(postID.uuidString)/look.\(photo.fileExtension)"
            try await upload(photo, to: photoPath, using: client)
            uploadedPaths.append(photoPath)

            try await client
                .from("post_media")
                .insert(PostMediaInsert(postID: postID, storagePath: photoPath, sortOrder: 0))
                .execute()

            var itemRows: [PostItemInsert] = []
            itemRows.reserveCapacity(draft.items.count)

            for (index, item) in draft.items.enumerated() {
                let itemID = UUID()
                var imagePath: String?

                if let imageData = item.imageData {
                    let image = try mediaFile(from: imageData)
                    let path = "\(userID.uuidString)/\(postID.uuidString)/items/\(item.sourceGarmentID.uuidString).\(image.fileExtension)"
                    try await upload(image, to: path, using: client)
                    uploadedPaths.append(path)
                    imagePath = path
                }

                itemRows.append(PostItemInsert(
                    id: itemID,
                    postID: postID,
                    sourcePrivateID: item.sourceGarmentID,
                    nameSnapshot: item.name,
                    brandSnapshot: item.brand,
                    categorySnapshot: item.categoryRaw,
                    sizeSnapshot: item.size,
                    colorHexSnapshot: item.colorHex,
                    imageStoragePath: imagePath,
                    sortOrder: index
                ))
            }

            if !itemRows.isEmpty {
                try await client
                    .from("post_items")
                    .insert(itemRows)
                    .execute()
            }

            try await client
                .from("posts")
                .update(PostVisibilityUpdate(visibility: "public"))
                .eq("id", value: postID.uuidString)
                .execute()

            return postID
        } catch {
            if !uploadedPaths.isEmpty {
                _ = try? await client.storage.from(bucket).remove(paths: uploadedPaths)
            }
            if didCreatePost {
                _ = try? await client
                    .from("posts")
                    .delete()
                    .eq("id", value: postID.uuidString)
                    .execute()
            }
            throw error
        }
    }

    private func upload(
        _ media: CommunityMediaFile,
        to path: String,
        using client: SupabaseClient
    ) async throws {
        guard media.data.count <= maximumFileSize else {
            throw CommunityPostPublishingError.imageTooLarge
        }

        try await client.storage.from(bucket).upload(
            path,
            data: media.data,
            options: FileOptions(contentType: media.contentType, upsert: false)
        )
    }

    private func mediaFile(from data: Data) throws -> CommunityMediaFile {
        let bytes = [UInt8](data.prefix(12))

        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return CommunityMediaFile(data: data, fileExtension: "jpg", contentType: "image/jpeg")
        }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return CommunityMediaFile(data: data, fileExtension: "png", contentType: "image/png")
        }
        if bytes.count >= 12,
           String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" {
            return CommunityMediaFile(data: data, fileExtension: "webp", contentType: "image/webp")
        }
        if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            let isHEIF = brand == "mif1" || brand == "msf1"
            return CommunityMediaFile(
                data: data,
                fileExtension: isHEIF ? "heif" : "heic",
                contentType: isHEIF ? "image/heif" : "image/heic"
            )
        }

        throw CommunityPostPublishingError.unsupportedImageFormat
    }
}

private struct CommunityMediaFile: Sendable {
    let data: Data
    let fileExtension: String
    let contentType: String
}

private struct PostInsert: Encodable, Sendable {
    let id: UUID
    let authorID: UUID
    let sourcePrivateID: UUID
    let caption: String
    let tags: [String]
    let visibility: String

    enum CodingKeys: String, CodingKey {
        case id, caption, tags, visibility
        case authorID = "author_id"
        case sourcePrivateID = "source_private_id"
    }
}

private struct PostMediaInsert: Encodable, Sendable {
    let postID: UUID
    let storagePath: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
    }
}

private struct PostItemInsert: Encodable, Sendable {
    let id: UUID
    let postID: UUID
    let sourcePrivateID: UUID
    let nameSnapshot: String
    let brandSnapshot: String
    let categorySnapshot: String
    let sizeSnapshot: String
    let colorHexSnapshot: String
    let imageStoragePath: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case sourcePrivateID = "source_private_id"
        case nameSnapshot = "name_snapshot"
        case brandSnapshot = "brand_snapshot"
        case categorySnapshot = "category_snapshot"
        case sizeSnapshot = "size_snapshot"
        case colorHexSnapshot = "color_hex_snapshot"
        case imageStoragePath = "image_storage_path"
        case sortOrder = "sort_order"
    }
}

private struct PostVisibilityUpdate: Encodable, Sendable {
    let visibility: String
}

enum CommunityPostPublishingError: LocalizedError {
    case imageTooLarge
    case unsupportedImageFormat

    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            "사진 한 장은 10MB 이하여야 합니다."
        case .unsupportedImageFormat:
            "지원하지 않는 사진 형식입니다."
        }
    }
}
