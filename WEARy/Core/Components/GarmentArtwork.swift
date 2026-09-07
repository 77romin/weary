import SwiftUI

struct GarmentArtwork: View {
    let garment: Garment
    var height: CGFloat = 180

    var body: some View {
        ZStack {
            Color(hex: garment.colorHex).opacity(0.82)

            Circle()
                .fill(.white.opacity(0.2))
                .frame(width: height * 0.86)
                .offset(x: height * 0.35, y: -height * 0.3)

            if let data = garment.cutoutImageData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(height * 0.08)
            } else if let data = garment.imageData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: garment.category.symbol)
                    .font(.system(size: height * 0.28, weight: .light))
                    .foregroundStyle(WEARyTheme.ink.opacity(0.84))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(height: height)
        .clipped()
        .accessibilityLabel("\(garment.name) 이미지")
    }
}

struct GarmentCutoutThumbnail: View {
    let garment: Garment

    var body: some View {
        Group {
            if let data = garment.cutoutImageData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
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

struct MetricPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
