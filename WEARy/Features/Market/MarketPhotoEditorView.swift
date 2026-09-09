import PhotosUI
import SwiftUI
import UIKit

struct MarketPhotoEditorView: View {
    @Binding var images: [Data]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false

    private let maximumPhotoCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("추가 사진")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(images.count)/\(maximumPhotoCount)")
                    .font(.caption)
                    .foregroundStyle(WEARyTheme.secondaryInk)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                        photoThumbnail(data, at: index)
                    }

                    if images.count < maximumPhotoCount {
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: maximumPhotoCount - images.count,
                            matching: .images
                        ) {
                            VStack(spacing: 7) {
                                Image(systemName: "plus")
                                    .font(.title2.weight(.semibold))
                                Text("사진 추가")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(WEARyTheme.ink)
                            .frame(width: 92, height: 112)
                            .background(WEARyTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(WEARyTheme.line, style: StrokeStyle(lineWidth: 1, dash: [5]))
                            }
                        }
                        .disabled(isLoading)
                        .accessibilityIdentifier("market.addPhotos")
                    }
                }
                .padding(.vertical, 2)
            }

            Text("기본 옷 사진 다음에 표시됩니다. 최대 8장까지 추가할 수 있어요.")
                .font(.caption)
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .onChange(of: selectedItems) {
            guard !selectedItems.isEmpty else { return }
            Task { await appendSelectedPhotos() }
        }
    }

    private func photoThumbnail(_ data: Data, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(WEARyTheme.secondaryInk)
                }
            }
            .frame(width: 92, height: 112)
            .background(WEARyTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .clipped()
            .accessibilityIdentifier("market.galleryPhoto.\(index)")

            Button {
                images.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.7))
            }
            .padding(5)
            .accessibilityLabel("추가 사진 \(index + 1) 삭제")
        }
    }

    @MainActor
    private func appendSelectedPhotos() async {
        isLoading = true
        defer {
            selectedItems = []
            isLoading = false
        }

        for item in selectedItems where images.count < maximumPhotoCount {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let optimized = optimizedImageData(data) else { continue }
            images.append(optimized)
        }
    }

    private func optimizedImageData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, 1_600 / longestSide)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: targetSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}
