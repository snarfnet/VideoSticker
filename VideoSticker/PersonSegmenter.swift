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

        // マスクのコントラストを立てて背景の薄残り（甘さ）を消す。
        // 0.45〜0.75 を 0〜1 へ引き伸ばし、境界を人物側へ少し引き締める＝背景のヘイズを除去。
        // scale = 1/(0.75-0.45) ≈ 3.333, bias = -0.45*scale = -1.5
        let s: CGFloat = 3.333
        maskCI = maskCI.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: s, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: s, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: s, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: s),
            "inputBiasVector": CIVector(x: -1.5, y: -1.5, z: -1.5, w: -1.5),
        ]).applyingFilter("CIColorClamp")

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
