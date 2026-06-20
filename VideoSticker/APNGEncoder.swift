import ImageIO
import UniformTypeIdentifiers
import UIKit

/// 複数フレームを APNG にまとめる（ImageIO 利用、自前チャンク組みは不要）。
enum APNGEncoder {

    /// - Parameters:
    ///   - frames: 同じサイズの透過 UIImage 配列
    ///   - totalDuration: 全体の再生秒数（LINE動くスタンプは1〜4秒）
    ///   - loop: 0 で無限ループ
    static func encode(frames: [UIImage], totalDuration: Double = 1.0, loop: Int = 0) -> Data? {
        guard !frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, frames.count, nil) else { return nil }

        let top = [kCGImagePropertyPNGDictionary as String:
                    [kCGImagePropertyAPNGLoopCount as String: loop]]
        CGImageDestinationSetProperties(dest, top as CFDictionary)

        let delay = totalDuration / Double(frames.count)
        let frameProps = [kCGImagePropertyPNGDictionary as String:
                            [kCGImagePropertyAPNGDelayTime as String: delay]]

        for f in frames {
            guard let cg = f.cgImage else { continue }
            CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
