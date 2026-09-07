import CoreImage
import CoreImage.CIFilterBuiltins
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
            let longestSide = max(outputImage.extent.width, outputImage.extent.height)
            let thumbnailScale = min(1, 640 / longestSide)
            let thumbnail = outputImage.transformed(
                by: CGAffineTransform(scaleX: thumbnailScale, y: thumbnailScale)
            )
            let context = CIContext(options: [.useSoftwareRenderer: false])
            return context.pngRepresentation(
                of: thumbnail,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        } catch {
            return nil
        }
    }
}
