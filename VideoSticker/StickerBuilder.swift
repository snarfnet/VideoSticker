import UIKit

/// 動画フレーム列から1個の動くスタンプ（APNG）を組み立てる。
enum StickerBuilder {
    static let fit = CGSize(width: 320, height: 270)   // LINE動くスタンプ最大
    static let sizeLimit = 300_000                     // 300KB

    struct Result {
        let apng: Data
        let preview: [UIImage]   // 文言込みの各フレーム（同サイズ）
        let bytes: Int
    }

    /// 背景処理＋人物枠切り＋LINEサイズ化まで（文言は焼き込まない）。
    /// 文言だけ変えるときは prepare をやり直さず compose だけ呼べばよい（再セグメンテーション不要）。
    /// - Parameters:
    ///   - rawFrames: 動画から抜いた素フレーム
    ///   - removeBG: 背景を消すなら true、残すなら false
    static func prepare(rawFrames: [UIImage], removeBG: Bool) -> [UIImage] {
        guard !rawFrames.isEmpty else { return [] }

        // 処理を軽くするため長辺600へ縮小。
        let work = rawFrames.map { resize($0, longSide: 600) }

        // 背景除去（残す場合は素のまま＝全面不透明）。
        let cut = removeBG ? work.map { PersonSegmenter.removeBackground($0) } : work

        // 全フレームの人物bboxを統合（ジッタ防止に共通枠で切る）。
        var union: CGRect? = nil
        for f in cut {
            guard let bb = alphaBBox(f) else { continue }
            union = union == nil ? bb : union!.union(bb)
        }
        let crop = union ?? CGRect(origin: .zero, size: cut[0].size)
        let padded = crop.insetBy(dx: -8, dy: -8)

        // 共通枠で切り、LINE枠へ拡縮（必ず片辺が320か270に接する）。
        let cropped = cut.map { cropPixels($0, rect: padded) }
        let cw = cropped[0].size.width
        let ch = cropped[0].size.height
        let scale = min(fit.width / cw, fit.height / ch)
        let target = CGSize(width: max(1, round(cw * scale)), height: max(1, round(ch * scale)))
        return cropped.map { resizeExact($0, to: target) }
    }

    /// prepare 済みフレームへ文言を焼き込み、300KB以内のAPNGへ。
    static func compose(baseFrames: [UIImage], caption: Caption) -> Result? {
        guard !baseFrames.isEmpty else { return nil }
        var shrink: CGFloat = 1.0
        let base = baseFrames[0].size
        for _ in 0..<6 {
            let sz = CGSize(width: max(1, round(base.width * shrink)),
                            height: max(1, round(base.height * shrink)))
            let frames = baseFrames.map { img -> UIImage in
                let scaled = shrink < 1.0 ? resizeExact(img, to: sz) : img
                return CaptionRenderer.draw(on: scaled, caption: caption)
            }
            if let data = APNGEncoder.encode(frames: frames, totalDuration: 1.0) {
                if data.count <= sizeLimit || shrink <= 0.6 {
                    return Result(apng: data, preview: frames, bytes: data.count)
                }
            }
            shrink -= 0.1
        }
        return nil
    }

    // MARK: - 画像ユーティリティ（scale=1で点=ピクセルを固定）

    private static func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = false
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt)
    }

    static func resize(_ image: UIImage, longSide: CGFloat) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let long = max(w, h)
        guard long > longSide else { return normalized(image) }
        let s = longSide / long
        return resizeExact(image, to: CGSize(width: round(w * s), height: round(h * s)))
    }

    static func resizeExact(_ image: UIImage, to size: CGSize) -> UIImage {
        renderer(size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// scale=1 の素直なビットマップへ正規化。
    static func normalized(_ image: UIImage) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        return resizeExact(image, to: CGSize(width: w, height: h))
    }

    static func cropPixels(_ image: UIImage, rect: CGRect) -> UIImage {
        let bounds = CGRect(origin: .zero, size: image.size)
        let r = rect.intersection(bounds)
        let target = r.isNull || r.isEmpty ? bounds : r
        return renderer(target.size).image { _ in
            image.draw(in: CGRect(x: -target.minX, y: -target.minY,
                                  width: image.size.width, height: image.size.height))
        }
    }

    /// 非透明領域の外接矩形（ピクセル座標）。不透明画像なら全面を返す。
    static func alphaBBox(_ image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w {
                if pixels[row + x * 4 + 3] > 12 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        if maxX < minX || maxY < minY { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
