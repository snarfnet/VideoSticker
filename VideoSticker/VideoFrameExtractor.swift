import AVFoundation
import UIKit

/// 動画から等間隔で N フレームを取り出す。
enum VideoFrameExtractor {
    /// - Parameters:
    ///   - url: 動画ファイル
    ///   - count: 取り出す枚数（=スタンプのフレーム数。LINEは8/16/24msではなく枚数自由だが本アプリは6固定）
    /// - Returns: 先頭→末尾の順に並んだ UIImage 配列
    static func extract(from url: URL, count: Int = 6) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true   // 撮影向きを反映
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero

        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            return []
        }
        let total = CMTimeGetSeconds(duration)
        guard total > 0 else { return [] }

        // 端は動きが切れがちなので、内側 8%〜92% を等間隔に刻む。
        let start = total * 0.08
        let span = total * 0.84
        var times: [NSValue] = []
        for i in 0..<count {
            let t = start + span * Double(i) / Double(max(1, count - 1))
            times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
        }

        var frames: [UIImage] = []
        for value in times {
            if let cg = try? gen.copyCGImage(at: value.timeValue, actualTime: nil) {
                frames.append(UIImage(cgImage: cg))
            }
        }
        return frames
    }
}
