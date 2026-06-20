import Vision
import UIKit

/// 動画フレームから動きを判定して Gesture バケツへ振り分ける。
/// 完全自動の一点当ては誤爆するので、ここでは粗いバケツ判定に徹する（UI側でスワイプ微調整）。
enum GestureClassifier {

    /// 各フレームを個別に判定する。動きが取れなかったフレームは nil。
    /// 1本の動画から複数の動きを拾い、バケツ別に振り分けるために使う。
    static func classifyEach(_ frames: [UIImage]) -> [Gesture?] {
        frames.map { classifyOne($0) }
    }

    static func classifyOne(_ image: UIImage) -> Gesture? {
        guard let cg = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])

        let bodyReq = VNDetectHumanBodyPoseRequest()
        let handReq = VNDetectHumanHandPoseRequest()
        handReq.maximumHandCount = 2
        try? handler.perform([bodyReq, handReq])

        let body = bodyReq.results?.first
        let hands = handReq.results ?? []

        // --- 体の主要点（正規化座標, 原点は左下, yは上向き）---
        func bp(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let body, let p = try? body.recognizedPoint(j), p.confidence > 0.2 else { return nil }
            return p.location
        }
        let nose = bp(.nose)
        let lSh = bp(.leftShoulder); let rSh = bp(.rightShoulder)
        let lWr = bp(.leftWrist); let rWr = bp(.rightWrist)
        let shY: CGFloat? = {
            let ys = [lSh?.y, rSh?.y].compactMap { $0 }
            return ys.isEmpty ? nil : ys.reduce(0, +) / CGFloat(ys.count)
        }()
        let wristTop: CGFloat? = [lWr?.y, rWr?.y].compactMap { $0 }.max()

        // --- 手の開き・OK判定 ---
        let handStates = hands.map { handOpenness($0) }
        let anyOK = handStates.contains { $0 == .ok }
        let anyOpen = handStates.contains { $0 == .open }
        let anyFist = handStates.contains { $0 == .fist }

        // 1) OKサイン（指のつまみ）
        if anyOK { return .ok }

        // 2) 手を頭より上へ挙げている
        if let wt = wristTop, let n = nose?.y, wt > n + 0.02 {
            if anyOpen { return .wave }
            if anyFist { return .fist }
            return .wave   // 手の判定が取れなくても高く挙げてれば挨拶寄り
        }

        // 3) 頭を下げている＝お辞儀（鼻が肩より下、もしくは鼻が極端に低い）
        if let n = nose?.y, let sy = shY, n < sy + 0.03 {
            return .bow
        }
        if let n = nose?.y, n < 0.45 { return .bow }

        // 4) 肩あたりで手のひらを前に＝待って
        if let wt = wristTop, let sy = shY, abs(wt - sy) < 0.18, anyOpen {
            return .palm
        }

        // 5) ガッツ（肩付近で握りこぶし）
        if let wt = wristTop, let sy = shY, wt > sy - 0.05, anyFist {
            return .fist
        }

        // 体も手も弱い→判定保留
        if body == nil && hands.isEmpty { return nil }
        return .nod
    }

    // MARK: - 手の状態

    private enum HandState { case open, fist, ok, unknown }

    private static func handOpenness(_ obs: VNHumanHandPoseObservation) -> HandState {
        func pt(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let p = try? obs.recognizedPoint(j), p.confidence > 0.2 else { return nil }
            return p.location
        }
        guard let wrist = pt(.wrist) else { return .unknown }

        func dist(_ a: CGPoint?, _ b: CGPoint?) -> CGFloat? {
            guard let a, let b else { return nil }
            return hypot(a.x - b.x, a.y - b.y)
        }
        // 指が伸びているか: 指先が PIP より手首から遠ければ伸展。
        func extended(tip: VNHumanHandPoseObservation.JointName,
                      pip: VNHumanHandPoseObservation.JointName) -> Bool {
            guard let dt = dist(pt(tip), wrist), let dp = dist(pt(pip), wrist) else { return false }
            return dt > dp * 1.08
        }
        let idx = extended(tip: .indexTip, pip: .indexPIP)
        let mid = extended(tip: .middleTip, pip: .middlePIP)
        let rng = extended(tip: .ringTip, pip: .ringPIP)
        let lit = extended(tip: .littleTip, pip: .littlePIP)
        let extCount = [idx, mid, rng, lit].filter { $0 }.count

        // OK: 親指先と人差し指先が近接 ＋ 中/薬/小が伸展
        if let pinch = dist(pt(.thumbTip), pt(.indexTip)),
           let span = dist(pt(.indexMCP), wrist), span > 0,
           pinch < span * 0.45, mid, rng {
            return .ok
        }
        if extCount >= 3 { return .open }
        if extCount <= 1 { return .fist }
        return .unknown
    }
}
