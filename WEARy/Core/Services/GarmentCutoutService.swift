import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation
import Vision

actor GarmentCutoutService {
    static let shared = GarmentCutoutService()

    func makeCutout(from imageData: Data) -> Data? {
        guard let sourceImage = CIImage(data: imageData) else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: sourceImage)

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }

            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            let maskImage = CIImage(cvPixelBuffer: maskBuffer)
            let transparentBackground = CIImage(color: .clear).cropped(to: sourceImage.extent)

            let blend = CIFilter.blendWithMask()
            blend.inputImage = sourceImage
            blend.backgroundImage = transparentBackground
            blend.maskImage = maskImage

            guard let outputImage = blend.outputImage else { return nil }
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let renderedImage = context.createCGImage(outputImage, from: outputImage.extent),
                  let croppedImage = Self.cropToVisibleContent(renderedImage) else {
                return nil
            }

            let croppedCIImage = CIImage(cgImage: croppedImage)
            let longestSide = max(croppedCIImage.extent.width, croppedCIImage.extent.height)
            let thumbnailScale = min(1, 640 / longestSide)
            let thumbnail = croppedCIImage.transformed(
                by: CGAffineTransform(scaleX: thumbnailScale, y: thumbnailScale)
            )
            return context.pngRepresentation(
                of: thumbnail,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        } catch {
            return nil
        }
    }

    nonisolated static func cropToVisibleContent(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let bitmapContext = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        bitmapContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        bitmapContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        let visibleAlphaThreshold: UInt8 = 8

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * bytesPerRow) + (x * bytesPerPixel) + 3]
                guard alpha > visibleAlphaThreshold else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY,
              let normalizedImage = bitmapContext.makeImage() else {
            return nil
        }

        let contentWidth = maxX - minX + 1
        let contentHeight = maxY - minY + 1
        let padding = max(2, Int(ceil(Double(max(contentWidth, contentHeight)) * 0.04)))
        let cropX = max(0, minX - padding)
        let cropY = max(0, minY - padding)
        let cropMaxX = min(width - 1, maxX + padding)
        let cropMaxY = min(height - 1, maxY + padding)
        let cropRect = CGRect(
            x: cropX,
            y: cropY,
            width: cropMaxX - cropX + 1,
            height: cropMaxY - cropY + 1
        )

        return normalizedImage.cropping(to: cropRect)
    }
}
