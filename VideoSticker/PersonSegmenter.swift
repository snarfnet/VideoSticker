import Vision
import CoreImage
import UIKit

/// Vision の人物セグメンテーションで背景を透過する。
/// 背景が何色でも人物だけを抜けるので、白背景フラッドフィル方式の弱点（白服が消える等）が出ない。
enum PersonSegmenter {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 背景を透過した UIImage を返す。失敗時は元画像をそのまま返す。
    static func removeBackground(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let ci = CIImage(cgImage: cg)

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return image
        }
        guard let mask = request.results?.first?.pixelBuffer else { return image }

        var maskCI = CIImage(cvPixelBuffer: mask)
        // マスクを元画像サイズへ合わせる。
        let sx = ci.extent.width / maskCI.extent.width
        let sy = ci.extent.height / maskCI.extent.height
        maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        let clear = CIImage(color: .clear).cropped(to: ci.extent)
        guard let blend = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: ci,
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: maskCI,
        ])?.outputImage else { return image }

        guard let out = ciContext.createCGImage(blend, from: ci.extent) else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }
}
