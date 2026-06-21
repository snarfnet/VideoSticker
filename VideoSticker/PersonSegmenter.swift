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

        // マスクがほぼ空（人物未検出）なら透明化せず元画像を返す。
        // これがないと人物を拾えない動画でスタンプが真っ透明になる。
        if let avg = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: maskCI,
            kCIInputExtentKey: CIVector(cgRect: maskCI.extent),
        ])?.outputImage {
            var px: [UInt8] = [0, 0, 0, 0]
            ciContext.render(avg, toBitmap: &px, rowBytes: 4,
                             bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                             format: .RGBA8, colorSpace: nil)
            if px[0] < 12 { return image }   // 平均マスク値が低い＝人物がほぼ写っていない
        }

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
