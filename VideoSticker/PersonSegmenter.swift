import Vision
import CoreImage
import CoreVideo
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

        // マスク(OneComponent8)の生バイトを直接読む。
        // CIImage(cvPixelBuffer:) は単一チャンネルをどのチャンネルへ載せるか端末依存で曖昧で、
        // 輝度が常に白扱いになると CIBlendWithMask が全面を前景と見なし背景が消えない。
        // 生値からグレースケール画像を組み直せば解釈が一意になる（人物=255, 背景=0）。
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        let mw = CVPixelBufferGetWidth(mask)
        let mh = CVPixelBufferGetHeight(mask)
        let mbpr = CVPixelBufferGetBytesPerRow(mask)
        guard mw > 0, mh > 0, let mbase = CVPixelBufferGetBaseAddress(mask) else {
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            return image
        }
        let srcBytes = mbase.assumingMemoryBound(to: UInt8.self)
        var bytes = [UInt8](repeating: 0, count: mw * mh)
        var sum = 0
        for y in 0..<mh {
            let row = y * mbpr
            for x in 0..<mw {
                let v = srcBytes[row + x]
                bytes[y * mw + x] = v
                sum += Int(v)
            }
        }
        CVPixelBufferUnlockBaseAddress(mask, .readOnly)

        // ほぼ空のマスク（人物未検出）なら透明化せず元画像を返す。
        if sum / (mw * mh) < 4 { return image }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let maskCG = CGImage(width: mw, height: mh, bitsPerComponent: 8, bitsPerPixel: 8,
                                   bytesPerRow: mw, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true,
                                   intent: .defaultIntent)
        else { return image }

        // 境界を少し締めて背景の薄残りを消す（輝度のみ操作）。
        var maskCI = CIImage(cgImage: maskCG).applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 2.0,
        ])

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
